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

- **macOS 専用**です。Apple のプライベートフレームワーク CoreBrightness でキーボードバックライトを制御しているため、Windows / Linux では動作しません。
- キーボードバックライト付きの Mac(MacBook Air / Pro)。
- **正直な注記:** 作者が所有しているのは M1 MacBook Air の1台だけで、実際に動作検証できているのはその環境のみです。ユニバーサルバイナリとしてビルドしているので Intel や新しい Apple Silicon でも動くはずですが、手元で確認はできていません。動いた/動かなかったの報告を歓迎します。

## Claude Code との連携の仕組み

- **Notification** フック(承認待ち・入力待ちの通知)で `kbglow pulse` が起動 → キーボードが明滅し始める
- 承認してツールが動く(**PostToolUse**)、プロンプトを送る(**UserPromptSubmit**)、ターンが終わる(**Stop**)のいずれかで `kbglow stop` → 明滅が止まり元の明るさに戻る

Claude Code 以外のエージェントでも、「承認待ちで任意コマンドを実行できる」仕組みがあれば `kbglow pulse` を呼ぶだけで同じことができます。

ターンの**完了時**にも短く速い点滅が欲しい場合はオプトインで:

```sh
kbglow-setup --done           # Claude Code の Stop フック + Codex CLI の notify
kbglow-setup --done-remove    # 承認待ちのみに戻す
```

([Codex CLI](https://developers.openai.com/codex) は `~/.codex/config.toml` の公式 `notify` オプション(`agent-turn-complete` で発火)を使います。既に notify を設定済みの場合は触りません。)

## その他の AI CLI

`kbglow-setup` はインストール済みの AI CLI を自動検出し、それぞれが公開しているシグナルに応じて自動配線します。既存の設定は保持され、`kbglow-setup --remove` で痕跡ごと全部消えます:

| CLI | 承認待ちで点滅 | ターン終了で消灯/完了点滅 |
|---|---|---|
| Claude Code | ✓ | ✓ |
| Gemini CLI | ✓ | ✓ |
| Qwen Code | ✓ | ✓ |
| GitHub Copilot CLI | ✓ | ✓ |
| Factory Droid | ✓ | ✓ |
| opencode | ✓ | ✓ |
| Cursor CLI | —(承認イベントなし) | ✓ |
| Codex CLI | —(ターミナル通知のみ) | ✓(`--done`) |

Aider / Goose / Amp は未対応です(設定枠が1つしかない・コードプラグイン必須などの理由)。PR歓迎。

## Claude デスクトップ / ChatGPT アプリ(GUIアプリ)

GUIアプリにはフック機構がないため、kbglow は代わりに **macOS の通知センターを監視**します。Claude デスクトップや ChatGPT アプリが通知を出したら(タスク完了・要対応など)キーボードが明滅し、**そのアプリにフォーカスを移すと消灯**します。セットアップ:

```sh
kbglow-setup --watch
```

ログイン時に自動起動する常駐エージェント(`kbglow watch`)が入り、そのまま**macOSが人間にしかさせてくれない唯一のステップ**(通知センターDBの読み取りに必要なフルディスクアクセスの付与)まで誘導します。コマンドがバイナリを選択済みのFinderとフルディスクアクセス設定画面を並べて開くので、ファイルをリストにドラッグしてトグルをオンにするだけ。付与された瞬間にコマンドが「✓ granted」と確認してくれます。補足:

- macOS は通知をDBに遅延書き込みするため、点滅開始は通知の**5〜10秒後**です
- フルディスクアクセスの許可はバイナリの署名に紐付くため、**kbglow を更新(`npm install -g kbglow`)したら一覧から削除→再追加**が必要です
- 光るのは「アプリが通知を出したとき」です。通知を出さないアプリ内の承認ダイアログは検知できません
- 他のアプリも `kbglow watch --app <bundle-id>` で監視可能。解除は `kbglow-setup --watch-remove`

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
kbglow watch            GUIアプリの通知で明滅(フォアグラウンド実行;
    --app <bundle-id>     監視対象アプリ。複数指定可。デフォルトは
                          Claudeデスクトップ + ChatGPT)
    -t, --timeout <秒>    通知1件あたりの最大点滅時間(デフォルト 120)
kbglow stop             実行中の pulse を止めて元の状態に戻す
kbglow-setup                 Claude Code フックを(再)設定
kbglow-setup --remove        kbglow のフックを全削除(Claude Code + Codex)
kbglow-setup --done          ターン完了時にも短く点滅
kbglow-setup --done-remove   承認待ちのみの点滅に戻す
kbglow-setup --watch         常駐ウォッチャーを設置(launchd)
kbglow-setup --watch-remove  常駐ウォッチャーを解除
```

`pulse` は終了時に元の明るさと自動調光設定を復元します。同時に動くのは1つだけで、新しく起動すると前のセッションは置き換わります。

## 仕組み

バックライト制御に、プライベートフレームワーク `CoreBrightness` の `KeyboardBrightnessClient` を実行時に読み込んで使用しています。プライベート API のため、将来の macOS で動かなくなる可能性があります。

## トラブルシューティング

- `no controllable keyboard backlight found` — バックライト非搭載の Mac か、外付けキーボードのみの環境です
- 明るさが勝手に変わる — macOS の自動調光と競合している場合、pulse 実行中は自動調光を一時無効化し、終了時に復元します

## 開発とリリース

普段の変更は `develop` ブランチ(デフォルト)に入れます。リリースするときは **Actions → release → Run workflow** でバージョンの上げ幅(patch / minor / major)と、必要ならリリースタイトルを選ぶだけ。ワークフローがバージョンを上げ、`develop` を `main` にマージし、npm へ publish して、GitHub Release を作成します(タイトル未指定なら `develop` の最新コミットメッセージ)。

## License

MIT
