import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';

/// 用户信息页：注册时间、观看时长、退出登录
class UserProfilePage extends StatefulWidget {
  const UserProfilePage({
    super.key,
    required this.api,
    required this.username,
  });
  final ApiService api;
  final String username;

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  double? _createdAt; // 用户注册时间（秒）
  bool _loadingHistory = true;
  List<Map<String, dynamic>> _history = [];
  // 总观看时长（秒），从 history 累加
  double _totalDuration = 0;
  int _finishedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    // 用户基础信息（注册时间）
    try {
      final me = await widget.api.me();
      final ts = me?['created_at'];
      if (ts is num) _createdAt = ts.toDouble();
    } catch (_) {}

    // 观看历史
    try {
      final h = await widget.api.getHistory(limit: 200);
      if (!mounted) return;
      setState(() {
        _history = h;
        double total = 0;
        int finished = 0;
        for (final r in h) {
          total += (r['position'] as num?)?.toDouble() ?? 0;
          if (r['finished'] == true) finished++;
        }
        _totalDuration = total;
        _finishedCount = finished;
        _loadingHistory = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  String _fmtDuration(double sec) {
    if (sec < 60) return '${sec.toInt()} 秒';
    if (sec < 3600) return '${(sec / 60).toStringAsFixed(0)} 分钟';
    if (sec < 86400) return '${(sec / 3600).toStringAsFixed(1)} 小时';
    return '${(sec / 86400).toStringAsFixed(1)} 天';
  }

  int _daysSince(double ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch((ts * 1000).toInt());
    return DateTime.now().difference(dt).inDays;
  }

  String _fmtDate(double ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch((ts * 1000).toInt());
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('退出登录？'),
        content: const Text('退出后会从已记住账号列表移除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try { await widget.api.logout(); } catch (_) {}
    await AuthService().remove(widget.username);
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 用户头像 + 信息
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.gradientCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                Container(
                  width: 64, height: 64,
                  decoration: const BoxDecoration(
                    gradient: AppColors.gradientBrand,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      widget.username.isNotEmpty
                          ? widget.username[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.username,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(
                        _createdAt == null
                            ? '已登录'
                            : '已加入 ${_daysSince(_createdAt!)} 天 · ${_fmtDate(_createdAt!)}',
                        style: const TextStyle(
                            color: AppColors.textTertiary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 数据卡片
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: AppColors.bgElev,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                _StatBox(
                  label: '累计观看',
                  value: _fmtDuration(_totalDuration),
                ),
                _StatBox(
                  label: '看完视频',
                  value: '$_finishedCount',
                ),
                _StatBox(
                  label: '历史条目',
                  value: '${_history.length}',
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          // 退出登录
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout, color: AppColors.danger),
              label: const Text('退出登录', style: TextStyle(color: AppColors.danger)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: AppColors.danger),
              ),
            ),
          ),

          const SizedBox(height: 24),
          // 历史小预览
          const _SectionTitle('最近观看'),
          if (_loadingHistory)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
            )
          else if (_history.isEmpty)
            Container(
              padding: const EdgeInsets.all(28),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.bgElev,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: const Text('还没有观看记录',
                  style: TextStyle(color: AppColors.textTertiary)),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: AppColors.bgElev,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < (_history.length > 20 ? 20 : _history.length); i++) ...[
                    _HistoryRow(rec: _history[i]),
                    if (i < (_history.length > 20 ? 20 : _history.length) - 1)
                      const Divider(height: 1, color: AppColors.divider, indent: 14, endIndent: 14),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.rec});
  final Map<String, dynamic> rec;

  double get _progress {
    final pos = (rec['position'] as num?)?.toDouble() ?? 0;
    final dur = (rec['duration'] as num?)?.toDouble() ?? 1;
    if (dur <= 0) return 0;
    return (pos / dur).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final name = (rec['name'] as String?)?.trim();
    final path = (rec['path'] as String?) ?? (rec['dir'] as String?) ?? '';
    final progress = _progress;
    final finished = rec['finished'] == true;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 32, height: 32,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 3,
                  backgroundColor: AppColors.divider,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
              Icon(finished ? Icons.check : Icons.play_arrow,
                  color: Colors.white, size: 16),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (name == null || name.isEmpty) ? '视频 ${rec['video_id']}' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 0, 10),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.5)),
      );
}