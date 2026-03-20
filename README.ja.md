# 小紅書コレクションナビ

<p align="center">増え続ける小紅書のお気に入りを、同期・分類・再閲覧・書き出しできる macOS デスクトップライブラリに変えるアプリです。</p>

<p align="center"><strong>macOS 専用です。macOS 15 以上が必要で、Windows / Linux には対応していません。</strong></p>

<p align="center">
  <a href="https://github.com/leoyoyofiona/xiaohongshu-favorites/releases/latest"><img src="https://img.shields.io/github/v/release/leoyoyofiona/xiaohongshu-favorites?display_name=tag&label=Release" alt="Release" /></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="MIT License" /></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-black?logo=apple" alt="macOS 15+" />
  <img src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white" alt="Swift 6.2" />
</p>

<p align="center">
  <a href="./README.md">简体中文</a> · <a href="./README.en.md">English</a>
</p>

<p align="center">
  <img src="./docs/assets/app-overview.png" alt="アプリ全体画面" width="100%" />
</p>

## 解決したいこと

- お気に入りが増え続け、必要な時に見つけにくい
- 論文、ツール、教育、アイデアが混ざって再利用しにくい
- 小紅書の標準お気に入りUIは、長期整理には向いていない
- 原文や画像をまとめて保存するのが面倒

## 主な機能

- Chrome で現在開いている小紅書お気に入りページから同期
- 重複排除と自動主分類
- 左に分類、中央に一覧、右に原文寄りの閲覧という 3 カラム構成
- 既読、重要マーク、前の記事 / 次の記事、最近同期の再確認
- 現在の記事本文、元リンク、画像一式をワンクリックで保存
- アプリ内でそのまま小紅書を開いて閲覧・同期

## スクリーンショット

### 1. 全体画面

![全体画面](./docs/assets/app-overview.png)

### 2. 同期状態

![同期状態](./docs/assets/app-sync.png)

### 3. 原文確認 / 動画再生

![原文確認と動画再生](./docs/assets/app-reading.png)

## インストール

### リリース版を使う

1. [Releases](https://github.com/leoyoyofiona/xiaohongshu-favorites/releases/latest) を開く
2. `XHS-Organizer-macOS.dmg` をダウンロード
3. `小红书收藏导航.app` を `Applications` にドラッグ
4. 初回起動で止められた場合は右クリックして `開く`

補足:

- 本ソフトは macOS 15 以上専用です。
- 一般配布用パッケージは `.dmg` 形式です。

### ソースから起動

必要環境:

- macOS 15+
- Xcode Command Line Tools
- Swift 6.2

```bash
swift run XHSOrganizerApp
```

## クイックスタート

1. Chrome で小紅書のお気に入りページを開く
2. アプリを開く
3. `同步小红书` を押す
4. `从当前 Chrome 收藏夹同步` を押す
5. 以後はアプリ内で閲覧、整理、書き出し

## 現在の記事を書き出し

右側の `下载` を押すと:

- `原文.txt`
- `原文链接.txt`
- 現在の記事の画像一式

を `Downloads/小红书收藏导出/` に保存します。

## 現在の同期方式

- 現在は Chrome 経由の同期を使います
- これは現時点で最も安定しやすい方法です
- 無理に完全埋め込み自動同期にするより、プラットフォーム側の制限に引っかかりにくいです
- 過去の不完全リンクで取り込んだデータは再同期で改善する場合があります

## 技術構成

- `SwiftUI + AppKit` による macOS ネイティブUI
- `WKWebView` によるアプリ内小紅書ブラウズ
- ローカル保存による記事、状態、分類の管理
- 同期、重複排除、再分類、書き出しの独自パイプライン

## プロジェクト構成

- `Sources/XHSOrganizerApp`: macOS UI とデスクトップロジック
- `Sources/XHSOrganizerCore`: モデル、同期導入、分類、検索、書き出し
- `scripts/build_dmg.sh`: `.app` と `.dmg` の生成
- `scripts/generate_app_icon.py`: アプリアイコン生成

## DMG の作成

```bash
./scripts/build_dmg.sh
```

生成物:

- `dist/小红书收藏导航.app`
- `dist/小红书收藏导航.dmg`

## ライセンス

本プロジェクトは [MIT License](./LICENSE) で公開しています。
