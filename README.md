# kbglow ⌨️✨

Mac のキーボードバックライトを「通知デバイス」にする小さな CLI ツールです。

- 🤖 **AIエージェントの承認待ちで光る** — Claude Code などのエージェントが許可を求めて止まっているとき、キーボードがふわふわ明滅して知らせてくれる
- 🔊 **システム音声に合わせて光る** — Mac で再生中の音の音量にバックライトが追従
- 👋 **[SlapMac](https://slapmac.com/) 連携** — Mac を叩くと喘ぐアレの声に合わせてキーボードも光る（音声リアクティブモードがそのまま反応します）

依存ゼロの単一バイナリ。Swift 製。

## 対応環境

- キーボードバックライト付きの Mac(MacBook Air / Pro)
- macOS 14.2 以降(`audio` モードに必要。`pulse` / `set` はそれ以前でも動くはず)
- Apple Silicon / Intel どちらも可(動作確認は M1 MacBook Air + macOS 26)

## インストール

```sh
git clone https://github.com/PenginPenPen/kbglow.git
cd kbglow
make install        # ~/.local/bin/kbglow に入ります
```

`~/.local/bin` にパスが通っていない場合は `.zshrc` に:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

## 使い方

```
kbglow set <0-100>      明るさを設定(%)
kbglow get              現在の明るさを表示
kbglow on / off         全点灯 / 消灯
kbglow pulse            呼吸するように明滅(承認待ちアラート用)
    -t, --timeout <秒>    自動停止までの秒数(デフォルト 600)
    --period <秒>         呼吸1回の長さ(デフォルト 1.6)
    --min / --max <0-100> 明滅の下限・上限
kbglow audio            再生中のシステム音声に合わせて光る
    --gain <n>            感度(デフォルト 6)
    --base <0-100>        無音時の明るさの下限
kbglow stop             実行中の pulse / audio を止めて元の状態に戻す
```

`pulse` と `audio` は終了時に元の明るさと自動調光設定を復元します。同時に動くのは1つだけで、新しく起動すると前のセッションは置き換わります。

## Claude Code 連携(承認待ちで光らせる)

`~/.claude/settings.json` にフックを追加します(`examples/claude-code-hooks.json` 参照)。

```json
{
  "hooks": {
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.local/bin/kbglow pulse -t 600 >/dev/null 2>&1 &"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          { "type": "command", "command": "$HOME/.local/bin/kbglow stop" }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "$HOME/.local/bin/kbglow stop" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "$HOME/.local/bin/kbglow stop" }
        ]
      }
    ]
  }
}
```

動きとしては:

- **Notification** フック(承認待ち・入力待ちの通知)で `kbglow pulse` が起動 → キーボードが明滅し始める
- 承認してツールが動く(**PostToolUse**)、プロンプトを送る(**UserPromptSubmit**)、ターンが終わる(**Stop**)のいずれかで `kbglow stop` → 明滅が止まり元の明るさに戻る

Claude Code 以外のエージェントでも、「承認待ちで任意コマンドを実行できる」仕組みがあれば `kbglow pulse` を呼ぶだけで同じことができます。

## 音声リアクティブ / SlapMac 連携

```sh
kbglow audio
```

Mac で再生中のすべての音声(音楽、動画、通知音、そして [SlapMac](https://slapmac.com/) の喘ぎ声)の音量にバックライトが追従します。SlapMac([オープンソース版 MacSlapApp](https://github.com/AbdullahFID/MacSlapApp) でも可)を起動して `kbglow audio` を実行しておけば、Mac を叩く → 喘ぐ → 声に合わせてキーボードが光る、が完成します。

### 初回のみ: システム音声の録音許可

`audio` モードは Core Audio のプロセスタップでシステム音声を拾うため、初回実行時に **「システム音声の録音」権限** の許可ダイアログが表示されます。許可すると次回から動きます。

ダイアログが出ない・無音のままの場合は、**システム設定 > プライバシーとセキュリティ > 画面収録とシステム音声の録音** で、使っているターミナルアプリ(または `kbglow` バイナリ)を「+」から追加してください。

音は録音・保存されません。音量(RMS)を計算して明るさに変換しているだけです。

## 仕組み

- バックライト制御: プライベートフレームワーク `CoreBrightness` の `KeyboardBrightnessClient` を実行時に読み込んで使用
- 音声検知: Core Audio のプロセスタップ(macOS 14.2+ の `AudioHardwareCreateProcessTap`)で全プロセスの出力をミックスした RMS を明るさにマッピング

プライベート API を使っているため、将来の macOS で動かなくなる可能性があります。

## トラブルシューティング

- `no controllable keyboard backlight found` — バックライト非搭載の Mac か、外付けキーボードのみの環境です
- `audio` が反応しない — 上記の録音許可を確認。`KBGLOW_DEBUG=1 kbglow audio` でコールバックと RMS 値がログに出ます
- 明るさが勝手に変わる — macOS の自動調光と競合している場合、pulse/audio 実行中は自動調光を一時無効化し、終了時に復元します

## License

MIT

---

### English (TL;DR)

`kbglow` turns your Mac's keyboard backlight into a notification device: it breathes while your AI agent (e.g. Claude Code) is waiting for approval, and can pulse in sync with whatever audio your Mac is playing — including the moans from [SlapMac](https://slapmac.com/). Install with `make install`, wire it up via Claude Code hooks (see `examples/claude-code-hooks.json`). Uses the private CoreBrightness framework for backlight control and a Core Audio process tap (macOS 14.2+) for audio reactivity; the first `kbglow audio` run needs the System Audio Recording permission.
