import AppKit
import ServiceManagement

// Connecting to Claude Code: our hooks go into ~/.claude/settings.json, which the CLI, the desktop
// app's Code tab and the IDE extensions all read. The hook script is copied out of the app bundle,
// so moving or deleting the app (or macOS running it from a random translocated path) breaks nothing.
// Every change asks first, keeps a backup and leaves everyone else's settings and hooks alone.

let settingsPath = ProcessInfo.processInfo.environment["CLAUDE_STATUS_SETTINGS"]   // override for tests
    ?? NSString(string: "~/.claude/settings.json").expandingTildeInPath
let scriptDir = NSString(string: "~/Library/Application Support/ClaudeStatus").expandingTildeInPath
let scriptPath = scriptDir + "/report.sh"

// event -> (state passed to report.sh, matcher)
let hookEvents: [(String, String, String?)] = [
    ("SessionStart", "idle", nil),
    ("UserPromptSubmit", "working", nil),
    ("PreToolUse", "working", nil),
    ("PostToolUse", "working", nil),
    ("PermissionRequest", "attention", nil),
    ("Notification", "attention", "permission_prompt|elicitation_dialog"),
    ("Stop", "idle", nil),
    ("StopFailure", "error", nil),
    ("SessionEnd", "end", nil),
]

// Ours: this app's script, or the pre-app layout (…/claude-status-light/bin/report.sh).
func isOurs(_ hook: Any) -> Bool {
    guard let cmd = (hook as? [String: Any])?["command"] as? String else { return false }
    return cmd.contains("report.sh") && (cmd.contains("ClaudeStatus/") || cmd.contains("claude-status"))
}

func ourGroups() -> [String: [String: Any]] {
    var out: [String: [String: Any]] = [:]
    for (event, state, matcher) in hookEvents {
        var g: [String: Any] = ["hooks": [["type": "command", "command": "\"\(scriptPath)\" \(state)", "async": true]]]
        if let m = matcher { g["matcher"] = m }
        out[event] = g
    }
    return out
}

enum SettingsError: Error { case unreadable(String) }

func loadSettings() throws -> [String: Any] {
    guard let data = FileManager.default.contents(atPath: settingsPath) else { return [:] }   // no file yet
    if data.isEmpty { return [:] }
    guard let obj = try? JSONSerialization.jsonObject(with: data), let dict = obj as? [String: Any] else {
        throw SettingsError.unreadable("~/.claude/settings.json is not valid JSON, so it was left untouched.")
    }
    return dict
}

// Settings with all of our hooks removed (and empty leftovers pruned), everything else as it was.
func withoutOurs(_ settings: [String: Any]) -> [String: Any] {
    var s = settings
    guard var hooks = s["hooks"] as? [String: Any] else { return s }
    for (event, value) in hooks {
        guard let groups = value as? [Any] else { continue }
        let kept: [Any] = groups.compactMap { g in
            guard var group = g as? [String: Any], let list = group["hooks"] as? [Any] else { return g }
            let rest = list.filter { !isOurs($0) }
            if rest.isEmpty { return nil }
            group["hooks"] = rest
            return group
        }
        hooks[event] = kept.isEmpty ? nil : kept
    }
    s["hooks"] = hooks.isEmpty ? nil : hooks
    return s
}

func isConnected() -> Bool {
    guard let s = try? loadSettings(), let hooks = s["hooks"] as? [String: Any] else { return false }
    return hooks.values.contains { ($0 as? [Any])?.contains { (($0 as? [String: Any])?["hooks"] as? [Any])?.contains(where: isOurs) ?? false } ?? false }
}

func writeSettings(_ s: [String: Any]) throws {
    let fm = FileManager.default
    try fm.createDirectory(atPath: (settingsPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    if fm.fileExists(atPath: settingsPath) {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        var bak = settingsPath + ".bak-claudestatus-" + f.string(from: Date())
        var n = 1
        while fm.fileExists(atPath: bak) { n += 1; bak = settingsPath + ".bak-claudestatus-" + f.string(from: Date()) + "-\(n)" }
        try fm.copyItem(atPath: settingsPath, toPath: bak)
    }
    let data = try JSONSerialization.data(withJSONObject: s, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try data.write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
}

// Copy the bundled script into place (also on every launch while connected, so updates reach it).
func installScript() throws {
    guard let src = Bundle.main.path(forResource: "report", ofType: "sh") else {
        throw SettingsError.unreadable("report.sh is missing from the app bundle.")
    }
    let fm = FileManager.default
    try fm.createDirectory(atPath: scriptDir, withIntermediateDirectories: true)
    let tmp = scriptPath + ".new"
    try? fm.removeItem(atPath: tmp)
    try fm.copyItem(atPath: src, toPath: tmp)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp)
    _ = try fm.replaceItemAt(URL(fileURLWithPath: scriptPath), withItemAt: URL(fileURLWithPath: tmp))
}

func ask(_ title: String, _ text: String, details: String? = nil, ok: String) -> Bool {
    NSApp.activate(ignoringOtherApps: true)
    let a = NSAlert()
    a.messageText = title
    a.informativeText = text
    if let d = details {
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 220))
        tv.string = d
        tv.isEditable = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let sv = NSScrollView(frame: tv.frame)
        sv.documentView = tv
        sv.hasVerticalScroller = true
        a.accessoryView = sv
    }
    a.addButton(withTitle: ok)
    a.addButton(withTitle: "Cancel")
    return a.runModal() == .alertFirstButtonReturn
}

func tell(_ title: String, _ text: String) {
    NSApp.activate(ignoringOtherApps: true)
    let a = NSAlert()
    a.messageText = title
    a.informativeText = text
    a.runModal()
}

func connect() {
    do {
        var s = withoutOurs(try loadSettings())
        var hooks = s["hooks"] as? [String: Any] ?? [:]
        let ours = ourGroups()
        for (event, group) in ours { hooks[event] = (hooks[event] as? [Any] ?? []) + [group] }
        s["hooks"] = hooks
        let block = try JSONSerialization.data(withJSONObject: ["hooks": ours], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        guard ask("Connect to Claude Code?",
                  "Adds these hooks to ~/.claude/settings.json (used by the Claude Code CLI, the Code tab of the Claude desktop app and the IDE extensions). A backup is saved next to it; your other settings and hooks stay as they are.\n\nThe hook only writes the session state, project folder name and event name to ~/.claude-status. Nothing is sent over the network.",
                  details: String(decoding: block, as: UTF8.self), ok: "Connect") else { return }
        try installScript()
        try writeSettings(s)
        tell("Connected", "Running Claude Code sessions pick this up on their next event.")
    } catch {
        tell("Could not connect", "\(error)")
    }
}

func disconnect() {
    do {
        let s = try loadSettings()
        guard ask("Disconnect from Claude Code?",
                  "Removes this app's hooks from ~/.claude/settings.json (a backup is saved next to it). Other hooks and settings stay.",
                  ok: "Disconnect") else { return }
        try writeSettings(withoutOurs(s))
        try? FileManager.default.removeItem(atPath: scriptPath)
        tell("Disconnected", "The light will stay grey until you connect again.")
    } catch {
        tell("Could not disconnect", "\(error)")
    }
}

var opensAtLogin: Bool { SMAppService.mainApp.status == .enabled }

func toggleOpenAtLogin() {
    do {
        if opensAtLogin { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        if SMAppService.mainApp.status == .requiresApproval {
            tell("Approve in System Settings", "Allow ClaudeStatus in System Settings → General → Login Items.")
            SMAppService.openSystemSettingsLoginItems()
        }
    } catch {
        tell("Could not change login item", "\(error)")
    }
}
