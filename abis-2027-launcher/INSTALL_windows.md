# ABiS Lin4Neuro ランチャーの入手方法（Windows）

ランチャーは**PowerShell から入手してください**。この方法なら、ランチャーを
開くときに「Windows によって PC が保護されました」という警告が出ません。

## 手順

1. **PowerShell を開きます。**
   スタートメニューを開いて `powershell` と入力し、「Windows PowerShell」を
   クリックします。
   （「コマンド プロンプト」ではなく **PowerShell** を開いてください。
   管理者として実行する必要はありません。）

2. **次の 1 行をコピーして PowerShell に貼り付け、`Enter` を押します。**
   貼り付けは右クリックまたは `Ctrl` + `V` です。

   ```
   curl.exe -fsSL -o "$env:TEMP\abis-2027-launcher-windows.zip" https://github.com/kytk/abis-web-2027/releases/latest/download/abis-2027-launcher-windows.zip; if ($?) { New-Item -ItemType Directory -Force "$HOME\abis-2027-launcher-windows" | Out-Null; tar.exe -xf "$env:TEMP\abis-2027-launcher-windows.zip" -C "$HOME\abis-2027-launcher-windows"; if ($?) { explorer.exe "$HOME\abis-2027-launcher-windows" } }
   ```

   ユーザーフォルダ（`C:\Users\<ユーザー名>`）に `abis-2027-launcher-windows`
   フォルダができ、エクスプローラーで開きます。

3. **エクスプローラーに表示されたファイルをダブルクリックして使います。**

   | ファイル | 使うとき |
   |---|---|
   | `0_Check_Environment.bat` | 講習の前に、PC が条件を満たしているか確認する |
   | `1_Download_Image.bat` | 講習の前に、解析環境をダウンロードする（約 20 GB） |
   | `2_Start_Lin4Neuro.bat` | 講習のたびに、解析環境を起動する |
   | `3_Stop_Lin4Neuro.bat` | 講習のたびに、解析環境を終了する |
   | `4_Configure_WSL.bat` | 環境チェックで「メモリが足りない」と出たときに、Docker が使えるメモリを増やす（もう一度実行すると元に戻せます） |

   PowerShell はもう閉じてかまいません。

**フォルダを見つけやすくするには**：エクスプローラーで
`abis-2027-launcher-windows` フォルダを右クリックし、「クイック アクセスに
ピン留めする」を選んでおくと便利です。

## ランチャーを新しくするとき

同じ 1 行をもう一度実行してください。ランチャーのファイルが上書きされます。
いま使っている版は、フォルダの中の `README.txt` の「版」の行で確認できます。
`abis_check_result.txt`（環境チェックの結果）はそのまま残ります。

## うまくいかないとき

### 赤い文字で `Invoke-WebRequest` や `パラメーター` のエラーが出る

コマンドの一部が欠けているか、`curl.exe` の `.exe` が抜けている可能性があります。
1 行全体をもう一度コピーして貼り付けてください。

### `curl: (6) Could not resolve host` と表示される

インターネットにつながっていません。接続を確認してからもう一度実行してください。

### `The requested URL returned error: 404` と表示される

コマンドの一部が欠けている可能性があります。1 行全体をもう一度コピーして
貼り付けてください。それでも同じ表示が出る場合は、講師に連絡してください。

### `'curl.exe' は認識されていません` と表示される

Windows が古い（Windows 10 の 2018 年春より前の版）可能性があります。
下の「ブラウザで入手する方法」を使ってください。

### PowerShell を使わずに入手したい（ブラウザで入手する方法）

1. ブラウザで次のアドレスを開き、zip ファイルをダウンロードします。
   `https://github.com/kytk/abis-web-2027/releases/latest/download/abis-2027-launcher-windows.zip`
2. ダウンロードした zip を右クリック →「プロパティ」を開き、下のほうにある
   **「許可する」**（Windows 10 では「ブロックの解除」）にチェックを入れて
   「OK」を押します。**展開する前に**行ってください。
3. zip を右クリック →「すべて展開」で展開します。

手順 2 を飛ばすと、ランチャーを開くたびに警告が出ます。その場合は
展開したフォルダを削除し、手順 2 からやり直してください。
