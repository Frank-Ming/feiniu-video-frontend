/// 视频条目模型，对应后端 /api/videos 返回的字段
class VideoItem {
  final String id;
  final String name;
  final String path;
  final String fullPath;
  final int size;
  final double mtime;
  final double? duration;
  final String dir;       // 一级子目录；空表示根目录下的视频
  final bool isSeries;
  final String seriesId;
  final int episodeNo;
  final int seriesCount;
  final List<String> siblings; // 按集数排序的全部 id

  const VideoItem({
    required this.id,
    required this.name,
    required this.path,
    required this.fullPath,
    required this.size,
    required this.mtime,
    this.duration,
    this.dir = '',
    this.isSeries = false,
    this.seriesId = '',
    this.episodeNo = 0,
    this.seriesCount = 0,
    this.siblings = const [],
  });

  factory VideoItem.fromJson(Map<String, dynamic> json) {
    final sib = (json['siblings'] as List?)?.cast<String>() ?? const [];
    return VideoItem(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      fullPath: json['full_path'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      mtime: (json['mtime'] as num?)?.toDouble() ?? 0,
      duration: (json['duration'] as num?)?.toDouble(),
      dir: json['dir'] as String? ?? '',
      isSeries: json['is_series'] == true,
      seriesId: json['series_id'] as String? ?? '',
      episodeNo: (json['episode_no'] as num?)?.toInt() ?? 0,
      seriesCount: (json['series_count'] as num?)?.toInt() ?? 0,
      siblings: sib,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'full_path': fullPath,
        'size': size,
        'mtime': mtime,
        'duration': duration,
        'dir': dir,
        'is_series': isSeries,
        'series_id': seriesId,
        'episode_no': episodeNo,
        'series_count': seriesCount,
        'siblings': siblings,
      };
}

/// 后端 /api/dirs 返回的子目录条目
class DirInfo {
  final String name;
  final int count;
  const DirInfo({required this.name, required this.count});

  factory DirInfo.fromJson(Map<String, dynamic> json) =>
      DirInfo(name: json['name'] as String, count: (json['count'] as num).toInt());
}

/// 筛选条件
class VideoFilter {
  /// 选中的子目录（空表示"全部"）
  final Set<String> selectedDirs;

  /// 最大时长（秒），null 表示不限
  final double? maxSeconds;

  /// 最小时长（秒），null 表示不限
  final double? minSeconds;

  const VideoFilter({
    this.selectedDirs = const {},
    this.maxSeconds,
    this.minSeconds,
  });

  bool get isEmpty =>
      selectedDirs.isEmpty && maxSeconds == null && minSeconds == null;

  Map<String, String> toQuery() {
    final out = <String, String>{};
    if (selectedDirs.isNotEmpty) {
      out['dirs'] = selectedDirs.join(',');
    }
    if (maxSeconds != null) out['max_seconds'] = maxSeconds!.toString();
    if (minSeconds != null) out['min_seconds'] = minSeconds!.toString();
    return out;
  }
}