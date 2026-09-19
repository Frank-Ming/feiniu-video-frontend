import 'package:flutter/material.dart';

import '../models/video_item.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/endpoint_store.dart';
import '../theme.dart';
import 'login_page.dart';
import 'main_shell_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.api, this.username});
  final ApiService? api;
  final String? username;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<EndpointRecord> _endpoints = [];
  List<UserRecord> _users = [];
  List<Map<String, dynamic>> _history = [];
  bool _loadingHistory = true;
  String? _activeEndpointId;
  // 应用版本号（与 pubspec.yaml 同步：major.minor）
  static const String _appVersion = '1.0.0';
  bool _debugEnabled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 从 MainShellPage 拉调试状态（如果用户是从主页进来的）
    _debugEnabled = MainShellPage.globalDebugEnabled;
  }

  void _setDebug(bool v) {
    setState(() => _debugEnabled = v);
    MainShellPage.globalDebugEnabled = v;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(v ? '调试日志已开启' : '调试日志已关闭'),
      duration: const Duration(seconds: 1),
    ));
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final store = EndpointStore();
    final auth = AuthService();
    final eps = await store.list();
    setState(() {
      _endpoints = eps;
      _activeEndpointId = eps.any((e) => e.id == (widget.api?.token != null
              ? _users.firstWhere(
                  (u) => u.token == widget.api!.token,
                  orElse: () => UserRecord(
                    username: '',
                    token: '',
                    endpointId: '',
                  ),
                ).endpointId
              : null))
          ? _users.firstWhere(
              (u) => u.token == widget.api!.token,
              orElse: () => UserRecord(
                username: '', token: '', endpointId: '',
              ),
            ).endpointId
          : null;
    });
    _activeEndpointId = await store.activeId();
    _users = await auth.list();
    if (widget.api != null) await _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final h = await widget.api!.getHistory(limit: 100);
      setState(() {
        _history = h;
        _loadingHistory = false;
      });
    } catch (_) {
      setState(() => _loadingHistory = false);
    }
  }

  Future<void> _setActiveEndpoint(String id) async {
    await EndpointStore().setActive(id);
    setState(() => _activeEndpointId = id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已设为默认后端地址')),
      );
    }
  }

  Future<void> _removeEndpoint(EndpointRecord ep) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('删除后端地址？'),
        content: Text('删除「${ep.label}」(${ep.url}) 后，使用此地址的账号也会一并移除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // 删除绑定此 endpoint 的账号
    final auth = AuthService();
    final users = await auth.list();
    for (final u in users.where((u) => u.endpointId == ep.id)) {
      await auth.remove(u.username);
    }
    await EndpointStore().remove(ep.id);
    await _loadAll();
  }

  Future<void> _editLabel(EndpointRecord ep) async {
    final ctrl = TextEditingController(text: ep.label);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('重命名'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '备注名'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    ep.label = result;
    // upsert 不便直接改 label，重新 upsert 然后删旧的
    await EndpointStore().upsert(ep.label, ep.url);
    // 同 url 的会被覆盖，不会重复
    await _loadAll();
  }

  Future<void> _removeUser(UserRecord u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('移除账号？'),
        content: Text('「${u.username}」将从列表移除（不会删除服务端账号）。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AuthService().remove(u.username);
    await _loadAll();
  }

  Future<void> _switchAccount(UserRecord u) async {
    final eps = await EndpointStore().list();
    final ep = eps.where((e) => e.id == u.endpointId).toList();
    if (ep.isEmpty) return;
    await EndpointStore().setActive(ep.first.id);
    await AuthService().setActive(u.username);
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    }
  }

  Future<void> _logout() async {
    if (widget.api != null) await widget.api!.logout();
    // 清掉当前账号的本地记录
    if (widget.username != null) {
      await AuthService().remove(widget.username!);
    }
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
    }
  }

  Future<void> _resumeFromHistory(Map<String, dynamic> rec) async {
    if (widget.api == null) return;
    final vid = rec['video_id'] as String?;
    if (vid == null) return;
    try {
      final detail = await widget.api!.getVideo(vid);
      final video = VideoItem.fromJson(detail);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => MainShellPage(
          api: widget.api!,
          username: widget.username ?? '',
          initialVideos: [video],
          initialIndex: 0,
          autoResumeFromHistory: rec,
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开视频: $e')),
      );
    }
  }

  Future<void> _deleteHistoryItem(Map<String, dynamic> rec) async {
    final vid = rec['video_id'] as String?;
    if (vid == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('删除这条记录？'),
        content: const Text('该视频的历史进度会被清除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('删除', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _history.removeWhere((h) => h['video_id'] == vid));
  }

  String _fmtTime(num? s) {
    if (s == null) return '--';
    final sec = s.toDouble();
    if (sec < 60) return '${sec.toInt()}s';
    final m = (sec / 60).floor();
    final r = (sec % 60).round();
    return '${m}m${r.toString().padLeft(2, '0')}s';
  }

  String _relTime(num? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().millisecondsSinceEpoch / 1000 - ts.toDouble();
    if (diff < 60) return '刚刚';
    if (diff < 3600) return '${(diff / 60).floor()} 分钟前';
    if (diff < 86400) return '${(diff / 3600).floor()} 小时前';
    return '${(diff / 86400).floor()} 天前';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 当前账号
          if (widget.username != null)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                gradient: AppColors.gradientCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: const BoxDecoration(
                      gradient: AppColors.gradientBrand,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.username!,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        const Text('已登录', style: TextStyle(color: AppColors.textTertiary)),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _logout,
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                    child: const Text('退出'),
                  ),
                ],
              ),
            ),

          // 后端地址管理
          const _SectionTitle('后端地址', trailing: '点星设为默认'),
          Container(
            decoration: BoxDecoration(
              color: AppColors.bgElev,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              children: [
                if (_endpoints.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: Text('尚未添加后端地址', style: TextStyle(color: AppColors.textTertiary)),
                    ),
                  )
                else
                  for (var i = 0; i < _endpoints.length; i++) ...[
                    _EndpointRow(
                      ep: _endpoints[i],
                      isActive: _endpoints[i].id == _activeEndpointId,
                      onSetDefault: () => _setActiveEndpoint(_endpoints[i].id),
                      onRename: () => _editLabel(_endpoints[i]),
                      onDelete: () => _removeEndpoint(_endpoints[i]),
                    ),
                    if (i < _endpoints.length - 1)
                      const Divider(height: 1, color: AppColors.divider, indent: 14, endIndent: 14),
                  ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                  child: Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _addEndpoint,
                        icon: const Icon(Icons.add),
                        label: const Text('添加新地址'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 账号管理
          if (_users.isNotEmpty) ...[
            const SizedBox(height: 18),
            const _SectionTitle('已记住的账号'),
            Container(
              decoration: BoxDecoration(
                color: AppColors.bgElev,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < _users.length; i++) ...[
                    _UserRow(
                      user: _users[i],
                      endpoint: _endpoints
                          .where((e) => e.id == _users[i].endpointId)
                          .toList()
                          .firstOrNull,
                      isCurrent: widget.username == _users[i].username,
                      onSwitch: () => _switchAccount(_users[i]),
                      onRemove: () => _removeUser(_users[i]),
                    ),
                    if (i < _users.length - 1)
                      const Divider(height: 1, color: AppColors.divider, indent: 14, endIndent: 14),
                  ],
                ],
              ),
            ),
          ],

          // 观看记录
          if (widget.api != null) ...[
            const SizedBox(height: 24),
            const _SectionTitle('观看记录'),
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
                child: const Text('还没有观看记录', style: TextStyle(color: AppColors.textTertiary)),
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
                    for (var i = 0; i < _history.length; i++) ...[
                      _HistoryTile(
                        rec: _history[i],
                        fmtTime: _fmtTime,
                        relTime: _relTime,
                        onTap: () => _resumeFromHistory(_history[i]),
                        onLongPress: () => _deleteHistoryItem(_history[i]),
                      ),
                      if (i < _history.length - 1)
                        const Divider(height: 1, color: AppColors.divider, indent: 14, endIndent: 14),
                    ],
                  ],
                ),
              ),
          ],

          // 关于 + 版本 + 调试开关
          const SizedBox(height: 24),
          const _SectionTitle('关于'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.bgElev,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.movie_creation_outlined,
                        color: AppColors.textTertiary, size: 18),
                    const SizedBox(width: 8),
                    const Text('飞牛短视频',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text(
                      'v$_appVersion',
                      style: const TextStyle(
                          color: AppColors.textTertiary, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // 调试模式开关：连续 7 次点击版本号也可触发
                Row(
                  children: [
                    const Icon(Icons.bug_report_outlined,
                        color: AppColors.textTertiary, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('调试日志',
                          style: TextStyle(fontSize: 14)),
                    ),
                    Switch(
                      value: _debugEnabled,
                      activeThumbColor: AppColors.primary,
                      onChanged: _setDebug,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  '开启后主页会显示 DEBUG 标记，并记录播放/转码日志',
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addEndpoint() async {
    final labelCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('添加后端地址'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(
                labelText: '备注（如：家里内网、公司公网）',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                labelText: '后端 URL',
                hintText: 'http://192.168.1.100:6969',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              final url = urlCtrl.text.trim();
              if (url.isEmpty) {
                Navigator.pop(context, false);
                return;
              }
              await EndpointStore().upsert(
                labelCtrl.text.trim().isEmpty ? '默认' : labelCtrl.text.trim(),
                url,
              );
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok == true) await _loadAll();
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 0, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.5)),
          ),
          if (trailing != null)
            Text(trailing!,
                style: const TextStyle(
                    color: AppColors.textTertiary, fontSize: 11)),
        ],
      ),
    );
  }
}

class _EndpointRow extends StatelessWidget {
  const _EndpointRow({
    required this.ep,
    required this.isActive,
    required this.onSetDefault,
    required this.onRename,
    required this.onDelete,
  });
  final EndpointRecord ep;
  final bool isActive;
  final VoidCallback onSetDefault;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isActive ? null : onSetDefault,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                isActive ? Icons.star_rounded : Icons.star_outline_rounded,
                color: isActive ? AppColors.accent : AppColors.textTertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            ep.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isActive
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                              fontWeight:
                                  isActive ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (isActive)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('默认',
                                style: TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                    Text(ep.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textTertiary, fontSize: 12)),
                    if (ep.lastFailAt != null &&
                        (ep.lastSuccessAt == null ||
                            ep.lastFailAt!.isAfter(ep.lastSuccessAt!)))
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '最近失败：${_fmtAgo(ep.lastFailAt!)}',
                          style: const TextStyle(
                              color: AppColors.danger, fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                color: AppColors.textTertiary,
                onPressed: onRename,
                tooltip: '重命名',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: AppColors.textTertiary,
                onPressed: onDelete,
                tooltip: '删除',
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.endpoint,
    required this.isCurrent,
    required this.onSwitch,
    required this.onRemove,
  });
  final UserRecord user;
  final EndpointRecord? endpoint;
  final bool isCurrent;
  final VoidCallback onSwitch;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.bgCard,
            child: Text(
              user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
              style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontWeight: isCurrent
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (isCurrent)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('当前',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
                Text(
                  '${endpoint?.label ?? "(已删除)"} · ${endpoint?.url ?? ""}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                ),
              ],
            ),
          ),
          if (!isCurrent)
            TextButton(
              onPressed: onSwitch,
              child: const Text('切换'),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            color: AppColors.textTertiary,
            onPressed: onRemove,
            tooltip: '移除',
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.rec,
    required this.fmtTime,
    required this.relTime,
    this.onTap,
    this.onLongPress,
  });
  final Map<String, dynamic> rec;
  final String Function(num?) fmtTime;
  final String Function(num?) relTime;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

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
    final finished = rec['finished'] == true;
    final progress = _progress;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 38, height: 38,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 3,
                  backgroundColor: AppColors.divider,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
              Icon(
                finished ? Icons.check : Icons.play_arrow,
                color: Colors.white, size: 18,
              ),
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
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (path.isNotEmpty) path,
                    fmtTime(rec['position']),
                    relTime(rec['updated_at']),
                  ].where((s) => s.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}