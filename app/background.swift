import Darwin

// Background commands: Claude Code runs every Bash tool call as a child shell
// ("<shell> -c source ~/.claude/shell-snapshots/… && eval '…'"). Once a turn has stopped, foreground
// calls are gone, so any such child still alive is a run_in_background command (MCP servers and hooks
// are started differently and never match). Found with two syscalls, no ps, no polling.

func parentPid(_ pid: pid_t) -> pid_t {
    var info = proc_bsdinfo()
    let n = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
    return n == Int32(MemoryLayout<proc_bsdinfo>.size) ? pid_t(info.pbi_ppid) : 0
}

func children(_ pid: pid_t) -> [pid_t] {
    var buf = [pid_t](repeating: 0, count: 256)
    let n = proc_listchildpids(pid, &buf, Int32(buf.count * MemoryLayout<pid_t>.size))
    return n > 0 ? Array(buf.prefix(Int(n))) : []
}

// The process's argv as one string (KERN_PROCARGS2: argc, exec path, then the arguments).
func commandLine(_ pid: pid_t) -> String {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return "" }
    var buf = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return "" }
    return String(decoding: buf.prefix(size).map { $0 == 0 ? 32 : $0 }, as: UTF8.self)
}

// Background command shells of a Claude Code process. `pid` comes from the hook and may be the
// shell that ran the hook rather than Claude itself, so its parent is checked too.
func backgroundShells(_ pid: pid_t) -> [pid_t] {
    guard pid > 1 else { return [] }
    var owners = [pid]
    let pp = parentPid(pid)
    if pp > 1 { owners.append(pp) }
    return owners.flatMap(children).filter { commandLine($0).contains("/.claude/shell-snapshots/") }
}
