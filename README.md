# GT听书 (GT Audiobook)

![Flutter](https://img.shields.io/badge/Flutter-3.7-blue) ![Android](https://img.shields.io/badge/Android-11%2B-brightgreen) ![License](https://img.shields.io/badge/License-MIT-green)

**轻量级有声小说播放器** — 无需在线书城、无需账号、无广告。把你下载的有声小说文件放到自己的服务器上，GT听书直接读取播放，支持离线缓存。

## 截图

| 首页 | 播放界面 | 下载管理 |
|------|----------|----------|
| (截图) | (截图) | (截图) |

## 功能特点

- 📚 **书库浏览** — 配置服务器地址后自动扫描有声书目录，按书名列出
- 📖 **章节列表** — 点击书名进入章节目录，支持跳转到任意章节
- ▶️ **智能播放** — 播放/暂停、快进/快退15秒、倍速（1x / 1.25x）
- ⏭️ **连续播放** — 自动播放下一个章节，无缝衔接
- ⏱️ **定时关闭** — 按时间（10~60分钟）或按集数（本集/1~5集）停止
- 📥 **离线缓存** — 提前下载章节，飞机/高铁无网络也能听
- 💾 **播放记忆** — 自动记录每集播放进度，下次打开继续
- 📋 **播放列表** — 正在播放的章节自动居中高亮
- 🌙 **深色模式** — 跟随系统主题，夜间听书不刺眼

## 系统要求

| 项目 | 要求 |
|------|------|
| **操作系统** | Android 11+ (兼容鸿蒙OS) |
| **架构** | arm64-v8a / armeabi-v7a |
| **存储** | 取决于下载缓存量 |
| **网络** | 播放时需访问自建服务器（离线缓存后无需网络） |

## 快速开始

### 1. 部署服务端

需要一台 Web 服务器，按以下目录结构存放有声书文件：

```
你的服务器/
├── 书名1/
│   ├── 第01章.mp3
│   ├── 第02章.mp3
│   └── ...
├── 书名2/
│   ├── 第一章.mp3
│   └── ...
└── ...
```

项目包含极简 PHP API 后端（`audiobook_api/` 目录），部署后返回目录列表和章节信息。

### 2. 安装 App

从 [Releases](https://github.com/tan730/gt_audiobook/releases) 下载最新 APK，或自行编译：

```bash
flutter build apk --release
```

### 3. 配置

首次打开 App 会进入配置页，输入你的服务器地址即可。

## 技术栈

- **框架**: Flutter (Dart)
- **音频引擎**: just_audio (ExoPlayer/Media3)
- **网络请求**: dio
- **本地存储**: shared_preferences
- **后台播放**: audio_service
- **服务端**: PHP (极简 API)

## 编译

```bash
flutter build apk --release
```

编译产物在 `build/app/outputs/flutter-apk/app-release.apk`。

## 许可证

[MIT License](LICENSE)

---

*GT听书 — 自己的有声书，想听就听。*
