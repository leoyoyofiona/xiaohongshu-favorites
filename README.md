# 小红书收藏导航

[English](./README.en.md) | [日本語](./README.ja.md)

![小红书收藏导航图标](./Resources/AppIcon-1024.png)

把小红书收藏夹从“越存越乱”变成一个能同步、能分类、能复看的 macOS 桌面工具。

[下载最新版本](https://github.com/leoyoyofiona/xiaohongshu-favorites/releases/latest) | [查看 Release 说明](https://github.com/leoyoyofiona/xiaohongshu-favorites/releases/tag/v0.1.0)

## 为什么做这个

- 收藏越来越多，真正要用的时候翻不到。
- 论文、工具、教程、教育、灵感混在一起，很难复用。
- 小红书原生收藏夹不适合长期整理和桌面端复盘。
- 想保存原文和图片，手动处理很麻烦。

## 主要功能

- 从当前 Chrome 小红书收藏夹同步到 App。
- 自动去重、自动分类，把内容归到主分类。
- 左侧分类导航，中间收藏列表，右侧阅读和导出。
- 支持标记已读、标为重点、上一篇 / 下一篇快速浏览。
- 支持一键下载当前文章原文和全部图片。

## 下载与安装

### 直接安装

1. 打开 [Releases](https://github.com/leoyoyofiona/xiaohongshu-favorites/releases/latest)
2. 下载 `小红书收藏导航.dmg`
3. 双击打开后，把 `小红书收藏导航.app` 拖到 `Applications`
4. 如果 macOS 首次拦截，右键 `打开` 一次即可

### 从源码运行

要求：

- macOS 15+
- Xcode Command Line Tools
- Swift 6.2

```bash
swift run XHSOrganizerApp
```

## 使用方法

### 1. 同步收藏夹

1. 在 Chrome 打开你的小红书收藏夹页面
2. 打开 App
3. 点击 `同步小红书`
4. 点击 `从当前 Chrome 收藏夹同步`

### 2. 浏览与整理

- 左侧：主分类导航
- 中间：收藏列表
- 右侧：正文、图片、重点标记、上一篇 / 下一篇

### 3. 下载当前文章

在右侧详情区域点击 `下载原文`：

- 导出 `原文.txt`
- 导出 `原文链接.txt`
- 下载当前文章全部图片
- 保存到 `下载/小红书收藏导出/`

## 当前方案说明

- 当前同步依赖 Chrome，这是目前最稳的方案。
- 相比 App 内嵌网页同步，这种方式更不容易触发平台风控。
- 旧数据如果是早期同步得到的不完整链接，建议重新同步一次，以提升原文显示比例。

## 项目结构

- `Sources/XHSOrganizerApp`：macOS SwiftUI 界面与桌面端逻辑
- `Sources/XHSOrganizerCore`：数据模型、同步导入、分类、搜索
- `scripts/build_dmg.sh`：打包 `.app` 和 `.dmg`
- `scripts/generate_app_icon.py`：生成 App 图标

## 打包

```bash
./scripts/build_dmg.sh
```

输出：

- `dist/小红书收藏导航.app`
- `dist/小红书收藏导航.dmg`
