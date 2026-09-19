# 飞牛短视频 · 下一轮改造方案

> 写给用户看 / 点头用的方案。不是代码细节，是「改什么、怎么改、改动在哪」。  
> 用户确认后再动手写代码。

---

## 0. 改之前我要先承认

之前那版我把播放逻辑塞进一个独立 `PlayerPage`，从首页 push 过去——这跟你的「打开 App 直接是视频」诉求冲突。这个设计判断是错的，我要改。

另外你说截图里出现了 `ExoPlaybackException Source error, null, null` 和"万花筒画面"——前者是 ExoPlayer 解码失败，后者是渲染异常。**根因大概率是你那些 mp4 里塞了非标准编码（脚本扒下来的常这样）。** 我下面会给方案。

---

## 1. 首页 = 播放器（核心改动）

### 现状
```
LoginPage → HomePage (全黑底) → push PlayerPage
```
你看到的"首页是黑的"就是因为这一段空窗 + push 动画造成的。

### 目标
```
LoginPage → PlayerPage (就是 App 唯一主屏幕)
```
**登录成功后直接进入一个全屏播放器。** 顶部半透明叠 3 个小圆按钮：用户名 / 筛选 / 设置。视频就是内容本身。

### 做法
- **删掉 `home_page.dart` 这个中间层**。`LoginPage._submit` 成功后直接 push 一个**新的** `MainShellPage`（或者改名 `FeedPage`），它内部直接就是 `_FeedPageState extends State<...>` + `PageView`，**整个页面就是抖音式播放器**。
- **顶部三个圆按钮**（用户名/筛选/设置）放右上角/左上角，半透明黑底小圆，点击弹底部抽屉，跟之前一样。
- **短剧/筛选/用户信息/设置**通过 `Navigator.push` 弹新路由，不离开播放器。
- 视频列表的"无限下拉取随机"逻辑保留在 `MainShellPage` 内。

### 影响
- 新文件：保留 `player_page.dart` 作为单个视频渲染单元，但**外部入口改成 `MainShellPage`**。
- `home_page.dart` 删除（保留备份以防你不喜欢）。
- `_FilterScreen` 行为不变：选完筛选项 → `Navigator.pop(filter)` → `MainShellPage` 收到 → 立刻 fetch 第一个 → 重置 list → 跳到第 0 个。

---

## 2. 播放报错：明确报错 + 一键跳过

### 现状
视频加载失败时全屏显示一个"加载失败"页 + 重试按钮。你只有"重试"。

### 目标
错误页同时提供 **重试** 和 **跳过这个视频**。跳过 = 自动调 `_appendRandom()` 跳到下一个。

### 改动
- `_LoadingOrError` 加一个 `onSkip` 回调，按钮文案：
  - 大按钮：**重试**
  - 次按钮：**跳过这个视频**
- `_PlayerPageState` 接收 `onSkip` → 调 `_appendRandom()` → `setState` 切到下一个。
- 错误信息带上视频名 + 错误类型（解码失败 / 网络错误 / 格式不支持），方便你看到底是哪类问题。

### 万花筒画面（专门处理）
万花筒 = 解码器没识别 codec 时的渲染错位。常见是 HEVC/H.265、AV1、奇葩容器。
- **手机端我做兜底**：在 `_VideoEntry.init` 加一个"重试不同解码器"的兜底——首次用 `VideoPlayerController.networkUrl` 失败 → **fallback 用 `VideoPlayerController.file(下载到本地的文件)` 走本地 ExoPlayer**（已经做了）；如果还是失败 → 显示"视频编码格式不支持，可跳过"。
- **不依赖服务端转码**（你说服务端不要改）。如果某个 mp4 真的硬解不了，跳过即可。

---

## 3. 倍速按钮（参考抖音）

### 你要的
- **小圆环**，只显示当前倍速数字（如 `1x`、`2x`、`3x`）
- **点击弹出选项菜单**：`0.5x / 1x / 1.25x / 1.5x / 2x`
- **暂停时显示**，播放时隐藏
- **竖屏和横屏都支持**
- **长按加速**（竖屏）+ 横屏时也是

### 实现细节
- `_CircleAction` 里倍速那个：默认隐藏，**只在 `_showControls` 或 `_pressing` 或暂停时显示**
- 点击弹出 `showModalBottomSheet` 列表，选择后 `controller.setPlaybackSpeed(...)`
- 倍速按钮长按时触发 `_setTempSpeed(2.0)`（保持 2x 长按加速）
- 横屏时位置：右下角小圆环（不是放大版）
- 状态变量：`_playbackSpeed` 当前值；`_controlsVisible` 是否显示控件

### 长按加速：竖屏横屏一致
- `onLongPressStart` → `_setTempSpeed(2.0)` 并显示 2x 提示
- `onLongPressMoveUpdate` → 下滑 80 像素触发"锁定 2x"
- `onLongPressEnd` → 复位 1x

---

## 4. 上下滑不灵敏 — 先诊断后改

### 可能原因（按可能性排序）
1. **预下载全量占带宽**：现在用户进入 N 时我下全量 N，几百 MB 在外网很慢；同步在播 N 又在缓冲 → 抢占带宽导致 PageView 手势响应掉帧
2. **PageView cacheExtent 太大**：默认 250，预渲染上下两页的视频，3 个 video_player 同时跑，CPU 压力大
3. **`pageSnapping` 默认 false**（虽然应该不影响）
4. **video_player 没设置 `mixWithOthers`**：音频焦点冲突 → 卡顿（次要）

### 诊断步骤
我打算在 App 启动时打开"详细日志模式"（DEBUG build 自动开启 / Release 通过点击版本号 7 次打开），记录：
- 每次 `prefetchFull` / `prefetchRange` 启动、取消、完成的时间
- 每次 `_onPageChanged` 触达到 controller 实际 `play()` 的间隔
- 每次 PageView 滑动开始到结束耗时

**装上后你滑几次，把日志截图给我**，我能精确定位。

### 同时改的优化（即使没诊断结果也建议改）
- `cacheExtent: 0.5`（默认 250 太大，限制预渲染区）
- prefetch 全量改为 `prefetchRange`（只下前 3MB），等用户真正在 N+1 上停留够久（≥2s）才升级为全量
- controller 数量上限：最多保 3 个（cur-1 / cur / cur+1），cur+2 时用完即弃

---

## 5. 短剧：抖音式

### 你要的
- 进入短剧后上下滑都是切集（不是锁死下滑）
- 滑到最后一集才退出短剧

### 实现
- `_PlayerPageState._seriesId` 仍然有，但**行为反转**：
  - 下滑（到下一集）：从 `getSeries` 拿 episodeNo+1，插入到 list 末尾
  - 上滑（到上一集）：从 `getSeries` 拿 episodeNo-1，插入到 list 当前位置之前
  - 滑到 seriesCount == episodeNo 时：下次下滑自动调用 `_appendRandom()` 退出短剧 → 拉一个普通视频

### 解决"选第 2 集不切换"
我看了下，应该是 `episode_picker` 的回调链断了——picked 拿到后调用 `onEpisodePicked`，但 pageview 的 `_onEpisodePicked` 用了 `jumpToPage` 跳转但没有 setState 把目标 video 加进 `_entries` 缓存里（虽然 `putIfAbsent` 会自动创建，但 `_resumeIndex` 没更新导致 `resumeProgress` 用错了）。

我修：`_onEpisodePicked` 改成：
```dart
if (idx == _currentIndex) return;
setState(() {
  // 如果 picked 在 _videos 之外，先插入
  if (idx < 0) {
    _videos.insert(_currentIndex + 1, picked);
    idx = _currentIndex + 1;
  }
  _resumeIndex = idx;
});
_controller.jumpToPage(idx);
```

---

## 6. 观看记录：点击回看

### 现状
`/admin/settings_page.dart` 里"观看记录"只展示文字列表。

### 目标
每条记录可点击 → **直接跳到那个视频开始播放**。

### 实现
- 列表用 `ListTile` 替代 `Row`
- `onTap` → 拿 video_id → `api.getVideo(id)` 拿到完整 `VideoItem` → `Navigator.pushReplacement(MainShellPage(videos:[item], initialIndex:0))` 直接进播放
- 长按 → 弹"删除这条记录"选项

---

## 7. 文件改动清单

| 文件 | 改动 |
|------|------|
| `lib/main.dart` | 不变 |
| `lib/pages/login_page.dart` | 不变 |
| `lib/pages/home_page.dart` | **删除**（或留作占位） |
| `lib/pages/main_shell_page.dart` | **新建**：原 HomePage + PlayerPage 合并 |
| `lib/pages/player_page.dart` | **重写**：去掉外层 scaffold，纯粹是一个视频 widget |
| `lib/pages/settings_page.dart` | 观看记录 ListTile + onTap |
| `lib/services/prefetch_manager.dart` | 改：默认 range，进度上报 |

---

## 8. 不在本次范围内

- **服务端转码**：你说 NAS 后端不动，所以不做
- **HEVC/AV1 硬解**：取决于你手机 ExoPlayer 能力；我做兜底（跳过）但不能保证每个 mp4 都能播
- **缓存清理界面**：不在本次范围

---

## 9. 验证

1. 改完后我跑 `flutter analyze` + `flutter test`（手机端所有 9 个测试还要过）
2. `flutter build apk --release` + `adb install -r`
3. 你装上后**实际滑几次**，如果还是不灵敏，把详细日志（已埋点）发我

---

**请你看下哪些要改、哪些不要。点头之后我开始写代码。**
