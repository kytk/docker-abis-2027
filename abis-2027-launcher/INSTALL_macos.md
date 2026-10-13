# ABiS Lin4Neuro ランチャーの入手方法（macOS）

ランチャーは**ターミナルから入手してください**。ブラウザでダウンロードすると、
macOS のセキュリティ機能（Gatekeeper）によってランチャーを開くのに工夫がいるようになります。

## 手順

1. **ターミナルを開きます。**
   `command` + `space` で Spotlight を開き、「ターミナル」または `terminal` と
   入力して `return` を押します。

2. **次の 1 行をコピーしてターミナルに貼り付け、`return` を押します。**

   ```
   set -o pipefail; curl -fsSL https://github.com/kytk/abis-web-2027/releases/latest/download/abis-2027-launcher-macos.tar.gz | tar xz -C ~ && open ~/abis-2027-launcher-macos
   ```

   ホームフォルダに `abis-2027-launcher-macos` フォルダができ、Finder で開きます。

3. **Finder に表示されたファイルをダブルクリックして使います。**

   | ファイル | 使うとき |
   |---|---|
   | `0_Check_Environment.command` | 講習の前に、PC が条件を満たしているか確認する |
   | `1_Download_Image.command` | 講習の前に、解析環境をダウンロードする（約 20 GB） |
   | `2_Start_Lin4Neuro.command` | 講習のたびに、解析環境を起動する |
   | `3_Stop_Lin4Neuro.command` | 講習のたびに、解析環境を終了する |
   | `4_Configure_Docker.command` | 環境チェックで「メモリが足りない」「Rosetta が使われていない」と出たときに、Docker の設定を変更する（もう一度実行すると元に戻せます） |

   ターミナルはもう閉じてかまいません。

**フォルダを見つけやすくするには**：Finder のサイドバーの「よく使う項目」に
`abis-2027-launcher-macos` フォルダをドラッグしておくと便利です。

## ランチャーを新しくするとき

同じ 1 行をもう一度実行してください。ランチャーのファイルが上書きされます。
いま使っている版は、フォルダの中の `README.txt` の「版」の行で確認できます。
`abis_check_result.txt`（環境チェックの結果）はそのまま残ります。

## うまくいかないとき

### 「開けません」「Apple は検証できませんでした」と表示される

ブラウザでダウンロードしたファイルを使っている可能性があります。
ターミナルで次の 1 行を実行してから、もう一度ダブルクリックしてください。

```
xattr -dr com.apple.quarantine ~/abis-2027-launcher-macos
```

フォルダをホーム以外の場所（ダウンロード フォルダなど）に置いている場合は、
`~/abis-2027-launcher-macos` の部分をそのフォルダに置き換えてください。
ターミナルに `xattr -dr com.apple.quarantine ` まで入力し（最後に半角スペース）、
Finder からフォルダをターミナルにドラッグすると、場所が自動で入力されます。

### `curl: (6) Could not resolve host` と表示される

インターネットにつながっていません。接続を確認してからもう一度実行してください。

### `The requested URL returned error: 404` と表示される

コマンドの一部が欠けている可能性があります。1 行全体をもう一度コピーして
貼り付けてください。それでも同じ表示が出る場合は、講師に連絡してください。
