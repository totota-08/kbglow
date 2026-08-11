import Foundation
import MacKeyboardBacklight

let version = "0.4.1"

let usage = """
kbglow \(version) — your keyboard glows while your AI waits for approval

USAGE:
  kbglow set <0-100>          Set backlight brightness (percent)
  kbglow get                  Print current brightness (percent)
  kbglow on | off             Full brightness / off
  kbglow pulse [options]      Flash until stopped (for "agent waiting" alerts)
      --blink                   Hard 0/100 on-off blinking instead of breathing
      -t, --timeout <sec>       Stop automatically after N seconds (default: 600)
      --period <sec>            Cycle length in seconds (default: 1.6)
      --min <0-100>             Low point of the cycle (default: 0)
      --max <0-100>             High point of the cycle (default: 100)
  kbglow watch [options]      Blink when a GUI AI app (Claude Desktop, ChatGPT)
                              posts a notification; stop when you focus the app.
                              Needs Full Disk Access. Runs in the foreground.
      --app <bundle-id>         App to watch (repeatable; default: Claude
                                Desktop + ChatGPT)
      -t, --timeout <sec>       Max blink duration per notification (default: 120)
  kbglow stop                 Stop a running pulse session, restore state

Pulse restores the previous brightness and auto-brightness setting when it
exits. Only one session runs at a time (starting a new one replaces the old).
"""

func parsePercent(_ s: String) -> Double? {
    guard let v = Double(s.replacingOccurrences(of: "%", with: "")) else { return nil }
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
    guard let bl = KeyboardBacklight() else {
        FileHandle.standardError.write(Data("kbglow: no controllable keyboard backlight found\n".utf8))
        exit(1)
    }
    bl.brightness = value

case "get":
    guard let bl = KeyboardBacklight() else {
        FileHandle.standardError.write(Data("kbglow: no controllable keyboard backlight found\n".utf8))
        exit(1)
    }
    print(Int((bl.brightness * 100).rounded()))

case "on", "off":
    guard let bl = KeyboardBacklight() else {
        FileHandle.standardError.write(Data("kbglow: no controllable keyboard backlight found\n".utf8))
        exit(1)
    }
    bl.brightness = command == "on" ? 1 : 0

case "pulse":
    let timeout = optionValue(&args, ["-t", "--timeout"]).flatMap(Double.init) ?? 600
    let period = optionValue(&args, ["--period"]).flatMap(Double.init) ?? 1.6
    let minB = optionValue(&args, ["--min"]).flatMap(parsePercent) ?? 0
    let maxB = optionValue(&args, ["--max"]).flatMap(parsePercent) ?? 1
    let blink = args.contains("--blink")
    Pulse.run(timeout: timeout > 0 ? timeout : nil, period: max(0.2, period), minB: minB, maxB: maxB, blink: blink)

case "watch":
    var apps: [String] = []
    while let id = optionValue(&args, ["--app"]) { apps.append(id) }
    let timeout = optionValue(&args, ["-t", "--timeout"]).flatMap(Double.init) ?? 120
    for sig in [SIGINT, SIGTERM, SIGHUP] {
        signal(sig) { _ in gStop = 1 }
    }
    Watch.run(bundleIDs: apps, pulseTimeout: timeout)

case "stop":
    Session.stopAndRestore()

case "help", "-h", "--help":
    print(usage)

case "version", "-v", "--version":
    print(version)

default:
    FileHandle.standardError.write(Data("kbglow: unknown command '\(command)'\n\n".utf8))
    print(usage)
    exit(1)
}
