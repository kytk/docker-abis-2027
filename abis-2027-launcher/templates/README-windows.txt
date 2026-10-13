ABiS Lin4Neuro ランチャー (Windows)
========================================

  版       : @VERSION@
  作成日時 : @BUILT@
  イメージ : @IMAGE@

■ 使い方 (ファイルをダブルクリックします)

  0_Check_Environment.bat  講習の前に、パソコンが条件を満たしているか確認する
  1_Download_Image.bat     講習の前に、解析環境をダウンロードする (約 20 GB)
  2_Start_Lin4Neuro.bat    講習のたびに、解析環境を起動する
  3_Stop_Lin4Neuro.bat     講習のたびに、解析環境を終了する
  4_Configure_WSL.bat      環境チェックで「メモリが足りない」と出たときに、
                           Docker が使えるメモリを増やす
                           (もう一度実行すると元に戻せます)

  lib フォルダの中身は直接開かないでください。

■ ランチャーを新しくするには

  入手したときと同じ 1 行のコマンドを、もう一度 PowerShell で実行してください。
  ファイルが上書きされ、この README.txt の「版」が新しくなります。
  公開されている最新の版は次のページで確認できます:
  @URL@

■ うまくいかないとき

  0_Check_Environment.bat を実行し、できあがった
  abis_check_result.txt をチュートリアルのチャットに送ってください。
  ランチャーの版もその中に書かれています。
