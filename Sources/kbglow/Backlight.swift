import Foundation

/// Controls the built-in keyboard backlight via the private CoreBrightness framework.
final class Backlight {
    private let client: NSObject
    private let keyboardID: UInt64

    init?() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil,
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else {
            return nil
        }
        client = cls.init()

        let sel = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard client.responds(to: sel),
              let ids = client.perform(sel)?.takeRetainedValue() as? [NSNumber],
              let first = ids.first else {
            return nil
        }
        keyboardID = first.uint64Value
    }

    var brightness: Float {
        get {
            let sel = NSSelectorFromString("brightnessForKeyboard:")
            guard client.responds(to: sel) else { return 0 }
            typealias Fn = @convention(c) (NSObject, Selector, UInt64) -> Float
            let fn = unsafeBitCast(client.method(for: sel), to: Fn.self)
            return fn(client, sel, keyboardID)
        }
        set {
            let sel = NSSelectorFromString("setBrightness:forKeyboard:")
            guard client.responds(to: sel) else { return }
            typealias Fn = @convention(c) (NSObject, Selector, Float, UInt64) -> Bool
            let fn = unsafeBitCast(client.method(for: sel), to: Fn.self)
            _ = fn(client, sel, max(0, min(1, newValue)), keyboardID)
        }
    }

    var autoBrightnessEnabled: Bool {
        let sel = NSSelectorFromString("isAutoBrightnessEnabledForKeyboard:")
        guard client.responds(to: sel) else { return false }
        typealias Fn = @convention(c) (NSObject, Selector, UInt64) -> Bool
        let fn = unsafeBitCast(client.method(for: sel), to: Fn.self)
        return fn(client, sel, keyboardID)
    }

    func setAutoBrightness(_ enabled: Bool) {
        let sel = NSSelectorFromString("enableAutoBrightness:forKeyboard:")
        guard client.responds(to: sel) else { return }
        typealias Fn = @convention(c) (NSObject, Selector, Bool, UInt64) -> Bool
        let fn = unsafeBitCast(client.method(for: sel), to: Fn.self)
        _ = fn(client, sel, enabled, keyboardID)
    }
}
