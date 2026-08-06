# kbglow ⌨️✨

**AIの承認待ちでキーボードが光る。**

[English README is here](README.md)

Claude Code などのエージェントが「許可を求めて止まっている」とき、Mac のキーボードバックライトが明滅して知らせてくれます。通知音を切っていても、別の画面を見ていても、視界の端で気づけます。

依存ゼロの単一バイナリ。Swift 製。macOS 専用。

## インストール

```sh
npm install -g kbglow
```

これだけです。インストールと同時に Claude Code のフック(`~/.claude/settings.json`)が自動設定されるので、次の承認待ちからすぐキーボードが光ります。元の設定は `settings.json.kbglow-bak` にバックアップされ、いつでも元に戻せます:

```sh
kbglow-setup --remove
```

自動設定がスキップされた場合(権限など)は、手動で `kbglow-setup` を実行してください。

<details>
<summary>npm を使わずソースから入れる場合</summary>

```sh
git clone https://github.com/totota-08/kbglow.git
cd kbglow
make install        # ~/.local/bin/kbglow に入ります
```

その後、`examples/claude-code-hooks.json` のフックを `~/.claude/settings.json` に自分で追加してください。

</details>

## 対応環境

- キーボードバックライト付きの Mac(MacBook Air / Pro)
- Apple Silicon / Intel どちらも可(動作確認は M1 MacBook Air)

## Claude Code との連携の仕組み

- **Notification** フック(承認待ち・入力待ちの通知)で `kbglow pulse` が起動 → キーボードが明滅し始める
- 承認してツールが動く(**PostToolUse**)、プロンプトを送る(**UserPromptSubmit**)、ターンが終わる(**Stop**)のいずれかで `kbglow stop` → 明滅が止まり元の明るさに戻る

Claude Code 以外のエージェントでも、「承認待ちで任意コマンドを実行できる」仕組みがあれば `kbglow pulse` を呼ぶだけで同じことができます。

## CLI の使い方

```
kbglow set <0-100>      明るさを設定(%)
kbglow get              現在の明るさを表示
kbglow on / off         全点灯 / 消灯
kbglow pulse            明滅開始(承認待ちアラート用)
    --blink               呼吸ではなく 0/100 のハードな点滅
    -t, --timeout <秒>    自動停止までの秒数(デフォルト 600)
    --period <秒>         明滅1回の長さ(デフォルト 1.6)
    --min / --max <0-100> 明滅の下限・上限
kbglow stop             実行中の pulse を止めて元の状態に戻す
kbglow-setup            Claude Code フックを(再)設定
kbglow-setup --remove   Claude Code フックを削除
```

`pulse` は終了時に元の明るさと自動調光設定を復元します。同時に動くのは1つだけで、新しく起動すると前のセッションは置き換わります。

## 仕組み

バックライト制御に、プライベートフレームワーク `CoreBrightness` の `KeyboardBrightnessClient` を実行時に読み込んで使用しています。プライベート API のため、将来の macOS で動かなくなる可能性があります。

## トラブルシューティング

- `no controllable keyboard backlight found` — バックライト非搭載の Mac か、外付けキーボードのみの環境です
- 明るさが勝手に変わる — macOS の自動調光と競合している場合、pulse 実行中は自動調光を一時無効化し、終了時に復元します

## License

MIT
