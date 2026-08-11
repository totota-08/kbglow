import Foundation

enum Pulse {
    /// Flash the backlight between `minB` and `maxB` until stopped or `timeout`
    /// elapses. `blink` toggles hard on/off (square wave); otherwise breathe
    /// smoothly (sine).
    static func run(timeout: Double?, period: Double, minB: Double, maxB: Double, blink: Bool) {
        guard let session = Session() else { exit(1) }
        let start = Date()
        let fps = 30.0
        var t = 0.0
        var last = -1.0
        while gStop == 0 {
            if let limit = timeout, Date().timeIntervalSince(start) >= limit { break }
            let value: Double
            if blink {
                value = t.truncatingRemainder(dividingBy: period) < period / 2 ? maxB : minB
            } else {
                let phase = (1 - cos(2 * .pi * t / period)) / 2
                value = minB + (maxB - minB) * phase
            }
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
