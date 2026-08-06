import Foundation
import CoreAudio
import AudioToolbox

/// Maps an incoming loudness signal to flashy, visualizer-style brightness:
/// auto-gain against the recent peak, gamma curve for punch, instant attack
/// with VU-meter falloff, and a strobe burst on detected onsets (beats).
struct VisualizerEnvelope {
    enum Mode {
        case beat    // VU-style envelope with strobe bursts on onsets (default)
        case smooth  // gentle level following
        case strobe  // dark, with a hard full-on flash on each detected hit
    }

    let base: Float
    let gain: Float
    let mode: Mode

    private var avg: Float = 0.001    // slow-moving average, for onset detection
    private var peak: Float = 0.02    // decaying peak, for auto-gain
    private var level: Float = 0
    private var strobe = 0
    private var burst = 0
    private var tick = 0
    private var lastOut: Float = -1

    init(base: Float, gain: Float, mode: Mode) {
        self.base = base
        self.gain = gain
        self.mode = mode
    }

    /// Feed one loudness sample (~90 Hz). Returns a brightness to apply, or
    /// nil when the value hasn't changed enough to be worth an XPC call.
    mutating func process(_ rms: Float) -> Float? {
        var out: Float
        switch mode {
        case .smooth:
            let target = min(1, base + rms * gain)
            level += (target - level) * (target > level ? 0.6 : 0.08)
            out = level
        case .strobe:
            avg += (rms - avg) * 0.02
            // While the signal sits above the running average — a hit, or a
            // whole loud passage — hammer the backlight with a ~24 Hz hard
            // flicker; go dark the moment the energy drops. The music's own
            // dynamics shape the strobing.
            let threshold = 1 + 3 / max(gain, 1)   // gain 6 -> 1.5x; higher gain = more sensitive
            if rms > avg * threshold && rms > 0.015 {
                burst = max(burst, 8)              // ~80 ms of flicker, retriggered while loud
            }
            if burst > 0 {
                burst -= 1
                tick += 1
                out = (tick / 2) % 2 == 0 ? 1 : 0  // 2 frames per state ≈ 24 Hz strobe
            } else {
                tick = 0
                out = base
            }
        case .beat:
            avg += (rms - avg) * 0.02
            peak = max(rms, peak * 0.9985)
            var v = min(1, (rms / max(peak, 0.02)) * (gain / 6))
            v = powf(v, 1.6)
            if v >= level {
                level = v                         // instant attack
            } else {
                level = max(v, level * 0.80)      // fast VU-style falloff
            }
            if strobe == 0 && rms > avg * 2.5 && rms > 0.03 {
                strobe = 10                       // ~110 ms strobe burst per beat
            }
            out = base + (1 - base) * level
            if strobe > 0 {
                out = (strobe / 3) % 2 == 0 ? 1 : 0
                strobe -= 1
            }
        }
        let quantized = (out * 50).rounded() / 50
        guard quantized != lastOut else { return nil }
        lastOut = quantized
        return quantized
    }
}

/// Lights the keyboard in sync with whatever is playing on the Mac, using a
/// Core Audio process tap (macOS 14.2+) on all system audio output.
@available(macOS 14.2, *)
enum AudioReactive {
    /// Preview the visualizer with a synthetic 130 BPM beat — no audio
    /// permission needed. Handy for tuning and for showing off.
    static func runDemo(gain: Float, base: Float, mode: VisualizerEnvelope.Mode, duration: Double) {
        guard let session = Session() else { exit(1) }
        var env = VisualizerEnvelope(base: base, gain: gain, mode: mode)
        let dt = 1.0 / 90.0
        let beatPeriod = 60.0 / 130.0
        var t = 0.0
        while gStop == 0, t < duration {
            let sinceKick = t.truncatingRemainder(dividingBy: beatPeriod)
            let sinceHat = (t + beatPeriod / 2).truncatingRemainder(dividingBy: beatPeriod / 2)
            let kick = 0.30 * Float(exp(-sinceKick * 9))
            let hat = 0.06 * Float(exp(-sinceHat * 18))
            let rms = kick + hat + Float.random(in: 0...0.005)
            if let b = env.process(rms) { session.backlight.brightness = b }
            usleep(useconds_t(dt * 1_000_000))
            t += dt
        }
        session.finish()
    }

    static func run(gain: Float, base: Float, mode: VisualizerEnvelope.Mode) {
        guard ensureAudioCapturePermission() else {
            fail("System Audio Recording permission was not granted. Enable it in " +
                 "System Settings > Privacy & Security > Screen & System Audio Recording " +
                 "(System Audio Recording Only), then run `kbglow audio` again.")
        }
        guard let session = Session() else { exit(1) }

        // Tap every process's audio output (stereo mixdown).
        let tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDesc.name = "kbglow tap"
        tapDesc.isPrivate = true
        tapDesc.muteBehavior = .unmuted
        var tapID = AudioObjectID(kAudioObjectUnknown)
        var err = AudioHardwareCreateProcessTap(tapDesc, &tapID)
        guard err == noErr else {
            session.finish()
            fail("could not create system audio tap (OSStatus \(err)). " +
                 "Grant System Audio Recording permission to your terminal in " +
                 "System Settings > Privacy & Security > Screen & System Audio Recording.")
        }

        // Wrap the tap in a private aggregate device we can run an IO proc on.
        // The default output device is included as a sub-device so the
        // aggregate has a clock source; without one the IO proc never fires.
        guard let outputUID = defaultOutputDeviceUID() else {
            AudioHardwareDestroyProcessTap(tapID)
            session.finish()
            fail("could not find the default audio output device")
        }
        let desc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "kbglow",
            kAudioAggregateDeviceUIDKey: "kbglow-\(ProcessInfo.processInfo.processIdentifier)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapDesc.uuid.uuidString,
                 kAudioSubTapDriftCompensationKey: true]
            ]
        ]
        var aggID = AudioObjectID(kAudioObjectUnknown)
        err = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &aggID)
        guard err == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            session.finish()
            fail("could not create aggregate device (OSStatus \(err))")
        }

        let debug = ProcessInfo.processInfo.environment["KBGLOW_DEBUG"] != nil
        var callbackCount = 0
        var env = VisualizerEnvelope(base: base, gain: gain, mode: mode)
        var ioProcID: AudioDeviceIOProcID?
        let queue = DispatchQueue(label: "kbglow.audio")
        err = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggID, queue) { _, inInputData, _, _, _ in
            let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            var sum: Float = 0
            var count = 0
            for buf in abl {
                guard let data = buf.mData else { continue }
                let n = Int(buf.mDataByteSize) / MemoryLayout<Float32>.size
                let samples = data.bindMemory(to: Float32.self, capacity: n)
                for i in 0..<n { sum += samples[i] * samples[i] }
                count += n
            }
            guard count > 0 else { return }
            let rms = sqrtf(sum / Float(count))
            if debug {
                callbackCount += 1
                if callbackCount % 20 == 1 {
                    FileHandle.standardError.write(Data("cb #\(callbackCount) buffers=\(abl.count) samples=\(count) rms=\(rms)\n".utf8))
                }
            }
            if let b = env.process(rms) {
                if debug && b == 1 {
                    FileHandle.standardError.write(Data("FLASH rms=\(rms)\n".utf8))
                }
                session.backlight.brightness = b
            }
        }
        guard err == noErr, ioProcID != nil else {
            AudioHardwareDestroyAggregateDevice(aggID)
            AudioHardwareDestroyProcessTap(tapID)
            session.finish()
            fail("could not create IO proc (OSStatus \(err))")
        }

        err = AudioDeviceStart(aggID, ioProcID)
        guard err == noErr else {
            AudioDeviceDestroyIOProcID(aggID, ioProcID!)
            AudioHardwareDestroyAggregateDevice(aggID)
            AudioHardwareDestroyProcessTap(tapID)
            session.finish()
            fail("could not start audio device (OSStatus \(err))")
        }

        while gStop == 0 { usleep(100_000) }

        AudioDeviceStop(aggID, ioProcID)
        AudioDeviceDestroyIOProcID(aggID, ioProcID!)
        AudioHardwareDestroyAggregateDevice(aggID)
        AudioHardwareDestroyProcessTap(tapID)
        session.finish()
    }

    /// System audio taps deliver silence until the user grants the
    /// "System Audio Recording" TCC permission. There is no public request API
    /// for CLI tools, so ask via the private TCC framework (same approach as
    /// AudioCap and friends).
    private static func ensureAudioCapturePermission() -> Bool {
        guard let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_NOW) else {
            return true // can't check; try the tap anyway
        }
        let service = "kTCCServiceAudioCapture" as CFString

        if let sym = dlsym(tcc, "TCCAccessPreflight") {
            typealias PreflightFn = @convention(c) (CFString, CFDictionary?) -> Int32
            let preflight = unsafeBitCast(sym, to: PreflightFn.self)
            switch preflight(service, nil) {
            case 0: return true // granted
            case 1: break       // not determined yet -> request below
            default: break      // denied -> request anyway; TCC just returns false
            }
        }

        guard let sym = dlsym(tcc, "TCCAccessRequest") else { return true }
        typealias RequestFn = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void
        let request = unsafeBitCast(sym, to: RequestFn.self)
        FileHandle.standardError.write(Data("kbglow: requesting System Audio Recording permission…\n".utf8))
        let sem = DispatchSemaphore(value: 0)
        var granted = false
        request(service, nil) { ok in
            granted = ok
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 120)
        return granted
    }

    private static func defaultOutputDeviceUID() -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &addr, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown else { return nil }

        addr.mSelector = kAudioDevicePropertyDeviceUID
        var uid: CFString = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &uid) == noErr else {
            return nil
        }
        return uid as String
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("kbglow: \(message)\n".utf8))
        exit(1)
    }
}
