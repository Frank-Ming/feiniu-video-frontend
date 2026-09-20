import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/video_item.dart';

/// 后端 API 客户端
class ApiService {
  ApiService({String? baseUrl, this.token}) : _baseUrl = baseUrl ?? _defaultBaseUrl();

  final String _baseUrl;
  String? token;

  static String _defaultBaseUrl() {
    return 'http://192.168.1.100:6969';
  }

  String get baseUrl => _baseUrl;

  void setToken(String? t) { token = t; }

  /// 拉取后端版本信息(用于显示在设置页)
  Future<Map<String, dynamic>> getVersion() async {
    final r = await http.get(_uri('/api/version', null), headers: _headers());
    if (r.statusCode != 200) {
      throw Exception('获取版本失败: ${r.statusCode}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// 后端健康检查(用于启动时挑选可达 endpoint)
  Future<bool> ping() async {
    try {
      final r = await http
          .get(_uri('/api/health'))
          .timeout(const Duration(seconds: 4));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Map<String, String> _headers() {
    final h = <String, String>{};
    if (token != null && token!.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  Uri _uri(String path, [Map<String, dynamic>? params]) {
    final base = Uri.parse(_baseUrl);
    return base.replace(
      path: path,
      queryParameters: params?.map((k, v) => MapEntry(k, '$v')),
    );
  }

  /// 详细诊断：返回带详细异常信息的字符串，便于排查网络问题
  Future<String> debugPing() async {
    final url = _uri('/api/health').toString();
    final info = StringBuffer()
      ..writeln('endpoint: $url')
      ..writeln('baseUrl: $_baseUrl')
      ..writeln('host: ${Uri.parse(_baseUrl).host}');
    try {
      final r = await http
          .get(_uri('/api/health'))
          .timeout(const Duration(seconds: 6));
      info.writeln('status: ${r.statusCode}');
      info.writeln('body: ${r.body.length > 200 ? "${r.body.substring(0, 200)}..." : r.body}');
    } catch (e, st) {
      info.writeln('exception: ${e.runtimeType}: $e');
      info.writeln('stack: ${st.toString().split("\n").take(3).join(" | ")}');
    }
    return info.toString();
  }

  // ---- 账号 ----
  Future<Map<String, dynamic>> login(String username, String password) async {
    final r = await http.post(
      _uri('/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (r.statusCode != 200) {
      final msg = _extractMsg(r.body);
      throw Exception(msg ?? '登录失败 (${r.statusCode})');
    }
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> register(String username, String password) async {
    final r = await http.post(
      _uri('/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (r.statusCode != 200) {
      final msg = _extractMsg(r.body);
      throw Exception(msg ?? '注册失败 (${r.statusCode})');
    }
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<void> logout() async {
    try {
      await http.post(_uri('/api/auth/logout'), headers: _headers());
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> me() async {
    final r = await http.get(_uri('/api/auth/me'), headers: _headers());
    if (r.statusCode != 200) return null;
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  // ---- 视频 ----
  Future<List<VideoItem>> listVideos({
    bool refresh = false,
    VideoFilter filter = const VideoFilter(),
  }) async {
    final params = <String, dynamic>{
      'refresh': refresh ? 1 : 0,
      ...filter.toQuery(),
    };
    final r = await http.get(_uri('/api/videos', params), headers: _headers());
    if (r.statusCode != 200) {
      throw Exception('加载视频列表失败: ${r.statusCode}');
    }
    final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final list = (data['videos'] as List?) ?? const [];
    return list
        .map((e) => VideoItem.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<DirInfo>> listDirs({bool refresh = false}) async {
    final r = await http.get(_uri('/api/dirs', {'refresh': refresh ? 1 : 0}),
        headers: _headers());
    if (r.statusCode != 200) {
      throw Exception('加载目录失败: ${r.statusCode})');
    }
    final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final list = (data['dirs'] as List?) ?? const [];
    return list
        .map((e) => DirInfo.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// 探测单个视频时长
  Future<double?> probeDuration(String videoId) async {
    try {
      final r = await http.post(_uri('/api/videos/$videoId/probe'), headers: _headers());
      if (r.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final d = data['duration'];
      return (d is num) ? d.toDouble() : null;
    } catch (_) {
      return null;
    }
  }

  /// 构造视频流直链
  String streamUrl(String videoId) {
    return '$_baseUrl/api/stream/$videoId';
  }

  /// 判断 baseUrl 的 host 是否在内网（192.168.x / 10.x / 172.16-31 / 127.x）
  bool get isLanHost {
    try {
      final host = Uri.parse(_baseUrl).host.toLowerCase();
      if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
        return true;
      }
      final parts = host.split('.');
      if (parts.length != 4) return false;
      final a = int.tryParse(parts[0]) ?? -1;
      final b = int.tryParse(parts[1]) ?? -1;
      if (a < 0 || b < 0) return false;
      if (a == 10) return true;
      if (a == 192 && b == 168) return true;
      if (a == 172 && b >= 16 && b <= 31) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  // ---- 观看记录 ----
  Future<List<Map<String, dynamic>>> getHistory({int limit = 200}) async {
    final r = await http.get(_uri('/api/history', {'limit': limit}), headers: _headers());
    if (r.statusCode != 200) {
      throw Exception('获取观看记录失败: ${r.statusCode}');
    }
    final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final list = (data['history'] as List?) ?? const [];
    return list.cast<Map<String, dynamic>>();
  }

  Future<void> reportProgress({
    required String videoId,
    required double position,
    required double duration,
  }) async {
    try {
      final headers = _headers();
      headers['Content-Type'] = 'application/json';
      await http.post(
        _uri('/api/history'),
        headers: headers,
        body: jsonEncode({
          'video_id': videoId,
          'position': position,
          'duration': duration,
        }),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  /// 获取单个视频详情
  Future<Map<String, dynamic>> getVideo(String videoId) async {
    final r = await http.get(_uri('/api/videos/$videoId'), headers: _headers());
    if (r.statusCode != 200) {
      throw Exception('获取视频详情失败: ${r.statusCode}');
    }
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 视频详细信息(用于弹窗显示):文件大小、修改时间、编码/帧率/分辨率等
  Future<Map<String, dynamic>> getVideoInfo(String videoId) async {
    final r = await http.get(_uri('/api/videos/$videoId/info'), headers: _headers());
    if (r.statusCode != 200) {
      throw Exception('获取视频详细信息失败: ${r.statusCode}');
    }
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 删除一个视频（需要后端 can_delete 权限）
  Future<bool> deleteVideo(String videoId) async {
    try {
      final r = await http.delete(
        _uri('/api/videos/$videoId'),
        headers: _headers(),
      ).timeout(const Duration(seconds: 10));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 随机挑一个视频（< maxSizeMb）
  /// - exclude：要排除的视频 id 列表（已展示过的，避免重复）
  /// - seriesId：限定在某个短剧内随机（自动连播下一集时用）
  /// - onlyFirstEpisode：True 时只选非 series 或 episode_no==1 的视频
  Future<VideoItem?> pickRandom({
    int maxSizeMb = 200,
    List<String> exclude = const [],
    String? seriesId,
    bool onlyFirstEpisode = false,
  }) async {
    try {
      // 手动拼 query 支持同名多值（http 包的 queryParameters 不支持）
      final parts = <String>['max_size_mb=$maxSizeMb'];
      for (final id in exclude) {
        parts.add('exclude=${Uri.encodeQueryComponent(id)}');
      }
      if (seriesId != null) {
        parts.add('series_id=${Uri.encodeQueryComponent(seriesId)}');
      }
      if (onlyFirstEpisode) {
        parts.add('only_first_episode=true');
      }
      final url = '$_baseUrl/api/random?${parts.join('&')}';
      final r = await http.get(Uri.parse(url), headers: _headers());
      if (r.statusCode == 404) return null;
      if (r.statusCode != 200) {
        throw Exception('随机接口失败: ${r.statusCode}');
      }
      return VideoItem.fromJson(
          jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 短剧详情（按集数排序）
  Future<List<VideoItem>> getSeries(String seriesId) async {
    final r = await http.get(_uri('/api/series/$seriesId'), headers: _headers());
    if (r.statusCode != 200) {
      throw Exception('获取短剧详情失败: ${r.statusCode}');
    }
    final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final list = (data['videos'] as List?) ?? const [];
    return list
        .map((e) => VideoItem.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>?> getProgress(String videoId) async {
    try {
      final r = await http.get(_uri('/api/history/$videoId'), headers: _headers());
      if (r.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (data.isEmpty) return null;
      return data;
    } catch (_) {
      return null;
    }
  }

  // ---- 按需转码 ----
  Future<Map<String, dynamic>?> requestTranscode(String videoId) async {
    try {
      final r = await http.post(
        _uri('/api/transcode/$videoId'),
        headers: _headers(),
      ).timeout(const Duration(seconds: 8));
      if (r.statusCode == 404) return null;
      if (r.statusCode != 200) return null;
      return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> transcodeStatus(String videoId) async {
    try {
      final r = await http.get(
        _uri('/api/transcode/$videoId'),
        headers: _headers(),
      ).timeout(const Duration(seconds: 5));
      if (r.statusCode != 200) return null;
      return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<bool> cancelTranscode(String videoId) async {
    try {
      final r = await http.post(
        _uri('/api/transcode/$videoId/cancel'),
        headers: _headers(),
      ).timeout(const Duration(seconds: 5));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  String? _extractMsg(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['detail'] != null) return j['detail'].toString();
    } catch (_) {}
    return null;
  }
}
