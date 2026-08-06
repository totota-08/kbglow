import Foundation
import CoreAudio
import AudioToolbox

/// Lights the keyboard in sync with whatever is playing on the Mac, using a
/// Core Audio process tap (macOS 14.2+) on all system audio output.
@available(macOS 14.2, *)
enum AudioReactive {
    static func run(gain: Float, base: Float, attack: Float, release: Float) {
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
        var level: Float = 0
        var lastSet: Float = -1
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
            let target = min(1, base + rms * gain)
            level += (target - level) * (target > level ? attack : release)
            let quantized = (level * 100).rounded() / 100
            if quantized != lastSet {
                lastSet = quantized
                session.backlight.brightness = quantized
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
