# Apptainer コンテナのビルドと実行手順

## 前提条件

- Docker イメージ `kytk/abis-2027:latest` がローカルにビルド済みであること
- Apptainer がインストールされていること

## Step 1: .sif ファイルのビルド

```bash
cd apptainer
sudo apptainer build ../abis-2027.sif abis-2027.def
```

> `Bootstrap: docker-daemon` を使用しているため、ローカルの Docker イメージから直接ビルドします。

## Step 2: コンテナの実行（noVNC GUI モード）

```bash
apptainer run --writable-tmpfs --no-home --contain \
  --bind /path/to/share:/home/brain/share \
  abis-2027.sif
```

- `--writable-tmpfs`: 読み取り専用の .sif に対して一時的な書き込みレイヤーを提供
- `--no-home`: ホストの $HOME をマウントしない（コンテナ内の /home/brain を使用）
- `--contain`: ホストの /tmp 等を隔離し、X サーバーの衝突を防ぐ
- `--bind src:dst`: ホストのディレクトリをコンテナ内にマウント（共有フォルダが不要な場合はこの行を省略）

## Step 3: ブラウザで接続

- URL: `http://localhost:6080/vnc.html`
- パスワード: `lin4neuro`
- 終了: ターミナルで `Ctrl+C`

## シェルモード

```bash
apptainer shell --writable-tmpfs --no-home --contain \
  --bind /path/to/share:/home/brain/share \
  abis-2027.sif
```

## オプション: フラグの説明

| フラグ | 目的 |
|---|---|
| `--writable-tmpfs` | .sif は読み取り専用のため、tmpfs で書き込みレイヤーを追加 |
| `--no-home` | ホストの $HOME がコンテナの /home/brain を上書きするのを防ぐ |
| `--contain` | ホストの /tmp 等を隔離し、X サーバーとの衝突を防ぐ |
| `--bind src:dst` | ホストのディレクトリをコンテナ内にマウント |
