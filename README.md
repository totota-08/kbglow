# kbglow ⌨️✨

**Your keyboard glows while your AI waits for approval.**

[日本語版 README はこちら](README.ja.md)

When an agent like Claude Code stops and asks for permission, your Mac's keyboard backlight starts blinking — so you notice from the corner of your eye, even with notification sounds off or another window in front. Answer it (or focus the app) and the light goes back to normal.

Zero dependencies, single Swift binary, macOS only.

## Install

```sh
npm install -g kbglow
```

That's it. The installer detects the AI CLIs on your machine and wires them all up automatically. Your existing settings are preserved (with a backup), and `kbglow-setup --remove` undoes everything.

Optional extras:

```sh
kbglow-setup --done     # short fast blink when a turn completes, too
kbglow-setup --watch    # GUI apps (Claude Desktop / ChatGPT) — guided setup
```

<details>
<summary>Install from source instead (no npm)</summary>

```sh
git clone https://github.com/totota-08/kbglow.git
cd kbglow
make install        # installs to ~/.local/bin/kbglow
```

Wire hooks up yourself — `examples/claude-code-hooks.json` is a template.

</details>

## Supported AI tools

| CLI | blink on approval-wait | stop / done-blink on turn end |
|---|---|---|
| <img src="https://github.com/anthropics.png?size=32" width="16" alt=""> Claude Code | ✓ | ✓ |
| <img src="https://github.com/google-gemini.png?size=32" width="16" alt=""> Gemini CLI | ✓ | ✓ |
| <img src="https://github.com/QwenLM.png?size=32" width="16" alt=""> Qwen Code | ✓ | ✓ |
| <img src="https://github.com/github.png?size=32" width="16" alt=""> GitHub Copilot CLI | ✓ | ✓ |
| <img src="https://github.com/Factory-AI.png?size=32" width="16" alt=""> Factory Droid | ✓ | ✓ |
| <img src="https://github.com/anomalyco.png?size=32" width="16" alt=""> opencode | ✓ | ✓ |
| <img src="https://github.com/cursor.png?size=32" width="16" alt=""> Cursor CLI | — (no approval event) | ✓ |
| <img src="https://github.com/openai.png?size=32" width="16" alt=""> Codex CLI | — (terminal-notification only) | ✓ (`--done`) |

Each CLI is wired through its own official hook/notify mechanism — no polling, no wrappers. Aider, Goose, and Amp aren't wired yet; PRs welcome.

**GUI apps** (Claude Desktop, the ChatGPT app) have no hooks, so `kbglow-setup --watch` installs a background watcher that blinks when they post a notification and stops when you focus the app. It walks you through the one manual step (granting Full Disk Access) and confirms when it works. Two caveats: the blink starts ~5–10s after the notification (macOS writes them lazily), and after updating kbglow the grant must be re-added (it is tied to the binary's signature — the updater reminds you).

## CLI usage

```
kbglow set <0-100>      Set brightness (percent)
kbglow get              Print current brightness
kbglow on / off         Full brightness / off
kbglow pulse            Blink until stopped (the approval alert)
    --blink               Hard 0/100 blinking instead of breathing
    -t, --timeout <sec>   Auto-stop after N seconds (default 600)
    --period <sec>        Cycle length (default 1.6)
    --min / --max <0-100> Low / high point of the cycle
kbglow watch            Blink on GUI-app notifications (foreground)
    --app <bundle-id>     App to watch, repeatable
    -t, --timeout <sec>   Max blink per notification (default 120)
kbglow stop             Stop a running pulse, restore previous state

kbglow-setup                 (Re)wire every detected AI CLI
kbglow-setup --remove        Remove every kbglow hook and generated file
kbglow-setup --done          Also blink briefly when a turn completes
kbglow-setup --done-remove   Approval-only blinking again
kbglow-setup --watch         Install the GUI-app watcher (guided)
kbglow-setup --watch-remove  Remove the watcher
```

`pulse` restores the previous brightness and auto-brightness setting on exit. Only one session runs at a time; starting a new one replaces the old. Any agent that can run a shell command can integrate manually — call `kbglow pulse` and `kbglow stop`.

## Requirements

- **macOS only.** kbglow drives the keyboard backlight through Apple's private CoreBrightness framework — there is nothing for it to do on Windows or Linux.
- A Mac with a backlit keyboard (MacBook Air / Pro).
- **Honest hardware note:** the only machine I own is an M1 MacBook Air, so that is the only hardware kbglow is actually verified on. It is built as a universal binary and should work on Intel and newer Apple Silicon Macs, but I cannot test those — reports (good or bad) are very welcome.

## Under the hood

Backlight control comes from [BacklightKit](https://github.com/totota-08/BacklightKit) (the private `CoreBrightness` framework, loaded at runtime — may break in a future macOS). The GUI-app watcher reads the Notification Center database, which is why it needs Full Disk Access.

## Troubleshooting

- `no controllable keyboard backlight found` — this Mac has no controllable backlight (or only an external keyboard)
- Brightness changes on its own — macOS auto-brightness; kbglow disables it during a pulse and restores it afterwards
- Watcher not blinking — check `/tmp/kbglow.watch.log`; it usually means Full Disk Access is missing

## License

MIT
