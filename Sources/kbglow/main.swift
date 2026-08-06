import Foundation

let version = "0.1.0"

let usage = """
kbglow \(version) — Mac keyboard backlight, but fun

USAGE:
  kbglow set <0-100>          Set backlight brightness (percent)
  kbglow get                  Print current brightness (percent)
  kbglow on | off             Full brightness / off
  kbglow pulse [options]      Breathe until stopped (for "agent waiting" alerts)
      -t, --timeout <sec>       Stop automatically after N seconds (default: 600)
      --period <sec>            Breath cycle length (default: 1.6)
      --min <0-100>             Low point of the breath (default: 0)
      --max <0-100>             High point of the breath (default: 100)
  kbglow audio [options]      Visualizer: flash with whatever the Mac is playing
      --gain <n>                Sensitivity multiplier (default: 6)
      --base <0-100>            Brightness floor when silent (default: 0)
      --smooth                  Gentle level-following instead of beat strobing
      --demo [sec]              Preview with a synthetic beat (no audio permission
                                needed; default 10 seconds)
  kbglow stop                 Stop a running pulse/audio session, restore state

Pulse and audio restore the previous brightness and auto-brightness setting
when they exit. Only one session runs at a time (starting a new one replaces
the old).
"""

func parsePercent(_ s: String) -> Float? {
    guard let v = Float(s.replacingOccurrences(of: "%", with: "")) else { return nil }
    return max(0, min(100, v)) / 100
}

func optionValue(_ args: inout [String], _ names: [String]) -> String? {
    for name in names {
        if let i = args.firstIndex(of: name), i + 1 < args.count {
            let v = args[i + 1]
            args.removeSubrange(i...(i + 1))
            return v
        }
    }
    return nil
}

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print(usage)
    exit(0)
}
args.removeFirst()

switch command {
case "set":
    guard let value = args.first.flatMap(parsePercent) else {
        FileHandle.standardError.write(Data("kbglow: set needs a value between 0 and 100\n".utf8))
        exit(1)
    }
    guard let bl = Backlight() else {
        FileHandle.standardError.write(Data("kbglow: no controllable keyboard backlight found\n".utf8))
        exit(1)
    }
    bl.brightness = value

case "get":
    guard let bl = Backlight() else {
        FileHandle.standardError.write(Data("kbglow: no controllable keyboard backlight found\n".utf8))
        exit(1)
    }
    print(Int((bl.brightness * 100).rounded()))

case "on", "off":
    guard let bl = Backlight() else {
        FileHandle.standardError.write(Data("kbglow: no controllable keyboard backlight found\n".utf8))
        exit(1)
    }
    bl.brightness = command == "on" ? 1 : 0

case "pulse":
    let timeout = optionValue(&args, ["-t", "--timeout"]).flatMap(Double.init) ?? 600
    let period = optionValue(&args, ["--period"]).flatMap(Double.init) ?? 1.6
    let minB = optionValue(&args, ["--min"]).flatMap(parsePercent) ?? 0
    let maxB = optionValue(&args, ["--max"]).flatMap(parsePercent) ?? 1
    Pulse.run(timeout: timeout > 0 ? timeout : nil, period: max(0.2, period), minB: minB, maxB: maxB)

case "audio":
    let gain = optionValue(&args, ["--gain"]).flatMap(Float.init) ?? 6
    let base = optionValue(&args, ["--base"]).flatMap(parsePercent) ?? 0
    let smooth = args.contains("--smooth")
    if #available(macOS 14.2, *) {
        if let demoIndex = args.firstIndex(of: "--demo") {
            let duration = demoIndex + 1 < args.count ? Double(args[demoIndex + 1]) ?? 10 : 10
            AudioReactive.runDemo(gain: gain, base: base, smooth: smooth, duration: duration)
        } else {
            AudioReactive.run(gain: gain, base: base, smooth: smooth)
        }
    } else {
        FileHandle.standardError.write(Data("kbglow: audio mode requires macOS 14.2 or later\n".utf8))
        exit(1)
    }

case "stop":
    Session.killExisting()

case "help", "-h", "--help":
    print(usage)

case "version", "-v", "--version":
    print(version)

default:
    FileHandle.standardError.write(Data("kbglow: unknown command '\(command)'\n\n".utf8))
    print(usage)
    exit(1)
}
