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
        func watchedAppIsFrontmost() -> Bool {
            guard let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
                return false
            }
            return folded.contains(front.lowercased())
        }

        // The pulse we spawned, while it may still be blinking. Checked
        // against the live process and its -t timeout: once the pulse exited
        // or timed out on its own, a later focus/dismiss must not call
        // stopAndRestore() and kill an unrelated session (e.g. a CLI
        // approval blink started by a hook).
        var blinkProc: Process?
        var blinkStart = Date.distantPast
        func blinking() -> Bool {
            guard let p = blinkProc else { return false }
            if !p.isRunning
                || (pulseTimeout > 0 && Date().timeIntervalSince(blinkStart) >= pulseTimeout) {
                blinkProc = nil
                return false
            }
            return true
        }
        func stopBlink() {
            blinkProc = nil
            Session.stopAndRestore()
        }
        while gStop == 0 {
            // Pump the runloop (not just sleep) so NSWorkspace state stays fresh.
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
            // Known hole: SQLite assigns new rows max(rowid)+1, so after the
            // newest watched record is dismissed the next notification can
            // REUSE its rec_id. If both happen within one poll interval the
            // numbers are identical and no rec_id-based scheme (MAX or
            // tracking the full id set) can tell the difference — that
            // notification is missed. Accepted: the window is ~1s and the
            // next notification re-arms the watcher.
            guard let newest = maxRecordID(ids) else { continue }
            if newest < lastSeen {
                // The newest watched notification was dismissed (or the DB was
                // rebuilt and rowids restarted lower). Re-baseline, and treat a
                // dismissal as acknowledged — keeping the blink going after the
                // user explicitly cleared the notification just annoys them.
                lastSeen = newest
                if blinking() { stopBlink() }
            }
            if newest > lastSeen {
                lastSeen = newest
                // A notification from the app the user is already looking at
                // needs no blink (and the stop below would race the spawn).
                if !watchedAppIsFrontmost() {
                    blinkStart = Date()
                    blinkProc = runSelf(["pulse", "--period", "2", "-t", String(pulseTimeout)])
                    // The stop paths below signal the pulse via its pid file;
                    // if the user focuses the app (or dismisses) before the
                    // newborn pulse has written it, the stop would miss the
                    // session and it would blink on to its timeout.
                    if let proc = blinkProc {
                        for _ in 0..<40 {
                            if Session.readPid() == proc.processIdentifier { break }
                            usleep(25_000)
                        }
                    }
                }
            }
            if blinking(), watchedAppIsFrontmost() { stopBlink() }
        }
        if blinking() { Session.stopAndRestore() }
    }

    /// First successful read of the DB. Without Full Disk Access the open
    /// fails; explain once and keep retrying so a launchd-managed watcher
    /// starts working the moment the permission is granted.
    private static func waitForDatabase(_ ids: [String]) -> Int64? {
        var warned = false
        var failures = 0
        while gStop == 0 {
            if let newest = maxRecordID(ids) { return newest }
            // A transient SQLITE_BUSY is not a missing permission — retry a
            // few times quickly before lecturing about Full Disk Access.
            failures += 1
            if failures < 3 {
                usleep(1_000_000)
                continue
            }
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
        sqlite3_busy_timeout(db, 250)

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
            // The DB stores bundle IDs lowercased; fold ours to match (--app
            // values may carry the app's true mixed casing).
            sqlite3_bind_text(stmt, Int32(i + 1), id.lowercased(), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(stmt, 0)
    }

    /// Spawn this same kbglow binary as a detached pulse session (pulse is a
    /// long-lived process with its own pid-file lifecycle; stop is called
    /// in-process via Session.stopAndRestore). Returns the child so the
    /// caller can track whether that specific pulse is still alive.
    private static func runSelf(_ args: [String]) -> Process? {
        guard let exe = Bundle.main.executablePath else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        return p
    }
}
