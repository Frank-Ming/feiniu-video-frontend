/// 飞牛短视频主页面（v6：抖音式）
///
/// 行为：
/// - 登录后直接全屏播放
/// - 顶部右上"三点"菜单：设置 / 用户信息 / 调试日志（连续 7 次切版本号）
/// - 普通模式：pickRandom 只挑 episode_no==1 的剧集（避免刷到中间集）
/// - 短剧模式（进入后）：
///     * 左上"← 返回"按钮退出短剧模式，回到之前视频
///     * 上滑 = 上一集，下滑 = 下一集（始终在 series 内）
///     * 播放到最后一集：弹"已看完"对话框，确认后退出短剧
///     * 选集通过 episode_picker，进入短剧模式
/// - 筛选：选中后立即取一个随机进入；之后所有随机都用这个 filter
/// - 删除视频：三点菜单里有"删除此视频"（仅 can_delete 用户可见）
/// - 物理返回键：series 模式 → 退出 series；横屏 → 退出横屏；竖屏 → "再按一次退出"
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../models/video_item.dart';
import '../services/api_service.dart';
import '../services/debug_log.dart';
import '../services/prefetch_manager.dart';
import '../services/progress_reporter.dart';
import '../theme.dart';
import '../widgets/dy_progress_bar.dart';
import '../widgets/episode_picker.dart';
import 'login_page.dart';
import 'settings_page.dart';
import 'user_profile_page.dart';

class MainShellPage extends StatefulWidget {
  const MainShellPage({
    super.key,
    required this.api,
    required this.username,
    this.initialVideos,
    this.initialIndex = 0,
    this.autoResumeFromHistory,
  });

  final ApiService api;
  final String username;
  final List<VideoItem>? initialVideos;
  final int initialIndex;
  final Map<String, dynamic>? autoResumeFromHistory;

  /// 全局调试开关：设置页可以读写，主页监听
  /// 这样从设置页改完回到主页能即时反映
  static bool globalDebugEnabled = false;

  @override
  State<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends State<MainShellPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final PageController _pageController = PageController();
  late List<VideoItem> _videos;
  int _currentIndex = 0;
  int _resumeIndex = 0;
  bool _bootstrapLoading = true;
  String? _bootstrapErr;

  // 当前的筛选状态（空 = 不筛选）
  VideoFilter? _activeFilter;

  // 短剧模式
  String? _seriesId; // null = 普通模式；非 null = 进入短剧
  // 进入短剧前那条视频（用于"返回"按钮回到原视频）
  VideoItem? _preSeriesVideo;

  // 删除权限
  bool _canDelete = false;

  final Map<int, _VideoEntry> _entries = {};

  // 调试（主页本地调试日志，调试开关状态使用 MainShellPage.globalDebugEnabled）
  bool get _debugEnabled => MainShellPage.globalDebugEnabled;
  final List<String> _debugLogs = [];

  // "再按一次退出"逻辑
  DateTime? _lastBackPress;

  // ---------- 初始化 ----------
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _videos = [];
    if (widget.initialVideos != null && widget.initialVideos!.isNotEmpty) {
      _videos = List.of(widget.initialVideos!);
      _currentIndex = widget.initialIndex.clamp(0, _videos.length - 1);
      _resumeIndex = _currentIndex;
      if (_videos[_currentIndex].isSeries) {
        _seriesId = _videos[_currentIndex].seriesId;
      }
      _bootstrapLoading = false;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _loadUserPermissions();
        if (mounted) _schedulePrefetch();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _bootstrap();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final e in _entries.values) {
      e.flushProgress();
    }
    PrefetchManager.instance.cancelAll();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  // ---------- 启动 ----------
  Future<void> _bootstrap() async {
    setState(() {
      _bootstrapLoading = true;
      _bootstrapErr = null;
    });
    try {
      await _loadUserPermissions();
      VideoItem? entry = await _fetchRandomInitial();
      if (entry == null) {
        setState(() {
          _bootstrapErr = 'NAS 上还没有视频';
          _bootstrapLoading = false;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _videos = [entry];
        _currentIndex = 0;
        _resumeIndex = 0;
        _bootstrapLoading = false;
        // 注意：只对 episode_no==1 才视为"还没选过剧集"，保留为普通模式
      });
      _schedulePrefetch();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bootstrapErr = e.toString();
        _bootstrapLoading = false;
      });
    }
  }

  Future<void> _loadUserPermissions() async {
    try {
      final m = await widget.api.me();
      if (m != null && mounted) {
        setState(() => _canDelete = m['can_delete'] == true);
        _debugLog('can_delete=$_canDelete');
      }
    } catch (_) {}
  }

  /// 取一个初始随机视频（带筛选 / only_first_episode=true）
  Future<VideoItem?> _fetchRandomInitial({List<String>? extraExclude}) async {
    final exclude = <String>[
      ..._videos.map((v) => v.id),
      ...?extraExclude,
    ];
    final r = await widget.api.pickRandom(
      maxSizeMb: 10240,
      exclude: exclude,
      onlyFirstEpisode: true,
    );
    return r;
  }

  // ---------- 调试 ----------
  void _debugLog(String msg) {
    if (!_debugEnabled) return;
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    final line = '$ts $msg';
    _debugLogs.add(line);
    if (_debugLogs.length > 200) _debugLogs.removeAt(0);
    // 同时写到手机本地文件方便排错
    DebugLog.i(msg);
  }

  // ---------- 视频流 ----------
  void _ensureVideoEntry(int index) {
    if (index < 0 || index >= _videos.length) return;
    final v = _videos[index];
    // 占位视频(loading_*) 跳过 init,等待 _appendNext 替换
    if (v.id.startsWith('loading_')) {
      _entries.putIfAbsent(index, () => _VideoEntry(api: widget.api, video: v));
      return;
    }
    _entries.putIfAbsent(index, () {
      final e = _VideoEntry(api: widget.api, video: v);
      e.init(
        onAspectReady: () {
          if (mounted) setState(() {});
          _debugLog('aspect ready #${v.id}');
        },
        onError: () {
          if (mounted) setState(() {});
          _debugLog('init error #${v.id}: ${e.initError}');
          _maybeRequestTranscode(index);
        },
      );
      return e;
    });
  }

  Future<void> _maybeRequestTranscode(int index) async {
    if (index < 0 || index >= _videos.length) return;
    final entry = _entries[index];
    if (entry == null || entry.transcodeRequested) return;
    entry.transcodeRequested = true;
    _debugLog('请求转码 #${_videos[index].id}');
    await widget.api.requestTranscode(_videos[index].id);
    if (mounted) {
      setState(() {});
      _pollTranscode(index);
    }
  }

  Future<void> _pollTranscode(int index) async {
    if (index < 0 || index >= _videos.length) return;
    final vid = _videos[index].id;
    for (int i = 0; i < 60; i++) {
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted) return;
      final res = await widget.api.transcodeStatus(vid);
      if (res == null) continue;
      final hasCache = res['has_cache'] == true;
      final task = res['task'] as Map<String, dynamic>?;
      final status = task?['status'] as String?;
      _debugLog('转码 #$vid: $status has_cache=$hasCache');
      if (mounted) setState(() {});
      if (hasCache) {
        final entry = _entries[index];
        if (entry != null) {
          entry.dispose();
          _entries.remove(index);
        }
        if (mounted) setState(() {});
        _ensureVideoEntry(index);
        return;
      }
      if (status == 'failed') break;
    }
  }

  Future<void> _onPageChanged(int idx) async {
    if (idx < 0 || idx >= _videos.length) return;
    _debugLog('onPageChanged $idx (was $_currentIndex)');
    final prev = _entries[_currentIndex];
    prev?.flushProgress();
    prev?.controller?.pause();
    prev?.controller?.setVolume(0);

    setState(() {
      _currentIndex = idx;
      _resumeIndex = idx;
    });
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    _ensureVideoEntry(idx);
    final c = _entries[idx]?.controller;
    if (c != null) {
      await c.play();
      c.setVolume(1);
    }

    _schedulePrefetch();
  }

  // ---------- 短剧模式 ----------
  /// 进入短剧模式（从 episode_picker 选集后调用）
  /// seriesId: 短剧 id；episodes: 全部集（按集数排序）；startIndex: 默认进入第几集
  Future<void> _enterSeriesMode(String seriesId, List<VideoItem> episodes,
      int startIndex) async {
    if (episodes.isEmpty) return;
    // 记录"进入短剧前"的现场，方便"返回"按钮恢复
    _preSeriesVideo = _videos.isNotEmpty ? _videos[_currentIndex] : null;
    setState(() {
      _seriesId = seriesId;
      _videos = episodes;
      _currentIndex = startIndex.clamp(0, episodes.length - 1);
      _resumeIndex = _currentIndex;
    });
    _debugLog('进入短剧 $seriesId @ ep ${episodes[_currentIndex].episodeNo}');
    _schedulePrefetch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_currentIndex);
      }
    });
  }

  /// 退出短剧模式：回到进入短剧前的视频
  void _exitSeriesMode({bool showSnackBar = true}) {
    if (_seriesId == null) return;
    _debugLog('退出短剧 $_seriesId');
    setState(() {
      _seriesId = null;
    });
    if (showSnackBar && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已退出短剧'), duration: Duration(seconds: 1)),
      );
    }
    if (_preSeriesVideo != null) {
      // 回到进入短剧前的视频：清空列表，只剩 preSeriesVideo
      for (final e in _entries.values) {
        e.dispose();
      }
      _entries.clear();
      PrefetchManager.instance.cancelAll();
      setState(() {
        _videos = [_preSeriesVideo!];
        _currentIndex = 0;
        _resumeIndex = 0;
        _preSeriesVideo = null;
      });
      _schedulePrefetch();
    } else {
      // 没有前置视频（不应当发生），用普通取一个
      _fetchRandomAndAppend();
    }
  }

  /// 下滑切下一集（在短剧模式下）或普通随机（在普通模式下）
  Future<void> _onSwipeDown() async {
    if (_seriesId != null) {
      await _seriesNext();
    } else {
      await _appendRandom();
    }
  }

  /// 上滑切上一集（在短剧模式下），普通模式不响应上滑（保持抖音体验）
  Future<void> _onSwipeUp() async {
    if (_seriesId != null) {
      await _seriesPrev();
    } else {
      _debugLog('普通模式上滑忽略');
    }
  }

  Future<void> _seriesNext() async {
    final cur = _videos[_currentIndex];
    if (!cur.isSeries) return;
    // 已经是最后一集 → 弹"已看完"对话框
    if (cur.episodeNo >= cur.seriesCount) {
      _debugLog('已是最后一集，提示退出短剧');
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.bgCard,
          title: const Text('已看完'),
          content: const Text('这部短剧已经看完，是否退出？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: const Text('继续看其他集')),
            TextButton(onPressed: () => Navigator.pop(context, true),
                child: const Text('退出短剧')),
          ],
        ),
      );
      if (ok == true) {
        _exitSeriesMode();
      }
      return;
    }
    // 列表里还有下一集？
    final nextIdx = _currentIndex + 1;
    if (nextIdx < _videos.length &&
        _videos[nextIdx].isSeries &&
        _videos[nextIdx].episodeNo == cur.episodeNo + 1) {
      _pageController.animateToPage(nextIdx,
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
      return;
    }
    // 否则拉下一集
    try {
      final siblings = await widget.api.getSeries(_seriesId!);
      final nextEp = siblings.firstWhere(
        (e) => e.episodeNo == cur.episodeNo + 1,
        orElse: () => siblings.isNotEmpty ? siblings.last : cur,
      );
      if (nextEp.id != cur.id) {
        if (!mounted) return;
        setState(() => _videos.add(nextEp));
        _schedulePrefetch();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients) {
            _pageController.animateToPage(_videos.length - 1,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut);
          }
        });
      }
    } catch (e) {
      _debugLog('series next 拉取失败: $e');
    }
  }

  Future<void> _seriesPrev() async {
    final cur = _videos[_currentIndex];
    if (!cur.isSeries) return;
    if (cur.episodeNo <= 1) {
      _debugLog('已是第一集，无上一集');
      return;
    }
    final prevIdx = _currentIndex - 1;
    if (prevIdx >= 0 &&
        _videos[prevIdx].isSeries &&
        _videos[prevIdx].episodeNo == cur.episodeNo - 1) {
      _pageController.animateToPage(prevIdx,
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
      return;
    }
    try {
      final siblings = await widget.api.getSeries(_seriesId!);
      final prevEp = siblings.firstWhere(
        (e) => e.episodeNo == cur.episodeNo - 1,
        orElse: () => siblings.isNotEmpty ? siblings.first : cur,
      );
      if (prevEp.id != cur.id) {
        if (!mounted) return;
        setState(() => _videos.add(prevEp));
        _schedulePrefetch();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients) {
            _pageController.jumpToPage(_videos.length - 1);
          }
        });
      }
    } catch (e) {
      _debugLog('series prev 拉取失败: $e');
    }
  }

  // ---------- 普通随机追加 ----------
  Future<void> _appendRandom() async {
    final exclude = _videos.map((v) => v.id).toList();
    VideoItem? next;
    // 如果当前有 filter，用 listVideos(filter: ...) → 随机；否则用 pickRandom
    if (_activeFilter != null && !_activeFilter!.isEmpty) {
      try {
        final list = await widget.api.listVideos(filter: _activeFilter!);
        if (list.isNotEmpty) {
          final pool = list.where((v) => !exclude.contains(v.id)).toList();
          if (pool.isNotEmpty) {
            next = pool[Random().nextInt(pool.length)];
          }
        }
      } catch (e) {
        _debugLog('listVideos(filter) 失败: $e');
      }
    }
    next ??= await widget.api.pickRandom(
      maxSizeMb: 10240,
      exclude: exclude,
      onlyFirstEpisode: true,
    );
    if (next == null || !mounted || _hasId(next.id)) {
      _debugLog('appendRandom 拿不到新视频（可能池子太小）');
      return;
    }
    setState(() => _videos.add(next!));
    _schedulePrefetch();
  }

  bool _hasId(String id) => _videos.any((v) => v.id == id);

  Future<void> _fetchRandomAndAppend() async {
    await _appendRandom();
  }

  // ---------- 预加载 ----------
  void _schedulePrefetch() {
    final cur = _currentIndex;
    final ahead = [cur + 1, cur + 2, cur + 3];
    final behind = cur - 1;

    // 在 series 模式下：当前正在看 + 前后 1 集做全量（因为短剧希望快速切）
    // 普通模式：当前全量 + ahead range + behind range
    final playing = _videos[cur];
    final inSeries = _seriesId != null;

    PrefetchManager.instance.prefetchFull(
      videoId: playing.id,
      url: widget.api.streamUrl(playing.id),
      token: widget.api.token,
    ).catchError((_) {});
    _debugLog('prefetchFull playing #${playing.id} (inSeries=$inSeries)');

    final keep = <String>{playing.id};
    for (final i in ahead) {
      if (i > 0 && i < _videos.length) keep.add(_videos[i].id);
    }
    if (behind >= 0) keep.add(_videos[behind].id);
    final running = PrefetchManager.instance.activeIds();
    for (final id in running) {
      if (!keep.contains(id)) PrefetchManager.instance.cancel(id);
    }

    // ahead range（前 3MB）
    for (final i in ahead) {
      if (i <= 0 || i >= _videos.length) continue;
      if (i == cur) continue;
      final v = _videos[i];
      PrefetchManager.instance.prefetchRange(
        videoId: v.id,
        url: widget.api.streamUrl(v.id),
        token: widget.api.token,
        bytes: PrefetchManager.prefetchBytes,
      ).catchError((_) {});
    }

    // behind range
    if (behind >= 0) {
      final v = _videos[behind];
      PrefetchManager.instance.prefetchRange(
        videoId: v.id,
        url: widget.api.streamUrl(v.id),
        token: widget.api.token,
        bytes: PrefetchManager.prefetchBytes,
      ).catchError((_) {});
    }

    // 列表扩展
    if (!inSeries) {
      for (final aheadIdx in [cur + 1, cur + 2]) {
        if (aheadIdx >= _videos.length - 1) {
          _appendRandom();
          break;
        }
      }
    }
  }

  // ---------- 弹窗 / 设置 ----------
  Future<void> _openFilter() async {
    final result = await Navigator.of(context).push<VideoFilter>(
      MaterialPageRoute(
        builder: (_) => _FilterScreen(
          api: widget.api,
          initial: _activeFilter ?? const VideoFilter(),
        ),
        fullscreenDialog: true,
      ),
    );
    if (result == null || !mounted) return;
    // 应用筛选 + 立即取一个进入
    try {
      List<VideoItem> list = [];
      if (!result.isEmpty) {
        list = await widget.api.listVideos(filter: result);
      } else {
        // 不筛选
        final all = await widget.api.pickRandom(
          maxSizeMb: 10240,
          onlyFirstEpisode: true,
        );
        if (all != null) list = [all];
      }
      if (list.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('筛选范围内没有视频')),
        );
        return;
      }
      final entry = list[Random().nextInt(list.length)];
      if (!mounted) return;
      // 重置播放器到该 entry + 保存 filter
      for (final e in _entries.values) {
        e.dispose();
      }
      _entries.clear();
      PrefetchManager.instance.cancelAll();
      setState(() {
        _videos = [entry];
        _currentIndex = 0;
        _resumeIndex = 0;
        _activeFilter = result.isEmpty ? null : result;
        _seriesId = null;
      });
      _schedulePrefetch();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载失败: $e')),
      );
    }
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SettingsPage(
        api: widget.api,
        username: widget.username,
      ),
    ));
  }

  void _openUserProfile() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => UserProfilePage(api: widget.api, username: widget.username),
    ));
  }

  Future<void> _logout() async {
    try { await widget.api.logout(); } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  // ---------- 三点菜单 ----------
  void _openMoreMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('我的资料'),
              onTap: () { Navigator.pop(ctx); _openUserProfile(); },
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('筛选视频'),
              onTap: () { Navigator.pop(ctx); _openFilter(); },
            ),
            if (_canDelete)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.danger),
                title: const Text('删除当前视频',
                    style: TextStyle(color: AppColors.danger)),
                onTap: () { Navigator.pop(ctx); _confirmDeleteCurrent(); },
              ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('设置'),
              onTap: () { Navigator.pop(ctx); _openSettings(); },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.textTertiary),
              title: const Text('退出登录',
                  style: TextStyle(color: AppColors.textTertiary)),
              onTap: () { Navigator.pop(ctx); _logout(); },
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 删除当前视频 ----------
  Future<void> _confirmDeleteCurrent() async {
    if (_currentIndex < 0 || _currentIndex >= _videos.length) return;
    final vid = _videos[_currentIndex].id;
    final vname = _videos[_currentIndex].name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('删除此视频？'),
        content: Text('「$vname」会被永久删除，无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('删除',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok != true) return;
    _debugLog('删除视频 #$vid');
    final success = await widget.api.deleteVideo(vid);
    if (!mounted) return;
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除失败（无权限或后端错误）')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已删除')),
    );
    // 删除后清理：1. 清本地预加载缓存  2. 从当前 list 移除该项
    // 3. 修正 _currentIndex 防止越界  4. list 空时取一个新随机
    await PrefetchManager.instance.deleteCache(vid);
    if (!mounted) return;
    final removeIdx = _currentIndex;
    setState(() {
      _videos.removeAt(removeIdx);
      if (_currentIndex >= _videos.length) {
        _currentIndex = _videos.length - 1;
      }
      _resumeIndex = _currentIndex.clamp(0, _videos.length - 1);
    });
    // 重建受影响的 _entries（删一条后 index 全部偏移）
    _rebuildEntriesAfterRemove(removeIdx);
    // 强制 pageview 同步到当前 index（可能越界后被 Flutter 拉回去）
    if (_pageController.hasClients && _videos.isNotEmpty) {
      _pageController.jumpToPage(_currentIndex);
    }
    if (_videos.isEmpty) {
      await _appendRandom();
    }
  }

  /// list 移除一项后，重新整理 _entries 索引
  void _rebuildEntriesAfterRemove(int removedIdx) {
    final oldEntries = Map<int, _VideoEntry>.from(_entries);
    _entries.clear();
    // 原 index < removedIdx → 不变；>= removedIdx → 减 1
    oldEntries.forEach((idx, entry) {
      if (idx == removedIdx) {
        entry.dispose();
        return;
      }
      final newIdx = idx > removedIdx ? idx - 1 : idx;
      _entries[newIdx] = entry;
    });
  }

  /// list 在 insertedAt 处插入一项后，把 >= insertedAt 的 entry 索引都 +1
  /// 插入点之后还没创建 entry 的不用动（_ensureVideoEntry 会补上）
  void _rebuildEntriesAfterInsert(int insertedAt) {
    final oldEntries = Map<int, _VideoEntry>.from(_entries);
    _entries.clear();
    oldEntries.forEach((idx, entry) {
      final newIdx = idx >= insertedAt ? idx + 1 : idx;
      _entries[newIdx] = entry;
    });
  }

  /// 用户在错误页点了「跳过」：等效于不等了直接下滑到下一个新视频
  void _skipCurrent() {
    if (_seriesId != null) {
      _seriesNext(); // 短剧里：尝试到下一集
      return;
    }
    _appendNext(); // 普通模式：拿一个新随机视频放在当前 index 后一位
  }

  /// 拉一个新随机视频，插到当前 index 之后，自动滚动到下一个
  /// 优化：先插入占位视频 + 立即滚动（乐观更新），后台异步获取真实视频
  Future<void> _appendNext() async {
    final insertAt = _currentIndex + 1;
    // 1. 先插入占位视频，让 UI 立即跳转（用户感受到秒响应）
    final placeholder = VideoItem(
      id: 'loading_${DateTime.now().microsecondsSinceEpoch}',
      name: '加载中...',
      path: '',
      fullPath: '',
      size: 0,
      mtime: 0,
      dir: '',
    );
    if (!mounted) return;
    setState(() {
      _videos.insert(insertAt, placeholder);
      _currentIndex = insertAt;
      _resumeIndex = insertAt;
    });
    _rebuildEntriesAfterInsert(insertAt);
    if (_pageController.hasClients) {
      _pageController.jumpToPage(insertAt);
    }
    // 2. 后台异步获取真实视频
    VideoItem? next;
    final exclude = _videos
        .where((v) => !v.id.startsWith('loading_'))
        .map((v) => v.id)
        .toList();
    try {
      if (_activeFilter != null && !_activeFilter!.isEmpty) {
        try {
          final list = await widget.api.listVideos(filter: _activeFilter!);
          if (list.isNotEmpty) {
            final pool =
                list.where((v) => !exclude.contains(v.id)).toList();
            if (pool.isNotEmpty) {
              next = pool[Random().nextInt(pool.length)];
            }
          }
        } catch (e) {
          _debugLog('listVideos(filter) 失败: $e');
        }
      }
      next ??= await widget.api.pickRandom(
        maxSizeMb: 10240,
        exclude: exclude,
        onlyFirstEpisode: true,
      );
    } catch (e) {
      _debugLog('pickRandom 失败: $e');
    }
    if (!mounted) return;
    if (next == null || _hasId(next.id)) {
      _debugLog('skip 拿不到新视频（可能池子太小）');
      // 移除占位
      final phIdx = _videos.indexWhere((v) => v.id == placeholder.id);
      if (phIdx >= 0) {
        setState(() => _videos.removeAt(phIdx));
        _rebuildEntriesAfterRemove(phIdx);
        if (_currentIndex >= _videos.length) {
          _currentIndex = _videos.length - 1;
          if (_pageController.hasClients) {
            _pageController.jumpToPage(_currentIndex);
          }
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有更多视频了，点 ❌ 删掉一些试试')),
      );
      return;
    }
    // 3. 用真实视频替换占位
    final phIdx = _videos.indexWhere((v) => v.id == placeholder.id);
    if (phIdx < 0) return; // 用户已经滑走
    setState(() {
      _videos[phIdx] = next!;
    });
    _rebuildEntriesAfterInsert(phIdx + 1);
    _schedulePrefetch();
  }

  // ---------- 选集 ----------
  Future<void> _onEpisodePicked(VideoItem picked) async {
    // 如果当前已经在 series 模式，且选的就是同一 series
    if (_seriesId != null && picked.seriesId == _seriesId) {
      final idx = _videos.indexWhere((v) => v.id == picked.id);
      if (idx >= 0) {
        _pageController.animateToPage(idx,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut);
        return;
      }
    }
    // 新进 series 模式
    try {
      final episodes = await widget.api.getSeries(picked.seriesId);
      if (episodes.isEmpty || !mounted) return;
      final startIdx = episodes.indexWhere((v) => v.id == picked.id)
          .clamp(0, episodes.length - 1);
      await _enterSeriesMode(picked.seriesId, episodes, startIdx);
    } catch (e) {
      _debugLog('episode picker 失败: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载剧集失败: $e')),
      );
    }
  }

  // ---------- 返回键 ----------
  Future<bool> _handleBack() async {
    // 1. series 模式 → 退出 series
    if (_seriesId != null) {
      _exitSeriesMode();
      return false; // 不退出 App
    }
    // 2. 横屏 → 退出横屏
    if (MediaQuery.of(context).orientation == Orientation.landscape) {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      return false;
    }
    // 3. 竖屏非 series → "再按一次退出"
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      // 2 秒内再按一次 → 真退出
      return true;
    }
    _lastBackPress = now;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('再按一次退出'),
        duration: Duration(seconds: 2),
      ),
    );
    return false;
  }

  // ---------- 渲染 ----------
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldExit = await _handleBack();
        if (shouldExit && mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (_bootstrapLoading)
              const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            else if (_bootstrapErr != null)
              _BootstrapErrorView(
                err: _bootstrapErr!,
                onRetry: _bootstrap,
                onLogout: _logout,
              )
            else
              _buildPageView(),

            // 顶部叠加：series 返回按钮 / 三个点菜单
            if (!_bootstrapLoading && _bootstrapErr == null)
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: _buildTopBar(),
                ),
              ),

            // 调试日志浮窗
            if (_debugEnabled && _debugLogs.isNotEmpty)
              Positioned(
                left: 8, right: 8, bottom: 8,
                child: _DebugPanel(
                  logs: List.of(_debugLogs.reversed.take(8)),
                  onClose: () => setState(() {
                    MainShellPage.globalDebugEnabled = false;
                    _debugLogs.clear();
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageView() {
    return NotificationListener<ScrollNotification>(
      // 不做任何事，仅用于诊断
      child: PageView.builder(
        // 用 _videos 的 hashCode 作为 key,列表/filter 改变时强制重建
        // 否则 Flutter 会复用旧 _FeedItem 导致 controller 状态错乱甚至闪退
        key: ValueKey('pageview_${_videos.length}_${_videos.isEmpty ? 0 : _videos[0].id}'),
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _videos.length,
        onPageChanged: _onPageChanged,
        pageSnapping: true,
        physics: const PageScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        itemBuilder: (ctx, i) {
          _ensureVideoEntry(i);
          return _FeedItem(
            entry: _entries[i]!,
            isActive: i == _currentIndex,
            video: _videos[i],
            inSeriesMode: _seriesId != null,
            onEpisodePicked: _onEpisodePicked,
            onSkip: _skipCurrent,
            onReportPlayError: (msg) => _debugLog('play error: $msg'),
            onSwipeDown: _onSwipeDown,
            onSwipeUp: _onSwipeUp,
            resumeProgress: i == _resumeIndex
                ? widget.autoResumeFromHistory : null,
          );
        },
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        // series 模式下显示"返回"按钮
        if (_seriesId != null)
          _GlassCircle(
            icon: Icons.arrow_back,
            onTap: () => _exitSeriesMode(),
          ),
        if (_seriesId != null) const SizedBox(width: 8),
        // 用户名 pill（始终显示）
        _GlassPill(
          icon: Icons.person_outline,
          text: widget.username,
          onTap: _openUserProfile,
        ),
        const Spacer(),
        // 三个点菜单（设置/退出登录/调试模式入口）
        _GlassCircle(
          icon: Icons.more_horiz,
          onTap: _openMoreMenu,
        ),
        // DEBUG 模式下显示一个标记，方便排查（不是版本号）
        if (_debugEnabled) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'DEBUG',
              style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================
// UI 组件
// ============================================================
class _GlassPill extends StatelessWidget {
  const _GlassPill({
    required this.icon, required this.text, this.onTap,
  });
  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.textPrimary, size: 16),
              const SizedBox(width: 6),
              Text(text, style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassCircle extends StatelessWidget {
  const _GlassCircle({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(side: BorderSide(color: Colors.white24)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.more_horiz, color: AppColors.textPrimary, size: 20),
        ),
      ),
    );
  }
}

class _DebugPanel extends StatelessWidget {
  const _DebugPanel({required this.logs, required this.onClose});
  final List<String> logs;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.bug_report, color: Colors.greenAccent, size: 14),
              const SizedBox(width: 4),
              const Text('DEBUG', style: TextStyle(color: Colors.greenAccent, fontSize: 11)),
              const Spacer(),
              GestureDetector(
                onTap: onClose,
                child: const Icon(Icons.close, color: Colors.white54, size: 14),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 4),
          Expanded(
            child: SingleChildScrollView(
              reverse: true,
              child: SelectableText(
                logs.join('\n'),
                style: const TextStyle(
                  color: Colors.greenAccent, fontSize: 10,
                  fontFamily: 'monospace', height: 1.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BootstrapErrorView extends StatelessWidget {
  const _BootstrapErrorView({
    required this.err, required this.onRetry, required this.onLogout,
  });
  final String err;
  final VoidCallback onRetry;
  final VoidCallback onLogout;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: AppColors.textTertiary, size: 56),
            const SizedBox(height: 16),
            Text('启动失败\n$err', textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh), label: const Text('重试'),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onLogout, child: const Text('退出登录')),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 单视频渲染单元
// ============================================================
class _VideoEntry {
  _VideoEntry({required this.api, required this.video});
  final ApiService api;
  final VideoItem video;

  VideoPlayerController? controller;
  bool initialized = false;
  double aspectRatio = 9 / 16;
  String? initError;
  bool transcodeRequested = false;

  ProgressReporter? _reporter;
  Duration _lastPosForFlush = Duration.zero;
  Timer? _ticker;

  Future<void> init({
    required VoidCallback onAspectReady,
    VoidCallback? onError,
  }) async {
    String? localPath = await PrefetchManager.instance.localCachePath(
      video.id, full: true,
    );
    localPath ??= await PrefetchManager.instance.localCachePath(
      video.id, full: false,
    );
    VideoPlayerController c;
    if (localPath != null) {
      c = VideoPlayerController.file(File(localPath));
    } else {
      c = VideoPlayerController.networkUrl(Uri.parse(api.streamUrl(video.id)));
    }
    controller = c;

    try {
      await c.initialize().timeout(const Duration(seconds: 15));
      initialized = true;
      aspectRatio = c.value.aspectRatio == 0 ? 9 / 16 : c.value.aspectRatio;
      c.setLooping(true);
      _reporter = ProgressReporter(api, video.id, 0);

      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!initialized) return;
        final pos = c.value.position;
        final dur = c.value.duration;
        final ms = dur.inMilliseconds;
        if (ms <= 0) return;
        final sec = pos.inMilliseconds / 1000.0;
        _reporter!.duration = ms / 1000.0;
        _reporter!.report(sec);
        _lastPosForFlush = pos;
      });

      await c.play();
      onAspectReady();
    } catch (e) {
      initError = e.toString();
      if (onError != null) onError();
    }
    if (video.duration == null) {
      api.probeDuration(video.id);
    }
  }

  void flushProgress() {
    if (_reporter == null || controller == null) return;
    final ms = controller!.value.duration.inMilliseconds;
    if (ms <= 0) return;
    _reporter!.duration = ms / 1000.0;
    _reporter!.flush(_lastPosForFlush.inMilliseconds / 1000.0);
  }

  void dispose() {
    _ticker?.cancel();
    flushProgress();
    controller?.dispose();
    controller = null;
  }
}

class _FeedItem extends StatefulWidget {
  const _FeedItem({
    required this.entry,
    required this.isActive,
    required this.video,
    required this.inSeriesMode,
    required this.onEpisodePicked,
    required this.onSkip,
    required this.onReportPlayError,
    required this.onSwipeDown,
    required this.onSwipeUp,
    this.resumeProgress,
  });

  final _VideoEntry entry;
  final bool isActive;
  final VideoItem video;
  final bool inSeriesMode;
  final ValueChanged<VideoItem> onEpisodePicked;
  final VoidCallback onSkip;
  final ValueChanged<String> onReportPlayError;
  final VoidCallback onSwipeDown;
  final VoidCallback onSwipeUp;
  final Map<String, dynamic>? resumeProgress;

  @override
  State<_FeedItem> createState() => _FeedItemState();
}

class _FeedItemState extends State<_FeedItem> {
  Timer? _progressHideTimer;
  bool _showControls = false;

  bool _pressing = false;
  double _pressDy = 0.0;

  double _scale = 1.0;
  double _baseScale = 1.0;
  double _currentSpeed = 1.0;

  bool _resumed = false;

  List<VideoItem>? _seriesEpisodes;

  @override
  void dispose() {
    _progressHideTimer?.cancel();
    super.dispose();
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    _progressHideTimer?.cancel();
    if (_showControls) {
      _progressHideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showControls = false);
      });
    }
  }

  void _onTap() {
    final c = widget.entry.controller;
    if (c == null || !widget.entry.initialized) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
    _toggleControls();
  }

  void _onLongPressStart(LongPressStartDetails d) {
    _pressing = true;
    _pressDy = 0;
    _setTempSpeed(2.0);
    setState(() {});
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails d) {
    if (!_pressing) return;
    _pressDy = d.offsetFromOrigin.dy;
    if (_pressDy > 80) {
      _pressing = false;
      _setTempSpeed(2.0);
      setState(() => _currentSpeed = 2.0);
    }
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    if (!_pressing) return;
    _setTempSpeed(1.0);
    _pressing = false;
    setState(() {});
  }

  void _setTempSpeed(double s) {
    _currentSpeed = s;
    final c = widget.entry.controller;
    if (c != null && widget.entry.initialized) {
      c.setPlaybackSpeed(s);
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    _baseScale = _scale;
    if (d.pointerCount >= 2) _showControls = false;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount >= 2) {
      final newScale = (_baseScale * d.scale).clamp(1.0, 4.0);
      setState(() => _scale = newScale);
    }
  }

  String _fmtTime(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$m:$s';
    return '$m:$s';
  }

  void _maybeResume() {
    if (_resumed) return;
    final c = widget.entry.controller;
    final p = widget.resumeProgress;
    if (c == null || !widget.entry.initialized) return;
    if (p == null || p.isEmpty) return;
    final pos = (p['position'] as num?)?.toDouble() ?? 0;
    final dur = (p['duration'] as num?)?.toDouble() ?? 0;
    if (pos <= 0 || dur <= 0) return;
    if (pos / dur >= 0.95) return;
    _resumed = true;
    Future.delayed(const Duration(milliseconds: 400), () async {
      await c.seekTo(Duration(milliseconds: (pos * 1000).toInt()));
      await c.play();
    });
  }

  Future<void> _openEpisodePicker() async {
    final video = widget.video;
    if (!video.isSeries) return;
    _seriesEpisodes ??= await widget.entry.api.getSeries(video.seriesId);
    if (!mounted) return;
    final picked = await showEpisodePicker(
        context, _seriesEpisodes!, video.id);
    if (picked != null && picked.id != video.id) {
      widget.onEpisodePicked(picked);
    }
  }

  Future<void> _toggleLandscape() async {
    if (MediaQuery.of(context).orientation == Orientation.landscape) {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  Future<void> _showSpeedSheet() async {
    final options = [
      ('0.5x', 0.5),
      ('1x', 1.0),
      ('1.25x', 1.25),
      ('1.5x', 1.5),
      ('2x', 2.0),
    ];
    final picked = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('播放速度',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            for (final opt in options)
              ListTile(
                title: Text(opt.$1),
                trailing: _currentSpeed == opt.$2
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, opt.$2),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) {
      _setTempSpeed(picked);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final video = widget.video;

    if (widget.isActive && entry.initialized && !_resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeResume());
    }

    return OrientationBuilder(
      builder: (ctx, orientation) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTap,
          onLongPressStart: _onLongPressStart,
          onLongPressMoveUpdate: _onLongPressMoveUpdate,
          onLongPressEnd: _onLongPressEnd,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Transform.scale(
              scale: _scale,
              child: _buildVideo(entry),
            ),
          ),
          // 顶部 + 底部渐变蒙版
          IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black54,
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black87,
                  ],
                  stops: [0.0, 0.15, 0.7, 1.0],
                ),
              ),
            ),
          ),
          // 左下：视频名 + 路径 / 短剧徽章
          Positioned(
            left: 16, bottom: 28, right: 80,
            child: _buildInfo(video),
          ),
          // 全屏按钮：仅当视频是横屏比例 (>1) 时显示,
          // 放在视频下方约 50px 居中。
          // 视频比例 = 视频宽/视频高;>1 表示视频本身是横屏内容(电影/横屏短剧)
          // 不依赖手机物理方向,只依赖视频内容
          if (widget.entry.aspectRatio > 1.0)
            _buildLandscapeExitButton(context),
          // 倍速按钮：进度条上方右下，跟进度条一同出现/消失
          if (_showControls)
            Positioned(
              left: 0, right: 12, bottom: 80,
              child: Align(
                alignment: Alignment.bottomRight,
                child: _buildSpeedButton(),
              ),
            ),
          if (_pressing) const Center(child: _PressHint()),
          if (_showControls && widget.isActive)
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: _buildProgressBar(),
            ),
          if (widget.isActive)
            _LoadingOrError(
              entry: entry,
              onSkip: widget.onSkip,
              onReportPlayError: widget.onReportPlayError,
            ),
        ],
      ),
        );
      },
    );
  }

  Widget _buildSpeedButton() {
    return GestureDetector(
      onTap: _showSpeedSheet,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Center(
          child: Text(
            _currentSpeed == 1.0 ? '1x' : '${_currentSpeed}x',
            style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideo(_VideoEntry entry) {
    if (entry.controller == null || !entry.initialized) {
      // 占位视频 (loading_*) 时显示加载圈,避免黑屏
      if (widget.video.id.startsWith('loading_')) {
        return const ColoredBox(
          color: Colors.black,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 16),
                Text('加载下一个视频...',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
        );
      }
      return const ColoredBox(color: Colors.black);
    }
    return AspectRatio(
      aspectRatio: entry.aspectRatio == 0 ? 9 / 16 : entry.aspectRatio,
      child: VideoPlayer(entry.controller!),
    );
  }

  /// 横屏下"退出全屏"按钮:长条 pill,放在视频画面下方约 50px 水平居中
  /// 视频宽度 = MediaQuery 宽;视频高度 = 宽 / 长宽比;视频在 Stack 中垂直居中,
  /// 所以从屏幕底部往上 bottom = (屏高 - 视频高)/2 - 50
  Widget _buildLandscapeExitButton(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final aspect = widget.entry.aspectRatio == 0
        ? 16 / 9
        : widget.entry.aspectRatio;
    // 横屏时强制按宽屏(>=1)来计算视频高度,避免竖屏视频进来撑爆
    final effectiveAspect = aspect < 1.0 ? 1.0 / aspect : aspect;
    final videoH = size.width / effectiveAspect;
    final gapBelowVideo = (size.height - videoH) / 2; // 视频下方留白
    // 如果视频比屏幕还高(竖屏视频横屏显示),视频会铺满全屏,
    // 此时 gap < 0,按钮 bottom 强制放在屏幕下方 30px,确保可见
    double bottom;
    if (gapBelowVideo < 60) {
      bottom = 30; // 视频铺满,按钮放底部
    } else {
      bottom = (gapBelowVideo - 50).clamp(8.0, size.height / 2);
    }
    return Positioned(
      left: 0, right: 0,
      bottom: bottom,
      child: Center(
        child: Semantics(
          button: true,
          label: '退出全屏',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleLandscape,
            child: Container(
              width: 140, height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.4), width: 1),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.fullscreen_exit,
                      color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('退出全屏',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfo(VideoItem video) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (video.isSeries)
              GestureDetector(
                onTap: _openEpisodePicker,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientBrand,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '第 ${video.episodeNo} 集 / 共 ${video.seriesCount} 集',
                    style: const TextStyle(
                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            Flexible(
              child: Text(
                video.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          video.path,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white70, fontSize: 12,
            shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    final c = widget.entry.controller;
    if (c == null || !widget.entry.initialized) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.6),
          ],
        ),
      ),
      child: DyProgressBar(
        current: c.value.position,
        total: c.value.duration,
        buffered: c.value.buffered.isNotEmpty
            ? c.value.buffered.last.end
            : Duration.zero,
        onSeek: (d) async {
          await c.seekTo(d);
          await c.play();
        },
        timeText:
            '${_fmtTime(c.value.position)} / ${_fmtTime(c.value.duration)}',
      ),
    );
  }
}

// ---------- 加载/错误/转码 ----------
class _LoadingOrError extends StatelessWidget {
  const _LoadingOrError({
    required this.entry,
    required this.onSkip,
    required this.onReportPlayError,
  });

  final _VideoEntry entry;
  final VoidCallback onSkip;
  final ValueChanged<String> onReportPlayError;

  @override
  Widget build(BuildContext context) {
    if (entry.controller != null && entry.initialized) {
      return const SizedBox.shrink();
    }
    if (entry.controller == null && entry.initError == null) {
      return const Positioned.fill(
        child: ColoredBox(color: Colors.black),
      );
    }
    if (entry.initError == null) {
      return const Positioned.fill(
        child: ColoredBox(
          color: Colors.black87,
          child: Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
      );
    }
    onReportPlayError(entry.initError!);
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.75),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (entry.transcodeRequested) ...[
                  const Icon(Icons.hourglass_top, color: Colors.white, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    '正在转码兼容格式...',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '首次播放此格式，NAS 端转码中（1~3 分钟）',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                ] else ...[
                  const Icon(Icons.cloud_off, color: Colors.white70, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    '加载失败',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    entry.initError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 20),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        entry.controller?.dispose();
                        entry.controller = null;
                        entry.initialized = false;
                        entry.initError = null;
                        entry.transcodeRequested = false;
                        entry.init(
                          onAspectReady: () {},
                          onError: () {},
                        );
                      },
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('重试'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: onSkip, // 直接调切下一个
                      icon: const Icon(Icons.skip_next, size: 18),
                      label: const Text('跳过'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PressHint extends StatelessWidget {
  const _PressHint();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text('长按 2x 倍速中',
          style: TextStyle(color: Colors.white, fontSize: 14)),
    );
  }
}

// ============================================================
// 筛选
// ============================================================
class _FilterScreen extends StatefulWidget {
  const _FilterScreen({required this.api, required this.initial});
  final ApiService api;
  final VideoFilter initial;
  @override
  State<_FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<_FilterScreen> {
  VideoFilter _filter = const VideoFilter();
  List<DirInfo> _dirs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _filter = widget.initial;
    _load();
  }

  Future<void> _load() async {
    try {
      _dirs = await widget.api.listDirs();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('筛选')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _FilterBody(
              dirs: _dirs,
              filter: _filter,
              onApply: (f) => Navigator.pop(context, f),
            ),
    );
  }
}

class _FilterBody extends StatefulWidget {
  const _FilterBody({
    required this.dirs,
    required this.filter,
    required this.onApply,
  });
  final List<DirInfo> dirs;
  final VideoFilter filter;
  final ValueChanged<VideoFilter> onApply;

  @override
  State<_FilterBody> createState() => _FilterBodyState();
}

class _FilterBodyState extends State<_FilterBody> {
  late Set<String> _selectedDirs;
  String? _preset;
  late double? _minSec;
  late double? _maxSec;

  static const Map<String, String> _presetLabels = {
    'all': '不限',
    'short': '< 1 分钟（短视频）',
    'mid': '< 10 分钟',
    'long10': '> 10 分钟',
    'long30': '> 30 分钟',
    'custom': '自定义',
  };

  static const Map<String, ({double? min, double? max})> _presets = {
    'all': (min: null, max: null),
    'short': (min: null, max: 60),
    'mid': (min: null, max: 600),
    'long10': (min: 600, max: null),
    'long30': (min: 1800, max: null),
    'custom': (min: null, max: null),
  };

  @override
  void initState() {
    super.initState();
    _selectedDirs = {...widget.filter.selectedDirs};
    _minSec = widget.filter.minSeconds;
    _maxSec = widget.filter.maxSeconds;
    _preset = _matchPreset(_minSec, _maxSec);
  }

  String? _matchPreset(double? mn, double? mx) {
    for (final e in _presets.entries) {
      if (e.value.min == mn && e.value.max == mx) return e.key;
    }
    if (mn != null || mx != null) return 'custom';
    return 'all';
  }

  void _applyPreset(String key) {
    final p = _presets[key]!;
    setState(() {
      _preset = key;
      _minSec = p.min;
      _maxSec = p.max;
    });
  }

  void _onMinChanged(double v) {
    setState(() {
      _minSec = v == 0 ? null : v;
      _preset = _matchPreset(_minSec, _maxSec);
    });
  }

  void _onMaxChanged(double v) {
    setState(() {
      _maxSec = v == 0 ? null : v;
      _preset = _matchPreset(_minSec, _maxSec);
    });
  }

  void _reset() {
    setState(() {
      _selectedDirs.clear();
      _preset = 'all';
      _minSec = null;
      _maxSec = null;
    });
  }

  void _confirm() {
    widget.onApply(VideoFilter(
      selectedDirs: _selectedDirs,
      minSeconds: _minSec,
      maxSeconds: _maxSec,
    ));
  }

  String _fmtSec(double? s) {
    if (s == null) return '不限';
    if (s < 60) return '${s.toInt()} 秒';
    if (s < 3600) return '${(s / 60).toStringAsFixed(0)} 分钟';
    return '${(s / 3600).toStringAsFixed(1)} 小时';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('筛选视频',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            const Text('子文件夹（多选）',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 6),
            SizedBox(
              height: 120,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8, runSpacing: 6,
                  children: widget.dirs.map((d) {
                    final sel = _selectedDirs.contains(d.name);
                    return FilterChip(
                      label: Text('${d.name} (${d.count})'),
                      selected: sel,
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _selectedDirs.add(d.name);
                          } else {
                            _selectedDirs.remove(d.name);
                          }
                        });
                      },
                      selectedColor: const Color(0xFFFF2C55),
                      backgroundColor: Colors.white12,
                      labelStyle: TextStyle(
                        color: sel ? Colors.white : Colors.white70,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('时长',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8, runSpacing: 6,
              children: _presetLabels.entries.map((e) {
                final sel = _preset == e.key;
                return ChoiceChip(
                  label: Text(e.value),
                  selected: sel,
                  onSelected: (_) => _applyPreset(e.key),
                  selectedColor: const Color(0xFFFF2C55),
                  backgroundColor: Colors.white12,
                  labelStyle: TextStyle(color: sel ? Colors.white : Colors.white70),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            if (_preset == 'custom') ...[
              _SliderRow(
                label: '最短 (${_fmtSec(_minSec)})',
                value: _minSec ?? 0,
                max: 3600,
                onChanged: _onMinChanged,
              ),
              _SliderRow(
                label: '最长 (${_fmtSec(_maxSec)})',
                value: _maxSec ?? 0,
                max: 3600,
                onChanged: _onMaxChanged,
              ),
            ],
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _reset,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('重置'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF2C55),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('应用'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label, required this.value, required this.max,
    required this.onChanged,
  });
  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0, max),
            min: 0, max: max, divisions: 60,
            activeColor: const Color(0xFFFF2C55),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
