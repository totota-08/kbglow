import Foundation

enum Pulse {
    /// Breathe the backlight between `minB` and `maxB` until stopped or `timeout` elapses.
    static func run(timeout: Double?, period: Double, minB: Float, maxB: Float) {
        guard let session = Session() else { exit(1) }
        let start = Date()
        let fps = 30.0
        var t = 0.0
        while gStop == 0 {
            if let limit = timeout, Date().timeIntervalSince(start) >= limit { break }
            let phase = (1 - cos(2 * .pi * t / period)) / 2
            session.backlight.brightness = minB + (maxB - minB) * Float(phase)
            usleep(useconds_t(1_000_000 / fps))
            t += 1 / fps
        }
        session.finish()
    }
}
