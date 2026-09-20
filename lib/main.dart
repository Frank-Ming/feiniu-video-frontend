import 'package:fvp/fvp.dart' as fvp;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pages/login_page.dart';
import 'pages/main_shell_page.dart';
import 'pages/settings_page.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/endpoint_store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // fvp 注册：在 Android 上让 video_player 用 libmdk/FFmpeg 内核解码,
  // 解决 HEVC/AV1/MKV 等编码兼容问题
  // 优先 FFmpeg 软解(覆盖所有 codec,天玑 9000 兼容性最好),
  // MediaCodec 硬解作为可选加速(只对 h264 高效,hevc 在某些机型兼容性差)
  // 启用所有 demuxer(mp4/mov/mkv/ts/avi/flv) + 让 libavformat 自动嗅探容器
  fvp.registerWith(options: {
    'video.decoders': ['FFmpeg', 'MediaCodec'],
    'video.demuxers': [
      'mov,mp4,m4a,3gp,3g2,mj2',  // mp4/mov
      'matroska,webm',          // mkv
      'mpegts',                 // TS(包括 .mp4 扩展名实际是 TS 的)
      'avi',                    // avi
      'flv',                    // flv
      'hls',                    // m3u8
    ],
    'video.hwaccel': 1,  // 启用硬件加速(仅对 MediaCodec 生效,FFmpeg 是软解)
    'video.packet-buffering': 0,  // 减少缓冲延迟
    'demux.timeout': 15000,  // 15s 探不到就放弃
  });
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const FeiniuVideoApp());
}

class FeiniuVideoApp extends StatelessWidget {
  const FeiniuVideoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '飞牛短视频',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routes: {
        '/': (_) => const RootDecider(),
        '/settings': (_) => const SettingsPage(),
      },
      initialRoute: '/',
    );
  }
}

/// 启动时智能选择 endpoint 并登录
class RootDecider extends StatefulWidget {
  const RootDecider({super.key});

  @override
  State<RootDecider> createState() => _RootDeciderState();
}

class _RootDeciderState extends State<RootDecider> {
  Widget? _child;
  String? _bootErr;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final endpoints = await EndpointStore().list();
      if (endpoints.isEmpty) {
        setState(() => _child = const LoginPage());
        return;
      }

      // 当前活跃 endpoint 优先；不通就挨个试
      final store = EndpointStore();
      String? activeId = await store.activeId();
      EndpointRecord? chosen;
      String? failReason;

      final ordered = <EndpointRecord>[
        if (activeId != null) ...endpoints.where((e) => e.id == activeId),
        ...endpoints.where((e) => e.id != activeId),
      ];

      for (final ep in ordered) {
        final api = ApiService(baseUrl: ep.url);
        final ok = await api.ping();
        if (ok) {
          await store.markSuccess(ep.id);
          await store.setActive(ep.id);
          chosen = ep;
          break;
        } else {
          await store.markFail(ep.id, '健康检查失败');
          failReason ??= '${ep.label}: 连接失败';
        }
      }

      if (chosen == null) {
        // 都不通，进入登录页（会自动用当前 active 那个 url）
        setState(() => _child = LoginPage(endpoint: endpoints.first));
        return;
      }

      // 用选中的 endpoint 找匹配的账号
      final auth = AuthService();
      final users = await auth.list();
      final matched = users.where((u) => u.endpointId == chosen!.id).toList();
      if (matched.isEmpty) {
        setState(() => _child = LoginPage(endpoint: chosen!));
        return;
      }

      // 拿第一个匹配的账号试 token
      final user = matched.first;
      final api = ApiService(baseUrl: chosen.url, token: user.token);
      final me = await api.me();
      if (me == null || me['username'] == null) {
        // token 失效，删除该条账号并去登录
        await auth.remove(user.username);
        setState(() => _child = LoginPage(endpoint: chosen));
        return;
      }
      final username = me['username'] as String;
      final isAdmin = me['is_admin'] == true;
      // 超管账号不能登录客户端
      if (isAdmin) {
        await auth.remove(user.username);
        setState(() => _child = LoginPage(endpoint: chosen));
        return;
      }
      if (!mounted) return;
      setState(() => _child = MainShellPage(api: api, username: username));
    } catch (e) {
      setState(() {
        _bootErr = e.toString();
        _child = const LoginPage();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_child != null) return _child!;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.gradientScaffold),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              if (_bootErr != null) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    '启动异常：$_bootErr',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}