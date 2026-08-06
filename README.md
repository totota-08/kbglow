# kbglow ⌨️✨

**AIエージェントの承認待ちでキーボードが光る**、小さな CLI ツールです。

Claude Code などのエージェントが「許可を求めて止まっている」とき、Mac のキーボードバックライトがふわふわ明滅して知らせてくれます。通知音を切っていても、別の画面を見ていても、視界の端で気づけます。

依存ゼロの単一バイナリ。Swift 製。

## 対応環境

- キーボードバックライト付きの Mac(MacBook Air / Pro)
- Apple Silicon / Intel どちらも可(動作確認は M1 MacBook Air + macOS 26)

## インストール

```sh
git clone https://github.com/totota-08/kbglow.git
cd kbglow
make install        # ~/.local/bin/kbglow に入ります
```

`~/.local/bin` にパスが通っていない場合は `.zshrc` に:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

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
            "command": "$HOME/.local/bin/kbglow pulse --blink --period 2 -t 600 >/dev/null 2>&1 &"
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

## 使い方

```
kbglow set <0-100>      明るさを設定(%)
kbglow get              現在の明るさを表示
kbglow on / off         全点灯 / 消灯
kbglow pulse            呼吸するように明滅(承認待ちアラート用)
    --blink               呼吸ではなく 0/100 のハードな点滅
    -t, --timeout <秒>    自動停止までの秒数(デフォルト 600)
    --period <秒>         明滅1回の長さ(デフォルト 1.6)
    --min / --max <0-100> 明滅の下限・上限
kbglow stop             実行中の pulse を止めて元の状態に戻す
```

`pulse` は終了時に元の明るさと自動調光設定を復元します。同時に動くのは1つだけで、新しく起動すると前のセッションは置き換わります。

## 仕組み

バックライト制御に、プライベートフレームワーク `CoreBrightness` の `KeyboardBrightnessClient` を実行時に読み込んで使用しています。プライベート API のため、将来の macOS で動かなくなる可能性があります。

## トラブルシューティング

- `no controllable keyboard backlight found` — バックライト非搭載の Mac か、外付けキーボードのみの環境です
- 明るさが勝手に変わる — macOS の自動調光と競合している場合、pulse 実行中は自動調光を一時無効化し、終了時に復元します

## License

MIT

---

### English (TL;DR)

`kbglow` turns your Mac's keyboard backlight into an "AI is waiting for you" indicator: it breathes (or blinks) while your agent — e.g. Claude Code — is stopped waiting for approval, and restores the previous brightness once you respond. Install with `make install`, wire it up via Claude Code hooks (see `examples/claude-code-hooks.json`). Zero dependencies; uses the private CoreBrightness framework for backlight control.
