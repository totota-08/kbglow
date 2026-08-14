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

// Per-uid so two users on one Mac never fight over each other's files.
private let pidPath = "/tmp/kbglow.\(getuid()).pid"
private let statePath = "/tmp/kbglow.\(getuid()).state"

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
        let bl = discoverOrExit()
        backlight = bl

        Session.killExisting()
        try? String(ProcessInfo.processInfo.processIdentifier).write(
            toFile: pidPath, atomically: true, encoding: .utf8)

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

        installStopHandlers()
    }

    func finish() {
        guard !finished else { return }
        finished = true
        Session.restore(backlight, brightness: savedBrightness, auto: savedAuto)
        try? FileManager.default.removeItem(atPath: statePath)
        if let pid = Session.readPid(), pid == ProcessInfo.processInfo.processIdentifier {
            try? FileManager.default.removeItem(atPath: pidPath)
        }
    }

    /// End-of-session restore, honoring the configured `RestoreMode`.
    /// In `auto` mode the saved brightness is deliberately not written back:
    /// auto-brightness is re-enabled and the ambient sensor picks the level.
    /// Keyboards without the ambient feature fall back to the fixed restore
    /// (enabling auto there would be a no-op and leave the blink's last frame).
    static func restore(_ bl: KeyboardBacklight, brightness: Double, auto: Bool) {
        if RestoreMode.load() == .auto, bl.supportsAutoBrightness {
            bl.autoBrightness = true
        } else {
            bl.brightness = brightness
            bl.autoBrightness = auto
        }
    }

    static func readPid() -> Int32? {
        guard let s = try? String(contentsOfFile: pidPath, encoding: .utf8) else { return nil }
        return Int32(s.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func readState() -> (brightness: Double, auto: Bool)? {
        guard let s = try? String(contentsOfFile: statePath, encoding: .utf8) else { return nil }
        let parts = s.split(separator: " ")
        guard parts.count == 2, let b = Double(parts[0]) else { return nil }
        return (max(0, min(1, b)), parts[1] == "1")
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
        guard let pid = readPid(), pid != ProcessInfo.processInfo.processIdentifier else { return }
        if isKbglowProcess(pid), kill(pid, SIGTERM) == 0 {
            // Give it a moment to restore state and remove the pid file.
            for _ in 0..<20 where kill(pid, 0) == 0 { usleep(25_000) }
        }
        // Compare-and-delete: a session that started while we were waiting
        // owns the pid file now — deleting it would orphan that session.
        if readPid() == pid {
            try? FileManager.default.removeItem(atPath: pidPath)
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
            restore(bl, brightness: b, auto: auto)
        }
        try? FileManager.default.removeItem(atPath: statePath)
    }
}
