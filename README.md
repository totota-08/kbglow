# kbglow ⌨️✨

**Your keyboard glows while your AI waits for approval.**

[日本語版 README はこちら](README.ja.md)

When an agent like Claude Code stops and asks for permission, your Mac's keyboard backlight starts blinking — so you notice from the corner of your eye, even with notification sounds off or another window in front.

Zero dependencies, single Swift binary, macOS only.

## Install

```sh
npm install -g kbglow
```

That's it. The install automatically wires kbglow into Claude Code's hooks (`~/.claude/settings.json`), so the very next approval prompt makes your keyboard blink. A backup of your previous settings is saved as `settings.json.kbglow-bak`, and you can undo everything with:

```sh
kbglow-setup --remove
```

If the automatic setup was skipped (e.g. permissions), run `kbglow-setup` manually.

<details>
<summary>Install from source instead (no npm)</summary>

```sh
git clone https://github.com/totota-08/kbglow.git
cd kbglow
make install        # installs to ~/.local/bin/kbglow
```

Then add the hooks from `examples/claude-code-hooks.json` to `~/.claude/settings.json` yourself.

</details>

## Requirements

- A Mac with a backlit keyboard (MacBook Air / Pro)
- Apple Silicon or Intel (tested on M1 MacBook Air)

## How it works with Claude Code

- The **Notification** hook (approval / input needed) starts `kbglow pulse` → the keyboard begins blinking
- Approving a tool (**PostToolUse**), sending a prompt (**UserPromptSubmit**), or the turn ending (**Stop**) runs `kbglow stop` → blinking stops and the previous brightness is restored

Any other agent that can run a shell command while waiting for approval can do the same — just call `kbglow pulse`.

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
kbglow stop             Stop a running pulse, restore previous state
kbglow-setup            (Re)install the Claude Code hooks
kbglow-setup --remove   Remove the Claude Code hooks
```

`pulse` restores the previous brightness and auto-brightness setting on exit. Only one session runs at a time; starting a new one replaces the old.

## Under the hood

Backlight control uses the private `CoreBrightness` framework (`KeyboardBrightnessClient`), loaded at runtime. Being a private API, it may break in a future macOS release.

## Troubleshooting

- `no controllable keyboard backlight found` — this Mac has no controllable backlight (or only an external keyboard)
- Brightness changes on its own — macOS auto-brightness; kbglow disables it during a pulse and restores it afterwards

## License

MIT
