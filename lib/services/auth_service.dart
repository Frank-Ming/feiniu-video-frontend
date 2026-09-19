import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 已登录账号的记录（不存密码，仅存 token + username）
class UserRecord {
  final String username;
  String token;
  String endpointId;     // 绑定到一个后端地址
  DateTime? lastLoginAt;

  UserRecord({
    required this.username,
    required this.token,
    required this.endpointId,
    this.lastLoginAt,
  });

  Map<String, dynamic> toJson() => {
        'username': username,
        'token': token,
        'endpoint_id': endpointId,
        'last_login_at': lastLoginAt?.millisecondsSinceEpoch,
      };

  factory UserRecord.fromJson(Map<String, dynamic> j) => UserRecord(
        username: j['username'] as String,
        token: j['token'] as String,
        endpointId: j['endpoint_id'] as String? ?? '',
        lastLoginAt: j['last_login_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(j['last_login_at'] as int)
            : null,
      );
}

class AuthService {
  static const _kUsers = 'user_records_v1';
  static const _kActive = 'active_user_v1';

  Future<List<UserRecord>> list() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kUsers);
    if (raw == null || raw.isEmpty) return [];
    final arr = jsonDecode(raw) as List;
    return arr.map((e) => UserRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<UserRecord?> current() async {
    final p = await SharedPreferences.getInstance();
    final user = p.getString(_kActive);
    if (user == null) return null;
    final all = await list();
    return all.where((u) => u.username == user).cast<UserRecord?>().firstWhere(
          (_) => true,
          orElse: () => null,
        );
  }

  /// 一次性保存全量
  Future<void> _save(List<UserRecord> all) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUsers,
        jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  /// 登录成功后保存（同一 username + endpointId 只存一条）
  Future<UserRecord> saveLogin({
    required String username,
    required String token,
    required String endpointId,
  }) async {
    final all = await list();
    final hit = all.where((u) => u.username == username && u.endpointId == endpointId).toList();
    if (hit.isNotEmpty) {
      hit.first.token = token;
      hit.first.lastLoginAt = DateTime.now();
      await _save(all);
      await _setActive(username);
      return hit.first;
    }
    final rec = UserRecord(
      username: username,
      token: token,
      endpointId: endpointId,
      lastLoginAt: DateTime.now(),
    );
    all.insert(0, rec);
    await _save(all);
    await _setActive(username);
    return rec;
  }

  Future<void> _setActive(String username) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kActive, username);
  }

  Future<void> setActive(String username) async {
    await _setActive(username);
  }

  Future<void> remove(String username) async {
    final all = await list();
    all.removeWhere((u) => u.username == username);
    await _save(all);
    final p = await SharedPreferences.getInstance();
    if (p.getString(_kActive) == username) {
      await p.remove(_kActive);
    }
  }

  Future<void> updateToken(String username, String newToken) async {
    final all = await list();
    for (final u in all) {
      if (u.username == username) {
        u.token = newToken;
        u.lastLoginAt = DateTime.now();
        break;
      }
    }
    await _save(all);
  }
}