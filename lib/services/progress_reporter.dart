import 'api_service.dart';

/// 频率感知进度上报器
/// - 每 5 秒最多上报一次（避免网络/服务器压力）
/// - 进度变化 > 1% 或者 间隔 > 8 秒强制上报
class ProgressReporter {
  ProgressReporter(this._api, this._videoId, double duration) : _duration = duration;
  final ApiService _api;
  final String _videoId;
  double _duration;

  set duration(double v) { _duration = v; }

  double _lastReportedFraction = 0;
  DateTime _lastReportTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// 尝试上报；返回 true 表示真的发了请求
  bool report(double position) {
    if (_duration <= 0) return false;
    if (position < 1) return false;

    final now = DateTime.now();
    final dt = now.difference(_lastReportTime).inMilliseconds;
    final fraction = position / _duration;
    final df = (fraction - _lastReportedFraction).abs();

    // 上报条件：间隔超过 8s，或进度变化 > 1% 且间隔 > 5s
    final shouldReport = dt > 8000 || (df > 0.01 && dt > 5000);

    if (!shouldReport) return false;

    _lastReportTime = now;
    _lastReportedFraction = fraction;
    _api.reportProgress(videoId: _videoId, position: position, duration: _duration);
    return true;
  }

  /// 主动强制上报（页面退出 / 切到后台时）
  void flush(double position) {
    _lastReportTime = DateTime.now();
    if (_duration > 0) {
      _lastReportedFraction = position / _duration;
    }
    _api.reportProgress(videoId: _videoId, position: position, duration: _duration);
  }
}