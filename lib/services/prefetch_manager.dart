import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 视频预加载管理器
/// - prefetchRange(id, url, token, bytes)：下载前 N 字节到 <id>.cache
/// - prefetchFull(id, url, token)：下载完整文件到 <id>.full
/// - localCachePath(id, {full})：返回本地缓存路径（如不存在返回 null）
/// - cancel(id)：取消进行中的下载
/// - clear()：清空所有缓存
///
/// 文件命名约定（位于应用 cache 目录）：
/// - <id>.partial：正在下载中（断电时残留，下次启动会被覆盖）
/// - <id>.cache：前若干字节的快速首屏缓冲
/// - <id>.full：完整文件
class PrefetchManager {
  PrefetchManager._();
  static final PrefetchManager instance = PrefetchManager._();

  /// 预取字节数（前 3MB ≈ 30 秒到几分钟的视频，取决于码率）
  static const int prefetchBytes = 3 * 1024 * 1024;

  final Map<String, _Task> _tasks = {};

  /// 当前正在执行的任务 id 列表（只读）
  Set<String> activeIds() => _tasks.keys.toSet();

  /// 注入自定义 http.Client（仅用于测试）
  http.Client Function()? _clientFactory;
  void setClientFactory(http.Client Function()? f) {
    _clientFactory = f;
  }

  /// 全量下载：覆盖旧的 partial/cache/full
  Future<void> prefetchFull({
    required String videoId,
    required String url,
    required String? token,
  }) async {
    await _run(videoId, _Spec.full(url: url, token: token));
  }

  /// 字节范围下载（前 N 字节）
  Future<void> prefetchRange({
    required String videoId,
    required String url,
    required String? token,
    required int bytes,
  }) async {
    if (bytes <= 0) return;
    await _run(videoId, _Spec.range(url: url, token: token, bytes: bytes));
  }

  Future<void> _run(String id, _Spec spec) async {
    cancel(id);

    final dir = await _cacheDir();
    final partial = File('${dir.path}/$id.partial');
    final wanted = File('${dir.path}/$id.${spec.suffix}');

    // 已有目标文件 → 直接返回（range/full 都视为可用）
    if (await wanted.exists() && await wanted.length() > 0) {
      return;
    }
    // spec=full 但只有 range(.cache) 文件 → 删除并重新下载
    if (spec.isFull) {
      final cacheFile = File('${dir.path}/$id.cache');
      if (await cacheFile.exists()) {
        try { await cacheFile.delete(); } catch (_) {}
      }
    }
    // 清理旧残留
    if (await wanted.exists()) {
      try { await wanted.delete(); } catch (_) {}
    }
    if (await partial.exists()) {
      try { await partial.delete(); } catch (_) {}
    }

    final client = _clientFactory != null ? _clientFactory!() : http.Client();
    final ctl = Completer<void>();
    _tasks[id] = _Task(client: client, completer: ctl, isFull: spec.isFull);

    final headers = <String, String>{};
    final tok = spec.token;
    if (tok != null && tok.isNotEmpty) {
      headers['Authorization'] = 'Bearer $tok';
    }
    if (!spec.isFull) {
      headers['Range'] = 'bytes=0-${spec.bytes - 1}';
    }

    try {
      final req = http.Request('GET', Uri.parse(spec.url));
      req.headers.addAll(headers);
      final resp = await client.send(req).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        throw HttpException('prefetch failed: ${resp.statusCode}');
      }
      final sink = partial.openWrite();
      try {
        await resp.stream.listen(sink.add,
                onError: sink.addError, cancelOnError: true).asFuture<void>();
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (await partial.exists()) {
        if (await wanted.exists()) await wanted.delete();
        await partial.rename(wanted.path);
      }
      ctl.complete();
    } catch (e) {
      if (await partial.exists()) {
        try { await partial.delete(); } catch (_) {}
      }
      if (!ctl.isCompleted) ctl.completeError(e);
    } finally {
      client.close();
      _tasks.remove(id);
    }
  }

  Future<String?> localCachePath(String videoId, {bool full = false}) async {
    final dir = await _cacheDir();
    final p = File('${dir.path}/$videoId.${full ? "full" : "cache"}');
    if (await p.exists() && await p.length() > 0) return p.path;
    return null;
  }

  Future<bool> hasFull(String videoId) async {
    final dir = await _cacheDir();
    final f = File('${dir.path}/$videoId.full');
    if (!await f.exists()) return false;
    return await f.length() > 0;
  }

  void cancel(String videoId) {
    final t = _tasks.remove(videoId);
    if (t == null) return;
    try { t.client.close(); } catch (_) {}
    if (!t.completer.isCompleted) t.completer.completeError('cancelled');
  }

  void cancelAll() {
    for (final id in _tasks.keys.toList()) {
      cancel(id);
    }
  }

  /// 删除本地缓存文件（.cache + .full）；用于视频被后端删除时
  Future<void> deleteCache(String videoId) async {
    cancel(videoId);
    final dir = await _cacheDir();
    for (final ext in ['cache', 'full']) {
      try {
        final f = File('${dir.path}/$videoId.$ext');
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> clear() async {
    cancelAll();
    final dir = await _cacheDir();
    if (!await dir.exists()) return;
    await for (final f in dir.list()) {
      try { await f.delete(recursive: true); } catch (_) {}
    }
  }

  Future<Directory> _cacheDir() async {
    final base = await getTemporaryDirectory();
    final d = Directory('${base.path}/feiniu_prefetch');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }
}

class _Task {
  _Task({required this.client, required this.completer, required this.isFull});
  final http.Client client;
  final Completer<void> completer;
  final bool isFull;
}

class _Spec {
  _Spec._({
    required this.url,
    required this.token,
    required this.isFull,
    required this.suffix,
    required this.bytes,
  });
  factory _Spec.full({required String url, required String? token}) =>
      _Spec._(url: url, token: token, isFull: true, suffix: 'full', bytes: 0);
  factory _Spec.range({
    required String url, required String? token, required int bytes,
  }) =>
      _Spec._(url: url, token: token, isFull: false, suffix: 'cache', bytes: bytes);

  final String url;
  final String? token;
  final bool isFull;
  final String suffix;
  final int bytes;
}
