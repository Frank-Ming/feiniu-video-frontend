import 'package:flutter/material.dart';

/// 抖音风格的视频进度条
/// - 当前播放进度（粉）
/// - 缓冲进度（白半透明）
/// - 支持点击/拖动跳转
class DyProgressBar extends StatefulWidget {
  const DyProgressBar({
    super.key,
    required this.current,
    required this.total,
    required this.buffered,
    required this.onSeek,
    required this.timeText,
    this.height = 3.0,
  });

  final Duration current;
  final Duration total;
  final Duration buffered;
  final ValueChanged<Duration> onSeek;
  final String timeText;
  final double height;

  @override
  State<DyProgressBar> createState() => _DyProgressBarState();
}

class _DyProgressBarState extends State<DyProgressBar> {
  double? _dragFraction; // 0..1

  double _getFraction(Duration d) {
    final t = widget.total.inMilliseconds;
    if (t <= 0) return 0;
    final v = d.inMilliseconds / t;
    return v.clamp(0.0, 1.0);
  }

  void _seek(Offset local, double trackWidth) {
    if (widget.total.inMilliseconds <= 0) return;
    final f = (local.dx / trackWidth).clamp(0.0, 1.0);
    final ms = (widget.total.inMilliseconds * f).round();
    widget.onSeek(Duration(milliseconds: ms));
  }

  @override
  Widget build(BuildContext context) {
    final cur = _dragFraction ?? _getFraction(widget.current);
    final buf = _getFraction(widget.buffered);

    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 26,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // 透明触控层（点击/拖动）
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapDown: (d) => _seek(d.localPosition, w),
                    onHorizontalDragUpdate: (d) {
                      setState(() {
                        _dragFraction = (d.localPosition.dx / w).clamp(0.0, 1.0);
                      });
                    },
                    onHorizontalDragEnd: (d) {
                      final f = _dragFraction ?? cur;
                      final ms = (widget.total.inMilliseconds * f).round();
                      widget.onSeek(Duration(milliseconds: ms));
                      setState(() => _dragFraction = null);
                    },
                  ),
                ),
                // 进度条
                SizedBox(
                  height: widget.height,
                  child: Stack(
                    children: [
                      Container(color: Colors.white24),
                      FractionallySizedBox(
                        widthFactor: buf,
                        child: Container(color: Colors.white54),
                      ),
                      FractionallySizedBox(
                        widthFactor: cur,
                        child: Container(color: const Color(0xFFFF2C55)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.timeText,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const Text('飞牛短视频',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ],
      );
    });
  }
}
