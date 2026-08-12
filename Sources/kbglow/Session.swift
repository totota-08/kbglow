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

private let pidPath = "/tmp/kbglow.pid"
private let statePath = "/tmp/kbglow.state"

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
        backlight.brightness = savedBrightness
        backlight.autoBrightness = savedAuto
        try? FileManager.default.removeItem(atPath: statePath)
        if let pid = Session.readPid(), pid == ProcessInfo.processInfo.processIdentifier {
            try? FileManager.default.removeItem(atPath: pidPath)
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

    /// Ask any running kbglow session to stop (it restores brightness itself).
    static func killExisting() {
        guard let pid = readPid(), pid != ProcessInfo.processInfo.processIdentifier else { return }
        if kill(pid, SIGTERM) == 0 {
            // Give it a moment to restore state and remove the pid file.
            for _ in 0..<20 where kill(pid, 0) == 0 { usleep(25_000) }
        }
        try? FileManager.default.removeItem(atPath: pidPath)
    }

    /// `kbglow stop`: stop a running session, and if a state file is still
    /// around afterwards (the session crashed or was SIGKILLed before it
    /// could restore), restore the original state from the file.
    static func stopAndRestore() {
        killExisting()
        guard let (b, auto) = readState() else { return }
        if let bl = try? KeyboardBacklight.discover() {
            bl.brightness = b
            bl.autoBrightness = auto
        }
        try? FileManager.default.removeItem(atPath: statePath)
    }
}
