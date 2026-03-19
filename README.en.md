# XHS Organizer

[简体中文](./README.md) | [日本語](./README.ja.md)

A macOS desktop app that turns a messy Xiaohongshu favorites folder into something you can actually browse, sort, revisit, and export.

## The problem

- Favorites keep growing, but useful content becomes harder to find.
- Xiaohongshu is not designed for long-term desktop organization.
- Papers, tools, education notes, and inspiration all get mixed together.
- Exporting the original text and images of a saved post is tedious.

## What this app does

- Syncs your Xiaohongshu favorites from a logged-in Chrome page.
- Deduplicates and auto-categorizes saved items.
- Gives you a clean 3-column desktop layout.
- Supports read status, favorites, previous/next article navigation.
- Lets you export the current article text and all images in one click.
- Builds a distributable `.dmg` for sharing.

## How sync works

- Sync currently depends on `Chrome`.
- Open your Xiaohongshu favorites page in Chrome first.
- Then return to the app and start sync.
- This is the most stable approach so far and is less likely to trigger platform risk controls than embedded web syncing.

## Install

### Option 1: Install from `.dmg`

1. Open `小红书收藏导航.dmg`
2. Drag `小红书收藏导航.app` into `Applications`
3. If macOS blocks the first launch, right-click and choose `Open`, or allow it in System Settings > Privacy & Security

### Option 2: Run from source

Requirements:

- macOS 15+
- Xcode Command Line Tools
- Swift 6.2

```bash
swift run XHSOrganizerApp
```

## Basic usage

### 1. Sync favorites

1. Open your Xiaohongshu favorites page in Chrome
2. Open the app
3. Click `同步小红书`
4. Click `从当前 Chrome 收藏夹同步`

### 2. Browse

- Left: categories
- Middle: saved list
- Right: article content and images

### 3. Export the current article

Click `下载原文` in the detail pane:

- exports `原文.txt`
- exports `原文链接.txt`
- downloads all images from the current post
- saves everything into `Downloads/小红书收藏导出/`

## Project structure

- `Sources/XHSOrganizerApp`: macOS SwiftUI app
- `Sources/XHSOrganizerCore`: models, import pipeline, classification, search
- `scripts/build_dmg.sh`: package `.app` and `.dmg`
- `scripts/generate_app_icon.py`: generate the app icon

## Build a DMG

```bash
./scripts/build_dmg.sh
```

Outputs:

- `dist/小红书收藏导航.app`
- `dist/小红书收藏导航.dmg`

## Current limitations

- Sync currently relies on Chrome, not Safari or embedded web login.
- Some Xiaohongshu posts are restricted on the web, so original-content extraction depends on link quality and page availability.
- Old items imported with incomplete links may need one more sync pass to improve original-content coverage.
