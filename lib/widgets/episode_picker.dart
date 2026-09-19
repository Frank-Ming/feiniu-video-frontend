import 'package:flutter/material.dart';

import '../models/video_item.dart';
import '../theme.dart';

/// 弹出短剧选集列表
Future<VideoItem?> showEpisodePicker(
    BuildContext context, List<VideoItem> episodes, String currentId) {
  return showModalBottomSheet<VideoItem>(
    context: context,
    backgroundColor: const Color(0xFF111114),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _EpisodePicker(episodes: episodes, currentId: currentId),
  );
}

class _EpisodePicker extends StatelessWidget {
  const _EpisodePicker({required this.episodes, required this.currentId});
  final List<VideoItem> episodes;
  final String currentId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                '选择集数',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                '共 ${episodes.length} 集',
                style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  childAspectRatio: 1.4,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: episodes.length,
                itemBuilder: (ctx, i) {
                  final ep = episodes[i];
                  final isCurrent = ep.id == currentId;
                  return Material(
                    color: isCurrent
                        ? AppColors.primary.withValues(alpha: 0.15)
                        : AppColors.bgElev,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => Navigator.of(context).pop(ep),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isCurrent
                                ? AppColors.primary
                                : AppColors.divider,
                          ),
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          '第${ep.episodeNo}集',
                          style: TextStyle(
                            color: isCurrent
                                ? AppColors.primary
                                : AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}