import Foundation

enum Pulse {
    /// Hard-blink the backlight (full on/off square wave) until stopped or
    /// `timeout` elapses.
    static func run(timeout: Double?, period: Double) {
        let session = Session()
        let start = Date()
        let fps = 30.0
        var t = 0.0
        var last = -1.0
        while gStop == 0 {
            if let limit = timeout, Date().timeIntervalSince(start) >= limit { break }
            let value: Double = t.truncatingRemainder(dividingBy: period) < period / 2 ? 1 : 0
            if value != last {
                session.backlight.brightness = value
                last = value
            }
            usleep(useconds_t(1_000_000 / fps))
            t += 1 / fps
        }
        session.finish()
    }
}
