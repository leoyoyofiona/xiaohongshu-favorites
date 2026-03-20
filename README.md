# 小红书收藏导航

<p align="center">把越存越乱的小红书收藏夹，整理成一个适合桌面端复看、分类、导出和持续整理的 macOS 工具。</p>

<p align="center"><strong>仅适用于 macOS 15 及以上系统，不支持 Windows / Linux。</strong></p>

<p align="center">
  <a href="https://github.com/leoyoyofiona/xiaohongshu-favorites/releases/latest"><img src="https://img.shields.io/github/v/release/leoyoyofiona/xiaohongshu-favorites?display_name=tag&label=Release" alt="Release" /></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="MIT License" /></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-black?logo=apple" alt="macOS 15+" />
  <img src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white" alt="Swift 6.2" />
</p>

<p align="center">
  <a href="./README.en.md">English</a> · <a href="./README.ja.md">日本語</a>
</p>

<p align="center">
  <img src="./docs/assets/app-overview.png" alt="小红书收藏导航主界面" width="100%" />
</p>

## 为什么值得用

- 收藏越积越多，真正要找时翻不到。
- 论文、教程、工具、灵感混在一起，很难复用。
- 小红书原生收藏夹适合“先存着”，不适合“后面系统整理”。
- 想把原文、图片和重点内容留存下来，手动操作很碎。

## 核心能力

- 从当前 Chrome 打开的小红书收藏夹页同步到本地 App。
- 自动去重、自动主分类，减少收藏夹越堆越乱的问题。
- 三栏桌面布局：左侧分类，中间列表，右侧按接近原文的方式阅读。
- 支持已读、重点、上一篇 / 下一篇、最近同步快速回看。
- 支持一键下载当前文章原文、原链接和全部图片。
- 支持在 App 内直接打开小红书页面，继续浏览和同步。

## 界面预览

### 1. 整体界面

![整体界面](./docs/assets/app-overview.png)

### 2. 同步状态

![同步状态](./docs/assets/app-sync.png)

### 3. 直接查看原文或播放视频

![原文与视频阅读界面](./docs/assets/app-reading.png)

## 安装

### 直接下载

1. 打开 [Releases](https://github.com/leoyoyofiona/xiaohongshu-favorites/releases/latest)
2. 下载 `XHS-Organizer-macOS.dmg`
3. 双击打开后，把 `小红书收藏导航.app` 拖进 `Applications`
4. 如果 macOS 首次拦截，右键 `打开` 一次即可

说明：

- 本软件仅适用于 macOS 15 及以上版本。
- 发布包为 `.dmg`，面向 Mac 用户直接安装使用。

### 从源码运行

要求：

- macOS 15+
- Xcode Command Line Tools
- Swift 6.2

```bash
swift run XHSOrganizerApp
```

## 快速使用

### 1. 同步收藏夹

1. 在 Chrome 打开你的小红书收藏夹页
2. 打开 App
3. 点击 `同步小红书`
4. 点击 `从当前 Chrome 收藏夹同步`

### 2. 浏览与整理

- 左侧：全部收藏、最近同步、已读、重点、主分类
- 中间：当前分类下的收藏列表
- 右侧：按接近原文的方式阅读、切换上一篇 / 下一篇、调整分类

### 3. 导出当前文章

右侧点击 `下载` 后会导出：

- `原文.txt`
- `原文链接.txt`
- 当前文章全部图片

默认保存到 `下载/小红书收藏导出/`

## 当前同步方式

- 当前同步依赖 Chrome，这是现阶段最稳的方案。
- 相比强行全内嵌自动抓取，这种方式更不容易触发平台风控。
- 对于早期导入的不完整旧数据，建议重新同步一次，以提升原文与图片完整度。

## 技术栈

- `SwiftUI + AppKit`：macOS 原生界面
- `WKWebView`：程序内浏览小红书
- `SwiftData / 本地 JSON 存储逻辑`：持久化收藏、状态和分类
- `自定义导入与分类流水线`：同步、去重、重分类、导出

## 项目结构

- `Sources/XHSOrganizerApp`：macOS SwiftUI 界面与桌面逻辑
- `Sources/XHSOrganizerCore`：数据模型、同步导入、分类、搜索、导出
- `scripts/build_dmg.sh`：打包 `.app` 和 `.dmg`
- `scripts/generate_app_icon.py`：生成 App 图标

## 打包

```bash
./scripts/build_dmg.sh
```

输出：

- `dist/小红书收藏导航.app`
- `dist/小红书收藏导航.dmg`

## 许可证

本项目基于 [MIT License](./LICENSE) 开源。
