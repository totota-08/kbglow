import AppKit
import Foundation
import SQLite3

/// Watches the macOS Notification Center database for new notifications from
/// selected apps (Claude Desktop, ChatGPT, ...) and blinks the keyboard until
/// the user brings one of those apps to the front.
///
/// GUI agent apps have no hook system, but they do post a user notification
/// when they need approval or finish a task — so the delivered-notifications
/// database is the one generic signal available to a third-party tool.
/// Reading it requires Full Disk Access.
enum Watch {
    static let defaultBundleIDs = [
        "com.anthropic.claudefordesktop", // Claude Desktop
        "com.openai.codex",               // ChatGPT Desktop (unified app, 2026+)
        "com.openai.chat",                // ChatGPT Classic
    ]

    private static let dbPath = NSString(
        string: "~/Library/Group Containers/group.com.apple.usernoted/db2/db"
    ).expandingTildeInPath

    static func run(bundleIDs: [String], pulseTimeout: Double) {
        let ids = bundleIDs.isEmpty ? defaultBundleIDs : bundleIDs
        guard var lastSeen = waitForDatabase(ids) else { exit(0) }
        FileHandle.standardError.write(Data(
            "kbglow: watching notifications from \(ids.joined(separator: ", "))\n".utf8))

        // The notification DB lowercases bundle IDs; NSWorkspace reports the
        // app's true casing (e.g. com.apple.ScriptEditor2) — compare folded.
        let folded = Set(ids.map { $0.lowercased() })
        var blinking = false
        while gStop == 0 {
            // Pump the runloop (not just sleep) so NSWorkspace state stays fresh.
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
            guard let newest = maxRecordID(ids) else { continue }
            if newest > lastSeen {
                lastSeen = newest
                blinking = true
                runSelf(["pulse", "--blink", "--period", "2", "-t", String(pulseTimeout)])
            }
            if blinking, let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
               folded.contains(front.lowercased()) {
                blinking = false
                runSelf(["stop"])
            }
        }
        if blinking { runSelf(["stop"]) }
    }

    /// First successful read of the DB. Without Full Disk Access the open
    /// fails; explain once and keep retrying so a launchd-managed watcher
    /// starts working the moment the permission is granted.
    private static func waitForDatabase(_ ids: [String]) -> Int64? {
        var warned = false
        while gStop == 0 {
            if let newest = maxRecordID(ids) { return newest }
            if !warned {
                warned = true
                FileHandle.standardError.write(Data("""
                kbglow: cannot read the Notification Center database.
                kbglow: grant Full Disk Access to this binary (or your terminal) in
                kbglow: System Settings > Privacy & Security > Full Disk Access, then
                kbglow: kbglow will start watching automatically (retrying every 30s).\n
                """.utf8))
            }
            for _ in 0..<30 where gStop == 0 { usleep(1_000_000) }
        }
        return nil
    }

    /// Newest matching notification record. Opens a fresh read-only connection
    /// every time: a long-lived read-only connection keeps serving a stale WAL
    /// snapshot (it cannot refresh the shared-memory index), so rows written
    /// by usernoted after we connect would never become visible.
    private static func maxRecordID(_ ids: [String]) -> Int64? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if ProcessInfo.processInfo.environment["KBGLOW_DEBUG"] != nil {
                let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "nil handle"
                FileHandle.standardError.write(Data(
                    "kbglow: sqlite open failed: \(msg) (errno=\(errno))\n".utf8))
            }
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }

        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let sql = """
            SELECT COALESCE(MAX(r.rec_id), 0) FROM record r
            JOIN app a ON a.app_id = r.app_id
            WHERE a.identifier IN (\(placeholders))
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            if ProcessInfo.processInfo.environment["KBGLOW_DEBUG"] != nil {
                FileHandle.standardError.write(Data(
                    "kbglow: sqlite prepare failed: \(String(cString: sqlite3_errmsg(db)))\n".utf8))
            }
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        for (i, id) in ids.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(stmt, 0)
    }

    /// Run this same kbglow binary with the given arguments (pulse manages its
    /// own single-session lifecycle, so the watcher just shells out to it).
    private static func runSelf(_ args: [String]) {
        guard let exe = Bundle.main.executablePath else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        // pulse daemonizes by design (it keeps running until stopped); don't wait.
        if args.first == "stop" { p.waitUntilExit() }
    }
}
