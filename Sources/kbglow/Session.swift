import Foundation

/// Set to 1 by signal handlers; long-running loops poll this and exit cleanly.
nonisolated(unsafe) var gStop: sig_atomic_t = 0

private let pidPath = "/tmp/kbglow.pid"

/// A long-running lighting session (pulse). Ensures only one instance
/// runs at a time, and restores the original backlight state on exit.
final class Session {
    let backlight: Backlight
    private let savedBrightness: Float
    private let savedAuto: Bool
    private var finished = false

    init?() {
        guard let bl = Backlight() else {
            FileHandle.standardError.write(Data("kbglow: no controllable keyboard backlight found\n".utf8))
            return nil
        }
        backlight = bl

        Session.killExisting()
        try? String(ProcessInfo.processInfo.processIdentifier).write(
            toFile: pidPath, atomically: true, encoding: .utf8)

        savedBrightness = bl.brightness
        savedAuto = bl.autoBrightnessEnabled
        bl.setAutoBrightness(false)

        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig) { _ in gStop = 1 }
        }
    }

    func finish() {
        guard !finished else { return }
        finished = true
        backlight.brightness = savedBrightness
        backlight.setAutoBrightness(savedAuto)
        if let pid = Session.readPid(), pid == ProcessInfo.processInfo.processIdentifier {
            try? FileManager.default.removeItem(atPath: pidPath)
        }
    }

    static func readPid() -> Int32? {
        guard let s = try? String(contentsOfFile: pidPath, encoding: .utf8) else { return nil }
        return Int32(s.trimmingCharacters(in: .whitespacesAndNewlines))
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
}
