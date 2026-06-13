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

需要一个 **Nginx** 或 **Apache** 服务器（支持 PHP 即可）。

#### 目录结构

将 `audiobook_api/api.php` 放到有声书根目录，按以下结构组织：

```
服务器目录/
├── api.php                 ← 放入本项目提供的 api.php
├── 三体/
│   ├── 第01章.mp3
│   ├── 第02章.mp3
│   ├── 第03章.mp3
│   ├── cover.jpg           ← 封面图片（可选，显示在书库列表）
│   └── ...
├── 鬼吹灯/
│   ├── 001.mp3
│   ├── 002.mp3
│   ├── 003.mp3
│   ├── folder.jpg          ← 封面图片（可选）
│   └── ...
└── ...
```

**支持的音频格式**: `mp3`、`m4a`、`ogg`、`wav`、`aac`、`flac`

**封面图片**: 支持 `cover.jpg`、`cover.png`、`cover.jpeg`、`folder.jpg`

#### Nginx 配置示例

```nginx
server {
    listen 80;
    server_name your-domain.com;

    root /path/to/audiobooks;
    index index.php;

    # PHP 解析
    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    # 允许直接访问音频文件
    location ~* \.(mp3|m4a|ogg|wav|aac|flac)$ {
        add_header Accept-Ranges bytes;
    }
}
```

#### 验证部署

浏览器访问以下地址测试：

- `http://你的服务器地址/api.php?action=books` → 应返回 JSON 书单
- `http://你的服务器地址/api.php?action=chapters&book=三体` → 应返回章节列表

### 2. 安装 App

从 [Releases](https://github.com/tan730/gt_audiobook/releases) 下载最新 APK 安装到 Android 11+ 设备。

或自行编译：
```bash
flutter build apk --release
```

### 3. App 配置

首次打开 App 会进入**服务器配置页**。

输入你的服务器地址，例如：
- `http://192.168.1.100`（内网）
- `http://your-domain.com`（公网）

> **注意**: 公网访问请配置 HTTPS，Android 9+ 默认禁止明文 HTTP 请求。可在 `android/app/src/main/AndroidManifest.xml` 中配置 `android:usesCleartextTraffic="true"` 以允许 HTTP。

### API 接口说明

| 接口 | 参数 | 返回 |
|------|------|------|
| `?action=books` | 无 | 书单数组，含书名和封面路径 |
| `?action=chapters&book=书名` | `book`=书名 | 章节数组，含文件名、排序键、URL |

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
