import Foundation

/// What a session does with the backlight when it ends (`kbglow restore-mode`).
///
/// Persisted as a single word in ~/.config/kbglow/restore-mode — unlike the
/// /tmp session files this is a lasting preference, and a plain file means
/// every kbglow process (a pulse, `kbglow stop`, a watch-spawned pulse) reads
/// the same answer without threading a flag through every hook command.
enum RestoreMode: String {
    /// Put back the exact pre-session state (brightness + auto-brightness
    /// setting). The default — kbglow's historical behavior.
    case fixed
    /// Re-enable ambient auto-brightness and let macOS pick the level from
    /// the light sensor; the pre-session brightness is not written back.
    case auto

    static let path = NSString(string: "~/.config/kbglow/restore-mode").expandingTildeInPath

    static func load() -> RestoreMode {
        guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { return .fixed }
        return RestoreMode(rawValue: s.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .fixed
    }

    func save() throws {
        try FileManager.default.createDirectory(
            atPath: (RestoreMode.path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        try rawValue.write(toFile: RestoreMode.path, atomically: true, encoding: .utf8)
    }
}
