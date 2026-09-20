import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 视频详细信息弹窗 (点击主菜单"视频详细信息"后调用)。
///
/// 显示字段:
///   - 名称 / 路径 / 完整路径
///   - 文件大小 / 修改日期 / 时长
///   - 编码格式 (codec) / 帧率 / 分辨率 / 画面比例
///   - 容器格式 / 总码率 / 视频码率 / 像素格式
///   - 音频: 编码 / 采样率 / 声道
///
/// 调用方式:
/// ```dart
/// showDialog(
///   context: context,
///   barrierDismissible: false,
///   builder: (_) => VideoInfoDialog(
///     api: api,
///     videoId: currentVideoId,
///   ),
/// );
/// ```
class VideoInfoDialog extends StatefulWidget {
  const VideoInfoDialog({
    super.key,
    required this.api,
    required this.videoId,
  });

  final dynamic api; // ApiService, 类型用 dynamic 避免循环 import
  final String videoId;

  @override
  State<VideoInfoDialog> createState() => _VideoInfoDialogState();
}

class _VideoInfoDialogState extends State<VideoInfoDialog> {
  Map<String, dynamic>? _info;
  String? _err;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await widget.api.getVideoInfo(widget.videoId);
      if (!mounted) return;
      setState(() {
        _info = m;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E22),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _err != null
                      ? _errorView()
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: _buildFields(_info!),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12, width: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.white70, size: 20),
          const SizedBox(width: 8),
          const Text('视频详细信息',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(
            tooltip: '关闭',
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _errorView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, color: Colors.white54, size: 40),
          const SizedBox(height: 12),
          Text(_err!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildFields(Map<String, dynamic> info) {
    final probe = (info['probe'] as Map?)?.cast<String, dynamic>() ?? {};
    final v = (probe['video'] as Map?)?.cast<String, dynamic>();
    final a = (probe['audio'] as Map?)?.cast<String, dynamic>();

    final dur = info['duration'] ?? probe['duration'];
    final aspect = (v != null && v['width'] != null && v['height'] != null)
        ? (v['width'] as num) / (v['height'] as num)
        : null;

    final entries = <_Row>[
      _Row('名称', info['name']?.toString() ?? '—', copy: info['name']?.toString()),
      _Row('路径', info['path']?.toString() ?? '—', copy: info['path']?.toString()),
      _Row('完整路径', info['full_path']?.toString() ?? '—', copy: info['full_path']?.toString()),
      _Row('文件大小', _fmtBytes(info['size'])),
      _Row('修改日期', _fmtDate(info['mtime'])),
      _Row('时长', _fmtDuration(dur)),
      _Row('画面尺寸',
          v != null ? '${v['width']} × ${v['height']}' : '—'),
      _Row('画面比例',
          aspect != null ? '${aspect.toStringAsFixed(3)}  (${_ratioLabel(aspect)})' : '—'),
      _Row('帧率',
          v != null ? _fmtFps(v['avg_frame_rate']) : '—'),
      _Row('视频编码',
          v != null
              ? _fmtCodec(v['codec_name'], v['codec_long_name'], v['profile'])
              : '—'),
      _Row('像素格式', v?['pix_fmt']?.toString() ?? '—'),
      _Row('视频码率', _fmtBitrate(v?['bit_rate'])),
      _Row('音频编码',
          a != null
              ? _fmtAudioCodec(a['codec_name'], a['sample_rate'], a['channels'])
              : '—'),
      _Row('音频码率', _fmtBitrate(a?['bit_rate'])),
      _Row('容器格式', probe['format_name']?.toString() ?? '—'),
      _Row('总码率', _fmtBitrate(probe['bitrate'])),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in entries) _rowView(r),
      ],
    );
  }

  Widget _rowView(_Row r) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(r.label,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          Expanded(
            child: GestureDetector(
              onLongPress: r.copy == null
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: r.copy!));
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已复制到剪贴板'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
              child: Text(
                r.value,
                style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 格式化 ----------

  static String _fmtBytes(dynamic size) {
    if (size == null) return '—';
    final n = (size as num).toInt();
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    if (n < 1024 * 1024 * 1024) return '${(n / 1024 / 1024).toStringAsFixed(2)} MB';
    return '${(n / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  static String _fmtBitrate(dynamic bps) {
    if (bps == null) return '—';
    final n = (bps as num).toInt();
    if (n <= 0) return '—';
    if (n < 1000) return '$n bps';
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(0)} kbps';
    return '${(n / 1000000).toStringAsFixed(2)} Mbps';
  }

  static String _fmtFps(dynamic fps) {
    if (fps == null) return '—';
    final n = (fps as num).toDouble();
    if (n <= 0) return '—';
    return '${n.toStringAsFixed(2)} fps';
  }

  static String _fmtCodec(dynamic codec, dynamic longName, dynamic profile) {
    if (codec == null) return '—';
    final base = (codec as String).toUpperCase();
    if (profile != null && profile.toString().isNotEmpty) {
      return '$base · ${profile}';
    }
    if (longName != null && longName.toString().isNotEmpty) {
      return '$base · ${longName}';
    }
    return base;
  }

  static String _fmtAudioCodec(dynamic codec, dynamic sampleRate, dynamic channels) {
    if (codec == null) return '—';
    final parts = <String>[(codec as String).toUpperCase()];
    if (sampleRate != null) parts.add('${(sampleRate as num).toInt()} Hz');
    if (channels != null) parts.add(channels.toString());
    return parts.join(' · ');
  }

  static String _fmtDate(dynamic ts) {
    if (ts == null) return '—';
    final n = (ts as num).toDouble();
    final dt = DateTime.fromMillisecondsSinceEpoch((n * 1000).toInt());
    String two(int x) => x.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  static String _fmtDuration(dynamic sec) {
    if (sec == null) return '—';
    final n = (sec as num).toDouble();
    if (n <= 0) return '—';
    final h = n ~/ 3600;
    final m = ((n % 3600) ~/ 60).toInt();
    final s = (n % 60).toInt();
    if (h > 0) {
      return '${h}h ${m}m ${s}s (${n.toStringAsFixed(1)}s)';
    }
    if (m > 0) {
      return '${m}m ${s}s (${n.toStringAsFixed(1)}s)';
    }
    return '${s}s';
  }

  static String _ratioLabel(double aspect) {
    // 简单映射到常见比例
    const ratios = <(double, String)>[
      (16 / 9, '16:9'),
      (4 / 3, '4:3'),
      (21 / 9, '21:9'),
      (1.0, '1:1'),
      (3 / 4, '3:4'),
      (9 / 16, '9:16'),
      (2 / 3, '2:3'),
      (3 / 2, '3:2'),
    ];
    String best = aspect.toStringAsFixed(2);
    double bestDiff = double.infinity;
    for (final r in ratios) {
      final d = (aspect - r.$1).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = r.$2;
      }
    }
    if (bestDiff < 0.02) return best; // 接近标准比例才显示
    return best;
  }
}

class _Row {
  _Row(this.label, this.value, {this.copy});
  final String label;
  final String value;
  final String? copy;
}
