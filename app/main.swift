import AppKit
import CoreServices

// Claude status light: a coloured dot in the menu bar for all running Claude Code sessions.
// grey = idle, green = working, yellow = needs you, red = something went wrong (worst session wins).
// State: one file per session in ~/.claude-status ("state|project|event", mtime = last news),
// written by bin/report.sh from Claude Code hooks.
// Cheap by design: no polling. FSEvents wakes the app only when a file changes, the blink timer
// exists only while a session needs attention, one slow timer drops dead sessions.

enum Level: Int { case idle = 0, working, attention, error }

struct Session {
    var id: String
    var project: String
    var level: Level
    var ts: Double
}

let stateDir = ProcessInfo.processInfo.environment["CLAUDE_STATUS_DIR"]
    ?? NSString(string: "~/.claude-status").expandingTildeInPath
let staleWorking: Double = 30 * 60   // "working" with no news for 30 min: the session probably died
let dropAfter: Double = 12 * 3600

func readSessions() -> [Session] {
    let fm = FileManager.default
    guard let names = try? fm.contentsOfDirectory(atPath: stateDir) else { return [] }
    let now = Date().timeIntervalSince1970
    var out: [Session] = []
    for n in names where !n.hasPrefix(".") {
        let path = stateDir + "/" + n
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970,
              let data = fm.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else { continue }
        if now - mtime > dropAfter { try? fm.removeItem(atPath: path); continue }
        let f = text.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 2 else { continue }   // half-written: the next event repairs it
        var level: Level
        switch f[0] {
        case "working": level = .working
        case "attention": level = .attention
        case "error": level = .error
        default: level = .idle
        }
        if level == .working && now - mtime > staleWorking { level = .idle }
        out.append(Session(id: n, project: f[1].isEmpty ? "?" : f[1], level: level, ts: mtime))
    }
    return out.sorted { $0.level.rawValue != $1.level.rawValue ? $0.level.rawValue > $1.level.rawValue : $0.ts > $1.ts }
}

func color(_ l: Level) -> NSColor {
    switch l {
    case .idle: return NSColor.systemGray
    case .working: return NSColor.systemGreen
    case .attention: return NSColor.systemYellow
    case .error: return NSColor.systemRed
    }
}

func label(_ l: Level) -> String {
    switch l {
    case .idle: return "idle"
    case .working: return "working"
    case .attention: return "needs you"
    case .error: return "error"
    }
}

func makeDot(_ c: NSColor, alpha: CGFloat) -> NSImage {
    // Full menu bar height (22-24pt, taller on notched screens), with a 2pt margin.
    let h = NSStatusBar.system.thickness
    let img = NSImage(size: NSSize(width: h, height: h))
    img.lockFocus()
    c.withAlphaComponent(alpha).setFill()
    let r = NSRect(x: 2, y: 2, width: h - 4, height: h - 4)
    NSBezierPath(ovalIn: r).fill()
    NSColor.black.withAlphaComponent(0.35 * alpha).setStroke()
    NSBezierPath(ovalIn: r).stroke()
    img.unlockFocus()
    img.isTemplate = false
    return img
}

// Eight images drawn once: four colours, bright and dim.
let dots: [[NSImage]] = [Level.idle, .working, .attention, .error].map { l in
    [makeDot(color(l), alpha: 1), makeDot(color(l), alpha: 0.25)]
}

func ago(_ secs: Double) -> String {
    let s = Int(max(0, secs))
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m" }
    return "\(s / 3600)h"
}

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var sessions: [Session] = []
    var lastLevels: [String: Level] = [:]
    var blinkTimer: Timer?
    var blinkDim = false
    var stream: FSEventStreamRef?
    var pending = false
    let defaults = UserDefaults.standard

    var notifyOn: Bool { defaults.object(forKey: "notify") as? Bool ?? true }
    var soundOn: Bool { defaults.object(forKey: "sound") as? Bool ?? false }
    var worst: Level { sessions.map { $0.level }.max { $0.rawValue < $1.rawValue } ?? .idle }

    func applicationDidFinishLaunching(_ n: Notification) {
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        refresh()
        startWatching()
        // Dead sessions never send "end": look for them once a minute (tolerance lets macOS coalesce the wake-up).
        let t = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in self.refresh() }
        t.tolerance = 30
        // Keep the installed hook script in step with this build; offer to connect once on first run.
        if isConnected() { try? installScript() }
        else if !defaults.bool(forKey: "offeredConnect") {
            defaults.set(true, forKey: "offeredConnect")
            DispatchQueue.main.async { connect() }
        }
    }

    func startWatching() {
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info = info else { return }
            Unmanaged<App>.fromOpaque(info).takeUnretainedValue().scheduleRefresh()
        }
        stream = FSEventStreamCreate(nil, cb, &ctx, [stateDir] as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents))
        if let s = stream {
            FSEventStreamSetDispatchQueue(s, DispatchQueue.main)
            FSEventStreamStart(s)
        }
    }

    func scheduleRefresh() {
        if pending { return }
        pending = true
        DispatchQueue.main.async { self.pending = false; self.refresh() }
    }

    func refresh() {
        let new = readSessions()
        for s in new where (s.level == .attention || s.level == .error) && lastLevels[s.id] != s.level { notify(s) }
        lastLevels = Dictionary(new.map { ($0.id, $0.level) }, uniquingKeysWith: { a, _ in a })
        sessions = new
        let w = worst
        blinkDim = false
        item.button?.image = dots[w.rawValue][0]
        item.button?.toolTip = "Claude: " + label(w)
        // The blink timer only lives while somebody needs attention.
        if w == .attention || w == .error {
            if blinkTimer == nil {
                blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { _ in
                    self.blinkDim.toggle()
                    self.item.button?.image = dots[self.worst.rawValue][self.blinkDim ? 1 : 0]
                }
            }
        } else {
            blinkTimer?.invalidate()
            blinkTimer = nil
        }
    }

    func notify(_ s: Session) {
        if soundOn { NSSound(named: NSSound.Name(s.level == .error ? "Basso" : "Glass"))?.play() }
        guard notifyOn else { return }
        let text = "\(s.project): \(label(s.level))"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "display notification \"\(text)\" with title \"Claude Code\""]
        try? p.run()
    }

    // The menu is built only when it is opened.
    func menuNeedsUpdate(_ m: NSMenu) {
        m.removeAllItems()
        let head = NSMenuItem(title: sessions.isEmpty ? (isConnected() ? "No Claude sessions" : "Not connected to Claude Code") : "Claude sessions", action: nil, keyEquivalent: "")
        head.isEnabled = false
        m.addItem(head)
        let now = Date().timeIntervalSince1970
        for s in sessions {
            let it = NSMenuItem(title: "\(s.project) — \(label(s.level)) (\(ago(now - s.ts)))", action: nil, keyEquivalent: "")
            it.image = dots[s.level.rawValue][0]
            it.isEnabled = false
            m.addItem(it)
        }
        m.addItem(.separator())
        let connected = isConnected()
        let cc = NSMenuItem(title: connected ? "Disconnect from Claude Code…" : "Connect to Claude Code…",
                            action: #selector(toggleConnect), keyEquivalent: "")
        cc.target = self
        m.addItem(cc)
        let li = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        li.target = self
        li.state = opensAtLogin ? .on : .off
        m.addItem(li)
        let n = NSMenuItem(title: "Notifications", action: #selector(toggleNotify), keyEquivalent: "")
        n.target = self
        n.state = notifyOn ? .on : .off
        m.addItem(n)
        let so = NSMenuItem(title: "Sound", action: #selector(toggleSound), keyEquivalent: "")
        so.target = self
        so.state = soundOn ? .on : .off
        m.addItem(so)
        let c = NSMenuItem(title: "Forget all sessions", action: #selector(clearAll), keyEquivalent: "")
        c.target = self
        m.addItem(c)
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc func toggleConnect() { isConnected() ? disconnect() : connect() }
    @objc func toggleLogin() { toggleOpenAtLogin() }
    @objc func toggleNotify() { defaults.set(!notifyOn, forKey: "notify") }
    @objc func toggleSound() { defaults.set(!soundOn, forKey: "sound") }
    @objc func clearAll() {
        let fm = FileManager.default
        for n in (try? fm.contentsOfDirectory(atPath: stateDir)) ?? [] where !n.hasPrefix(".") {
            try? fm.removeItem(atPath: stateDir + "/" + n)
        }
        refresh()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon
let delegate = App()
app.delegate = delegate
app.run()
