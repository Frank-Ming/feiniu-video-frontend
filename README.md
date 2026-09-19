# 飞牛短视频 - Flutter 客户端

抖音式 UI，连接 NAS 后端播放本地视频。

## 功能

- 上下滑动切换视频
- 单击暂停 / 播放，显示进度条
- 长按 2x 倍速，松开恢复；长按期间下滑可锁定倍速
- 双指捏合缩放画面（1x ~ 4x）
- 宽屏视频显示「横屏」按钮（旋转整个 App）；竖屏视频隐藏该按钮
- 左下角：视频名 + 路径

## 准备

1. 安装 [Flutter SDK](https://docs.flutter.dev/get-started/install) ≥ 3.22
2. 安装 Android Studio / Android SDK（保证 `flutter doctor` 全绿）
3. 准备一台安卓手机，打开「开发者选项 → USB 调试」并连接到电脑

## 初始化

```bash
cd flutter_app
flutter pub get
```

## 配置后端地址

启动 App 后，进入右上角「设置」页面，填写 NAS 后端地址，例如：

```
http://192.168.1.100:6969
```

点击「测试连接」确认能访问 NAS 上的 FastAPI 服务。

## 真机调试

```bash
# 1. 用 USB 把手机连到电脑，确认手机已开启 USB 调试
adb devices
# 应该能看到类似：
#   XXXXXX   device

# 2. 启动 App
flutter run
```

首次启动会编译 APK 自动安装到手机。

## 打包 APK

```bash
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

## 通过 GitHub Actions 打包（推荐）

Windows 本地首次集成 fvp 会卡死（要编译 libmdk + ffmpeg so 库）。
所以推荐用 GitHub Actions 的 Linux runner 编译：

1. 把本目录推到 GitHub 仓库 `Frank-Ming/feiniu-video-frontend`
2. 推送后自动跑 `.github/workflows/build-apk.yml`
3. 跑完后到 Actions 页面下载 artifact：
   - `apk-release`：完整 APK（约 60MB，包含 fvp 的 libmdk + ffmpeg so）
   - `fvp-native-libs`：只含 so 库的 zip，方便其他项目复用
4. 把下载的 `app-release.apk` 用 `adb install -r` 装到手机即可

首次跑要 10~20 分钟（要下载 ffmpeg 源码并 cmake 编译），跑过之后会增量缓存。

## 常见问题

- **App 里一直转圈「连接后端失败」**：
  1. 确认 NAS 上 `docker compose up -d` 已运行，`curl http://NAS_IP:6969/api/health` 能返回 `{"status":"ok"}`
  2. 确认手机和 NAS 在同一局域网
  3. 飞牛 OS 防火墙需要在「控制面板 → 防火墙」放行 `6969` 端口
- **视频卡顿 / 加载慢**：把 `docker-compose.yml` 里的 `/vol1/1000/视频/H` 改成 SMB 直连路径也可以，详见 README

## 目录结构

```
lib/
├── main.dart                 // 入口
├── models/video_item.dart    // 视频条目模型
├── services/
│   ├── api_service.dart      // 后端 HTTP 客户端
│   └── settings_service.dart // 共享参数（保存后端地址）
├── pages/
│   ├── home_page.dart        // 列表页
│   ├── settings_page.dart    // 设置页
│   └── player_page.dart      // 抖音式播放页（核心）
└── widgets/
    └── dy_progress_bar.dart  // 抖音风格进度条
```
