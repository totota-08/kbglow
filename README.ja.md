# kbglow ⌨️✨

**AIの承認待ちでキーボードが光る。**

[English README is here](README.md)

Claude Code などのエージェントが「許可を求めて止まっている」とき、Mac のキーボードバックライトが明滅して知らせてくれます。通知音を切っていても、別の画面を見ていても、視界の端で気づけます。応答する(またはアプリにフォーカスする)と元の明るさに戻ります。

依存ゼロの単一バイナリ。Swift 製。macOS 専用。

## インストール

```sh
npm install -g kbglow
```

これだけです。インストーラーがマシン上の AI CLI を自動検出して、まとめて配線します。既存の設定は保持され(バックアップ付き)、`kbglow-setup --remove` で全部元に戻せます。

オプション:

```sh
kbglow-setup --done     # ターン完了時にも短く速い点滅
kbglow-setup --watch    # GUIアプリ(Claudeデスクトップ / ChatGPT)対応 — ガイド付き
```

<details>
<summary>npm を使わずソースから入れる場合</summary>

```sh
git clone https://github.com/totota-08/kbglow.git
cd kbglow
make install        # ~/.local/bin/kbglow に入ります
```

フックは自分で設定してください — `examples/claude-code-hooks.json` がテンプレートです。

</details>

## 対応 AI ツール

| CLI | 承認待ちで点滅 | ターン終了で消灯/完了点滅 |
|---|---|---|
| <img src="https://github.com/anthropics.png?size=32" width="16" alt=""> Claude Code | ✓ | ✓ |
| <img src="https://github.com/google-gemini.png?size=32" width="16" alt=""> Gemini CLI | ✓ | ✓ |
| <img src="https://github.com/QwenLM.png?size=32" width="16" alt=""> Qwen Code | ✓ | ✓ |
| <img src="https://github.com/github.png?size=32" width="16" alt=""> GitHub Copilot CLI | ✓ | ✓ |
| <img src="https://github.com/Factory-AI.png?size=32" width="16" alt=""> Factory Droid | ✓ | ✓ |
| <img src="https://github.com/anomalyco.png?size=32" width="16" alt=""> opencode | ✓ | ✓ |
| <img src="https://github.com/cursor.png?size=32" width="16" alt=""> Cursor CLI | —(承認イベントなし) | ✓ |
| <img src="https://github.com/openai.png?size=32" width="16" alt=""> Codex CLI | —(ターミナル通知のみ) | ✓(`--done`) |

各 CLI はそれぞれの公式フック/notify 機構で配線しています — ポーリングもラッパーもなし。Aider / Goose / Amp は未対応、PR歓迎。

**GUIアプリ**(Claudeデスクトップ、ChatGPTアプリ)にはフック機構がないため、`kbglow-setup --watch` が常駐ウォッチャーを設置します。アプリが通知を出したら点滅し、フォーカスすると消灯。唯一の手動ステップ(フルディスクアクセスの付与)もガイドしてくれて、効いた瞬間に確認表示が出ます。注意点は2つ: 点滅開始は通知の約5〜10秒後(macOSの遅延書き込みのため)、kbglow更新後は許可の再付与が必要(バイナリの署名に紐付くため。更新時に案内が出ます)。

## CLI の使い方

```
kbglow set <0-100>      明るさを設定(%)
kbglow get              現在の明るさを表示
kbglow on / off         全点灯 / 消灯
kbglow pulse            0/100のハードな点滅を開始(承認待ちアラート用)
    -t, --timeout <秒>    自動停止までの秒数(デフォルト 600)
    --period <秒>         明滅1回の長さ(デフォルト 1.6)
kbglow watch            GUIアプリの通知で明滅(フォアグラウンド)
    --app <bundle-id>     監視対象アプリ。複数指定可
    -t, --timeout <秒>    通知1件あたりの最大点滅時間(デフォルト 120)
kbglow stop             実行中の pulse を止めて元の状態に戻す

kbglow-setup                 検出した AI CLI をまとめて(再)配線
kbglow-setup --remove        kbglow のフック・生成ファイルを全削除
kbglow-setup --done          ターン完了時にも短く点滅
kbglow-setup --done-remove   承認待ちのみの点滅に戻す
kbglow-setup --watch         GUIアプリ用ウォッチャーを設置(ガイド付き)
kbglow-setup --watch-remove  ウォッチャーを解除
```

`pulse` は終了時に元の明るさと自動調光設定を復元します。同時に動くのは1つだけで、新しく起動すると前のセッションは置き換わります。シェルコマンドを実行できるエージェントなら手動連携も可能 — `kbglow pulse` と `kbglow stop` を呼ぶだけです。

## 対応環境

- **macOS 専用**です。Apple のプライベートフレームワーク CoreBrightness でキーボードバックライトを制御しているため、Windows / Linux では動作しません。
- キーボードバックライト付きの Mac(MacBook Air / Pro)。
- **正直な注記:** 作者が所有しているのは M1 MacBook Air の1台だけで、実際に動作検証できているのはその環境のみです。ユニバーサルバイナリとしてビルドしているので Intel や新しい Apple Silicon でも動くはずですが、手元で確認はできていません。動いた/動かなかったの報告を歓迎します。

## 仕組み

バックライト制御は [BacklightKit](https://github.com/totota-08/BacklightKit) 製(プライベートフレームワーク `CoreBrightness` を実行時に読み込み — 将来の macOS で動かなくなる可能性があります)。GUIアプリ用ウォッチャーは通知センターのDBを読むため、フルディスクアクセスが必要です。

## トラブルシューティング

- `no controllable keyboard backlight found` — バックライト非搭載の Mac か、外付けキーボードのみの環境です
- 明るさが勝手に変わる — macOS の自動調光と競合している場合、pulse 実行中は自動調光を一時無効化し、終了時に復元します
- ウォッチャーが光らない — `/tmp/kbglow.watch.log` を確認。大抵はフルディスクアクセス未付与です

## License

MIT
