import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 后端地址记录
class EndpointRecord {
  final String id;
  String label;       // 用户起的名字：「家里内网」「公司公网」
  String url;
  DateTime? lastSuccessAt;
  DateTime? lastFailAt;
  String? lastFailReason;

  EndpointRecord({
    required this.id,
    required this.label,
    required this.url,
    this.lastSuccessAt,
    this.lastFailAt,
    this.lastFailReason,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'url': url,
        'last_success_at': lastSuccessAt?.millisecondsSinceEpoch,
        'last_fail_at': lastFailAt?.millisecondsSinceEpoch,
        'last_fail_reason': lastFailReason,
      };

  factory EndpointRecord.fromJson(Map<String, dynamic> j) => EndpointRecord(
        id: j['id'] as String,
        label: j['label'] as String,
        url: j['url'] as String,
        lastSuccessAt: j['last_success_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(j['last_success_at'] as int)
            : null,
        lastFailAt: j['last_fail_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(j['last_fail_at'] as int)
            : null,
        lastFailReason: j['last_fail_reason'] as String?,
      );
}

/// 后端地址管理
class EndpointStore {
  static const _kList = 'endpoint_list';
  static const _kActiveId = 'active_endpoint_id';

  Future<List<EndpointRecord>> list() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kList);
    if (raw == null || raw.isEmpty) return [];
    final arr = jsonDecode(raw) as List;
    return arr.map((e) => EndpointRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<String?> activeId() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kActiveId);
  }

  Future<EndpointRecord?> active() async {
    final all = await list();
    if (all.isEmpty) return null;
    final id = await activeId();
    if (id != null) {
      final hit = all.where((e) => e.id == id).toList();
      if (hit.isNotEmpty) return hit.first;
    }
    return all.first;
  }

  Future<void> _save(List<EndpointRecord> all) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kList,
        jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  /// 添加或更新（按 url 去重）
  Future<EndpointRecord> upsert(String label, String url) async {
    final all = await list();
    final cleanUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    final existed = all.where((e) => e.url == cleanUrl).toList();
    if (existed.isNotEmpty) {
      existed.first.label = label.trim().isEmpty ? '默认' : label.trim();
      await _save(all);
      return existed.first;
    }
    final rec = EndpointRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      label: label.trim().isEmpty ? '默认' : label.trim(),
      url: cleanUrl,
    );
    all.insert(0, rec);
    await _save(all);
    return rec;
  }

  Future<void> remove(String id) async {
    final all = await list();
    all.removeWhere((e) => e.id == id);
    await _save(all);
    final p = await SharedPreferences.getInstance();
    if (p.getString(_kActiveId) == id) {
      await p.remove(_kActiveId);
    }
  }

  Future<void> setActive(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kActiveId, id);
  }

  Future<void> markSuccess(String id) async {
    final all = await list();
    final e = all.firstWhere((e) => e.id == id, orElse: () => EndpointRecord(id: id, label: '', url: ''));
    e.lastSuccessAt = DateTime.now();
    e.lastFailAt = null;
    e.lastFailReason = null;
    await _save(all);
  }

  Future<void> markFail(String id, String reason) async {
    final all = await list();
    final e = all.firstWhere((e) => e.id == id, orElse: () => EndpointRecord(id: id, label: '', url: ''));
    e.lastFailAt = DateTime.now();
    e.lastFailReason = reason;
    await _save(all);
  }
}