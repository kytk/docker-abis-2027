# docker-abis-2027

ABiS 脳 MRI チュートリアル（2027年1〜2月）で使う神経画像解析環境を Docker
コンテナとして構築するプロジェクトです。ブラウザから noVNC 経由で
Lin4Neuro デスクトップに接続して使います。

受講者向けの起動用スクリプトは `abis-2027-launcher/` にあります。

## 収録ソフトウェア

FreeSurfer 8.2.0 / FSL 6.0.7.23 / SPM25 / CONN25b / ANTs / MRtrix3 /
MRIcroGL / dcm2niix / AlizaMS / Python（nibabel, pydicom, nipype, heudiconv ほか）

## 受講者向け: 起動のしかた

`abis-2027-launcher/` の中の、お使いの OS 用のフォルダをダブルクリックで使います。

| スクリプト | いつ | 内容 |
|---|---|---|
| `0_Check_Environment` | 事前に一度 | 動作条件を満たしているか確認し、結果をファイルに出力します |
| `1_Download_Image` | 一度だけ | イメージをダウンロードします（約 20 GB、40〜60 分） |
| `2_Start_Lin4Neuro` | 毎回 | 共有フォルダを選んで起動し、ブラウザを開きます |
| `3_Stop_Lin4Neuro` | 毎回 | 終了します |

### 事前準備

- **Docker Desktop** をインストールしてください
- 内蔵ディスクの空き容量を **100 GB** 以上確保してください
- 共有フォルダを用意してください（Windows では **NTFS** 形式のドライブが必要です）
- FreeSurfer の `license.txt` を共有フォルダに置いてください

作業したファイルは必ず共有フォルダの中に保存してください。コンテナは終了時に
破棄されるため、共有フォルダの外に置いたものは残りません。

## 手動で起動する場合

```bash
docker run -d --rm \
  --name abis \
  --platform linux/amd64 \
  --shm-size 2g \
  -v /path/to/share:/home/brain/share \
  -p 127.0.0.1:6080:6080 \
  kytk/abis-2027:26.12
```

ブラウザで以下を開きます（パスワードは `lin4neuro`）。

```
http://127.0.0.1:6080/vnc.html?resize=scale&autoconnect=1&password=lin4neuro
```

終了は `docker stop abis`（`--rm` なので自動的に削除されます）。

- `-p` は `127.0.0.1` に限定しています。パスワードが公開されているため、
  同じネットワークの他の端末から接続できる状態にしないでください
- `--privileged` は不要です
- 画面解像度は 1920x1080 固定です（`build/init/supervisord.conf`）

## 開発者向け

```bash
docker build --progress=plain -t kytk/abis-2027:26.12 . 2>&1 | tee build.log
```

| ディレクトリ | 内容 |
|---|---|
| `build/` | イメージのビルドに使うもの一式（`packages/` は `.gitignore` 対象） |
| `abis-2027-launcher/` | 受講者向けランチャー（Windows / macOS） |
| `apptainer/` | Apptainer 用の定義ファイルとビルド手順 |
| `wsl2/` | WSL2 + xrdp 版（experimental） |

詳しい経緯・判断の理由・残作業は **`LOG.md`**、開発時の注意点は `CLAUDE.md` を
参照してください。

## ライセンスと注意

この Docker イメージは研究および教育目的で提供されています。含まれるソフトウェア
パッケージのライセンス条項を遵守してご使用ください。
