import BacklightKit
import Foundation

/// Set to 1 by signal handlers; long-running loops poll this and exit cleanly.
nonisolated(unsafe) var gStop: sig_atomic_t = 0

func installStopHandlers() {
    for sig in [SIGINT, SIGTERM, SIGHUP] {
        signal(sig) { _ in gStop = 1 }
    }
}

/// The keyboard backlight, or a clean exit naming the actual cause.
func discoverOrExit() -> KeyboardBacklight {
    do {
        return try KeyboardBacklight.discover()
    } catch {
        FileHandle.standardError.write(Data("kbglow: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

// Per-uid so two users on one Mac never fight over each other's files, and in
// the per-user temp dir rather than world-writable /tmp, where another local
// user could pre-create the paths (the sticky bit then makes our writes fail).
private let runDir: String = {
    var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
    let n = confstr(_CS_DARWIN_USER_TEMP_DIR, &buf, buf.count)
    guard n > 0, n <= buf.count else { return "/tmp" }
    let dir = String(cString: buf)
    return dir.hasSuffix("/") ? String(dir.dropLast()) : dir
}()
private let pidPath = "\(runDir)/kbglow.\(getuid()).pid"
private let statePath = "\(runDir)/kbglow.\(getuid()).state"
// Pre-0.8 versions kept these in /tmp — still checked (and cleaned up) so an
// upgrade can stop and restore a session started by the old binary.
private let legacyPidPath = "/tmp/kbglow.\(getuid()).pid"
private let legacyStatePath = "/tmp/kbglow.\(getuid()).state"

/// A long-running lighting session (pulse). Ensures only one instance
/// runs at a time, and restores the original backlight state on exit.
///
/// The pre-session state (brightness + auto-brightness) lives in a file, not
/// just in memory: when a new pulse replaces a running one, the current
/// reading is mid-blink with auto-brightness already disabled, so sampling it
/// would "save" a broken state and restoring would wreck the user's settings.
/// The file always holds the state from before the *first* session, survives
/// takeovers and crashes, and is removed once it has been restored.
/// (BacklightKit's `withManualControl` restores in-process; the file covers the
/// cross-process handoffs it cannot see.)
final class Session {
    let backlight: KeyboardBacklight
    private let savedBrightness: Double
    private let savedAuto: Bool
    private var finished = false

    init() {
        // Handlers first: a SIGTERM arriving after the pid file is written
        // but before the handler is installed would kill the process without
        // restoring anything (gStop is already polled by the run loops).
        installStopHandlers()

        let bl = discoverOrExit()
        backlight = bl

        Session.claimPidFile()

        if let (b, auto) = Session.readState() {
            // A previous session left its original state behind (it was
            // replaced mid-handoff or crashed) — that is the true original.
            savedBrightness = b
            savedAuto = auto
        } else {
            savedBrightness = bl.brightness
            savedAuto = bl.autoBrightness
            Session.writeState(brightness: savedBrightness, auto: savedAuto)
        }
        bl.autoBrightness = false
    }

    func finish() {
        guard !finished else { return }
        finished = true
        backlight.brightness = savedBrightness
        backlight.autoBrightness = savedAuto
        Session.removeStateFiles()
        if let pid = Session.readPid(), pid == ProcessInfo.processInfo.processIdentifier {
            try? FileManager.default.removeItem(atPath: pidPath)
        }
    }

    /// Write our pid file, exclusively. Two sessions starting at the same
    /// instant can both pass killExisting() before either has written the
    /// file — read-then-write would leave the loser blinking unsupervised.
    /// O_CREAT|O_EXCL makes exactly one win; the loser kills the winner on
    /// its next lap (a new session replaces the old, as documented).
    private static func claimPidFile() {
        for _ in 0..<40 {
            killExisting()
            let fd = open(pidPath, O_WRONLY | O_CREAT | O_EXCL, 0o644)
            if fd >= 0 {
                let pid = "\(ProcessInfo.processInfo.processIdentifier)"
                _ = pid.withCString { write(fd, $0, strlen($0)) }
                close(fd)
                return
            }
            usleep(25_000)
        }
        FileHandle.standardError.write(Data(
            "kbglow: could not claim \(pidPath) — another session keeps starting\n".utf8))
        exit(1)
    }

    static func readPid() -> Int32? { readPid(at: pidPath) }

    private static func readPid(at path: String) -> Int32? {
        guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return Int32(s.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func readState() -> (brightness: Double, auto: Bool)? {
        if let state = readState(at: statePath) { return state }
        guard legacyStatePath != statePath else { return nil }
        return readState(at: legacyStatePath)
    }

    private static func readState(at path: String) -> (brightness: Double, auto: Bool)? {
        guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let parts = s.split(separator: " ")
        guard parts.count == 2, let b = Double(parts[0]) else { return nil }
        return (max(0, min(1, b)), parts[1] == "1")
    }

    private static func removeStateFiles() {
        try? FileManager.default.removeItem(atPath: statePath)
        if legacyStatePath != statePath {
            try? FileManager.default.removeItem(atPath: legacyStatePath)
        }
    }

    static func writeState(brightness: Double, auto: Bool) {
        try? "\(brightness) \(auto ? 1 : 0)".write(
            toFile: statePath, atomically: true, encoding: .utf8)
    }

    /// True when `pid` is a live process actually running a kbglow binary.
    /// A stale pid file can point at a recycled pid belonging to some
    /// innocent app — never signal without this check.
    static func isKbglowProcess(_ pid: Int32) -> Bool {
        guard kill(pid, 0) == 0 else { return false }
        var buf = [CChar](repeating: 0, count: 4 * 1024)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return false }
        return String(cString: buf).contains("kbglow")
    }

    /// Ask any running kbglow session to stop (it restores brightness itself).
    static func killExisting() {
        killExisting(at: pidPath)
        if legacyPidPath != pidPath { killExisting(at: legacyPidPath) }
    }

    private static func killExisting(at path: String) {
        guard let pid = readPid(at: path),
              pid != ProcessInfo.processInfo.processIdentifier else { return }
        if isKbglowProcess(pid), kill(pid, SIGTERM) == 0 {
            // Give it a moment to restore state and remove the pid file.
            for _ in 0..<20 where kill(pid, 0) == 0 { usleep(25_000) }
        }
        // Compare-and-delete: a session that started while we were waiting
        // owns the pid file now — deleting it would orphan that session.
        if readPid(at: path) == pid {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    /// `kbglow stop`: stop a running session, and if a state file is still
    /// around afterwards (the session crashed or was SIGKILLed before it
    /// could restore), restore the original state from the file.
    static func stopAndRestore() {
        // A session starting concurrently can replace the one we just killed;
        // keep going until none is left (bounded — this converges immediately
        // outside pathological loops).
        for _ in 0..<3 {
            killExisting()
            guard let pid = readPid(), isKbglowProcess(pid) else { break }
        }
        if let pid = readPid(), isKbglowProcess(pid) { return } // it will restore itself
        guard let (b, auto) = readState() else { return }
        if let bl = try? KeyboardBacklight.discover() {
            bl.brightness = b
            bl.autoBrightness = auto
        }
        removeStateFiles()
    }
}
