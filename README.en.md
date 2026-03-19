# XHS Organizer

[简体中文](./README.md) | [日本語](./README.ja.md)

![XHS Organizer Overview](./docs/assets/app-overview.png)

A macOS desktop app that turns a messy Xiaohongshu favorites folder into something you can actually sync, sort, revisit, and export.

[Download latest release](https://github.com/leoyoyofiona/xiaohongshu-favorites/releases/latest) | [Release notes](https://github.com/leoyoyofiona/xiaohongshu-favorites/releases/tag/v0.1.0)

## Why it exists

- Favorites keep growing, but useful content becomes harder to find.
- Papers, tools, tutorials, and inspiration all get mixed together.
- Xiaohongshu’s default UI is not built for long-term desktop organization.
- Exporting the original text and images of a saved post is tedious.

## What it does

- Syncs your Xiaohongshu favorites from the current Chrome favorites page.
- Deduplicates and auto-categorizes saved items.
- Gives you a clean 3-column desktop layout.
- Supports read status, starred items, and previous/next article navigation.
- Exports the current article text, source link, and all images in one click.

## Screenshots

### Main workspace

![XHS Organizer main workspace](./docs/assets/app-overview.png)

### Reading and export

![XHS Organizer reading view](./docs/assets/app-reading.png)

## Install

### Install from release

1. Open [Releases](https://github.com/leoyoyofiona/xiaohongshu-favorites/releases/latest)
2. Download `小红书收藏导航.dmg`
3. Drag `小红书收藏导航.app` into `Applications`
4. If macOS blocks the first launch, right-click and choose `Open`

### Run from source

Requirements:

- macOS 15+
- Xcode Command Line Tools
- Swift 6.2

```bash
swift run XHSOrganizerApp
```

## How to use

1. Open your Xiaohongshu favorites page in Chrome.
2. Open the app.
3. Click `同步小红书`.
4. Click `从当前 Chrome 收藏夹同步`.
5. Browse, read, and export inside the app.

## Export current article

Click `下载原文` in the detail pane:

- exports `原文.txt`
- exports `原文链接.txt`
- downloads all images from the current post
- saves everything into `Downloads/小红书收藏导出/`

## Current sync model

- Sync currently depends on Chrome.
- This is the most stable approach so far.
- Embedded web syncing was more likely to trigger platform risk controls.
- Older items imported with incomplete links may need one more sync pass.

## Project structure

- `Sources/XHSOrganizerApp`: macOS SwiftUI app
- `Sources/XHSOrganizerCore`: models, import, classification, search
- `scripts/build_dmg.sh`: package `.app` and `.dmg`
- `scripts/generate_app_icon.py`: generate the app icon

## Build a DMG

```bash
./scripts/build_dmg.sh
```

Outputs:

- `dist/小红书收藏导航.app`
- `dist/小红书收藏导航.dmg`
