ABiS Lin4Neuro ランチャー (macOS)
========================================

  版       : @VERSION@
  作成日時 : @BUILT@
  イメージ : @IMAGE@

■ 使い方 (ファイルをダブルクリックします)

  0_Check_Environment.command  講習の前に、Mac が条件を満たしているか確認する
  1_Download_Image.command     講習の前に、解析環境をダウンロードする (約 20 GB)
  2_Start_Lin4Neuro.command    講習のたびに、解析環境を起動する
  3_Stop_Lin4Neuro.command     講習のたびに、解析環境を終了する
  4_Configure_Docker.command   環境チェックで「メモリが足りない」「Rosetta が
                               使われていない」と出たときに、Docker の設定を
                               変更する (もう一度実行すると元に戻せます)

  lib フォルダの中身は直接開かないでください。

■ ランチャーを新しくするには

  入手したときと同じ 1 行のコマンドを、もう一度ターミナルで実行してください。
  ファイルが上書きされ、この README.txt の「版」が新しくなります。
  公開されている最新の版は次のページで確認できます:
  @URL@

■ うまくいかないとき

  0_Check_Environment.command を実行し、できあがった
  abis_check_result.txt をチュートリアルのチャットに送ってください。
  ランチャーの版もその中に書かれています。
