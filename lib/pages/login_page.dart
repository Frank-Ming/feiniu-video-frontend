import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/endpoint_store.dart';
import '../theme.dart';
import 'main_shell_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.endpoint});
  final EndpointRecord? endpoint;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _err;
  late EndpointRecord _endpoint;
  bool _remember = true;

  @override
  void initState() {
    super.initState();
    _endpoint = widget.endpoint ?? EndpointRecord(
      id: '', label: '默认', url: 'http://192.168.1.100:6969',
    );
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      // 如果 endpoint id 为空（首次进入），先保存
      if (_endpoint.id.isEmpty) {
        _endpoint = await EndpointStore().upsert(
          _endpoint.label,
          _endpoint.url,
        );
      }

      // 注意：账号只能由超管在后台新增，客户端没有注册入口
      final api = ApiService(baseUrl: _endpoint.url);
      final r = await api.login(_username.text, _password.text);
      final token = r['token'] as String;
      final username = r['username'] as String;
      final isAdmin = r['is_admin'] == true;

      // 超管账号不能登录客户端
      if (isAdmin) {
        throw Exception('此账号是管理员账号，请用普通用户账号登录');
      }

      // 标记 endpoint 健康
      await EndpointStore().markSuccess(_endpoint.id);

      if (_remember) {
        await AuthService().saveLogin(
          username: username,
          token: token,
          endpointId: _endpoint.id,
        );
      }
      if (!mounted) return;
      api.setToken(token);
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => MainShellPage(api: api, username: username),
      ));
    } catch (e) {
      // 出错时附加详细诊断信息（便于排查网络问题）
      String msg = e.toString().replaceFirst('Exception: ', '');
      try {
        final api = ApiService(baseUrl: _endpoint.url);
        final diag = await api.debugPing();
        msg = '$msg\n\n--- 诊断 ---\n$diag';
      } catch (_) {}
      if (mounted) setState(() => _err = msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _editEndpoint() async {
    final endpoints = await EndpointStore().list();
    if (!mounted) return;
    final picked = await showModalBottomSheet<EndpointRecord>(
      context: context,
      backgroundColor: AppColors.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => _EndpointPicker(
        current: _endpoint,
        endpoints: endpoints,
        sheetContext: sheetCtx,
      ),
    );
    if (picked != null) {
      setState(() => _endpoint = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.gradientScaffold),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        gradient: AppColors.gradientBrand,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 48),
                    ),
                    const SizedBox(height: 24),
                    ShaderMask(
                      shaderCallback: (rect) =>
                          AppColors.gradientBrand.createShader(rect),
                      child: const Text(
                        '飞牛短视频',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28, fontWeight: FontWeight.w800,
                          color: Colors.white, letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '登录继续观看',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 当前后端地址（点击切换）
                    _EndpointPill(endpoint: _endpoint, onTap: _editEndpoint),
                    const SizedBox(height: 18),

                    TextField(
                      controller: _username,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        labelText: '用户名',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _busy ? null : _submit(),
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        labelText: '密码',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _remember,
                      onChanged: (v) => setState(() => _remember = v),
                      title: const Text('记住账号', style: TextStyle(fontSize: 13)),
                      activeThumbColor: AppColors.primary,
                      dense: true,
                    ),
                    if (_err != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 240),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _err!,
                            style: const TextStyle(
                                color: AppColors.danger, fontSize: 12,
                                height: 1.4, fontFamily: 'monospace'),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _busy ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('登录'),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '账号由管理员在后台开通',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textTertiary, fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EndpointPill extends StatelessWidget {
  const _EndpointPill({required this.endpoint, required this.onTap});
  final EndpointRecord endpoint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgElev,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.dns, color: AppColors.accent, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(endpoint.label,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600)),
                    Text(endpoint.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textTertiary, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// 选 endpoint 的底部弹窗
class _EndpointPicker extends StatelessWidget {
  const _EndpointPicker({
    required this.current,
    required this.endpoints,
    required this.sheetContext,
  });
  final EndpointRecord current;
  final List<EndpointRecord> endpoints;
  final BuildContext sheetContext;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('选择后端地址',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final ep in endpoints)
                      ListTile(
                        leading: Icon(
                          ep.id == current.id
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: ep.id == current.id
                              ? AppColors.primary
                              : AppColors.textTertiary,
                        ),
                        title: Text(ep.label),
                        subtitle: Text(ep.url),
                        onTap: () => Navigator.of(sheetContext).pop(ep),
                      ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.add_circle_outline,
                          color: AppColors.accent),
                      title: const Text('新增后端地址'),
                      onTap: () async {
                        // 在 picker 内部弹 dialog；不关闭 picker
                        final newRec = await _showAddDialog(context);
                        if (newRec != null && sheetContext.mounted) {
                          // 让 picker 关闭并把这个新地址作为结果返回
                          Navigator.of(sheetContext).pop(newRec);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 弹一个内嵌 AlertDialog（无需关闭 picker）
  Future<EndpointRecord?> _showAddDialog(BuildContext context) async {
    final labelCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    return showDialog<EndpointRecord>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('新增后端地址'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: '备注（如：家里内网、公司公网）',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: urlCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: '后端 URL',
                hintText: 'http://192.168.1.100:6969',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final label = labelCtrl.text.trim();
              final url = urlCtrl.text.trim();
              if (url.isEmpty) return;
              final rec = await EndpointStore().upsert(
                label.isEmpty ? '默认' : label,
                url,
              );
              if (dialogCtx.mounted) Navigator.of(dialogCtx).pop(rec);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
