// 调试日志服务:把日志同时输出到内存列表和手机本地文件
// 文件路径: <app 文档目录>/debug.log
//
// 用法:
//   DebugLog.i('aspect ready');  // 输出到控制台 + 内存 + 文件
//   await DebugLog.flush();      // app 退出前强制写盘
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class DebugLog {
  static final List<String> _buffer = <String>[];
  static const int _maxBuffer = 500;
  static File? _file;
  static bool _initialized = false;
  static bool _enabled = false;

  /// 启用调试日志(设置页开关)
  static void enable(bool v) {
    _enabled = v;
    if (v && !_initialized) {
      _init();
    }
  }

  static bool get enabled => _enabled;

  static Future<void> _init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/debug.log');
      _initialized = true;
    } catch (e) {
      // ignore
    }
  }

  /// 记录一条日志
  static void i(String msg) {
    if (!_enabled) return;
    final line = '${DateTime.now().toIso8601String().substring(11, 23)} $msg';
    _buffer.add(line);
    if (_buffer.length > _maxBuffer) {
      _buffer.removeAt(0);
    }
    // 异步写文件
    _writeLine(line);
  }

  /// 写一行到文件(异步)
  static void _writeLine(String line) {
    final f = _file;
    if (f == null) return;
    // 用 unawaited future,失败不抛
    f.writeAsString(
      '$line\n',
      mode: FileMode.append,
      flush: false,
    ).catchError((Object _) => f);
  }

  /// 强制写盘(用于退出 app 前)
  static Future<void> flush() async {
    final f = _file;
    if (f == null) return;
    try {
      // buffer 已经在写入时实时 append,这里只是保险
      await f.writeAsString('', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  /// 取当前内存日志(最新在前)
  static List<String> snapshot() {
    return _buffer.reversed.toList();
  }

  /// 取文件路径(供用户在 adb 里 cat)
  static Future<String?> filePath() async {
    if (_file == null) await _init();
    return _file?.path;
  }
}
