import 'dart:io';

import 'package:flutter/material.dart';

import '../core/app_models.dart';
import '../core/app_scope.dart';
import '../core/app_theme.dart';
import '../core/episode_choice.dart';
import '../data/download_manager.dart';
import '../player/playback_screen.dart';
import '../widgets/poster_artwork.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  Future<void> _play(
    BuildContext context,
    DownloadManager manager,
    DownloadJob job,
  ) async {
    final path = manager.localPath(job);
    if (!await File(path).exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('本地文件已丢失，请删除记录后重新下载。')));
      }
      return;
    }
    if (!context.mounted) return;
    final entry = PlayEntry(
      label: job.label,
      apiUrl: '',
      group: '本地原画',
      resource: job.resource,
    );
    final line = MediaLine(group: '本地原画', entries: [entry]);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaybackScreen(
          detail: VodDetail(item: job.item, lines: [line]),
          initialChoice: EpisodeChoice(line: line, entry: entry),
          localPath: path,
        ),
      ),
    );
  }

  Future<void> _remove(
    BuildContext context,
    DownloadManager manager,
    DownloadJob job,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除下载？'),
        content: Text('${job.item.name} · ${job.label}\n将删除此任务及已保存的本地文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await manager.remove(job);
  }

  @override
  Widget build(BuildContext context) {
    final manager = AppScope.of(context).downloads;
    return Scaffold(
      appBar: AppBar(title: const Text('我的下载')),
      body: manager == null
          ? const Center(child: Text('下载服务尚未初始化'))
          : AnimatedBuilder(
              animation: manager,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  const Text(
                    '原画保存到本机',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '请保持应用在前台。播放影片或切到后台时会暂停下载；返回后可手动继续。',
                    style: TextStyle(color: CinemaColors.muted, height: 1.5),
                  ),
                  const SizedBox(height: 22),
                  if (manager.jobs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 90),
                      child: Column(
                        children: [
                          Icon(
                            Icons.download_outlined,
                            size: 54,
                            color: CinemaColors.faint,
                          ),
                          SizedBox(height: 16),
                          Text('还没有下载'),
                          SizedBox(height: 8),
                          Text(
                            '从影片详情选择要保存的版本或剧集。',
                            style: TextStyle(color: CinemaColors.muted),
                          ),
                        ],
                      ),
                    ),
                  for (final job in manager.jobs)
                    Card(
                      color: CinemaColors.elevated,
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 14),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 64,
                              height: 92,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: PosterArtwork(item: job.item),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    job.item.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    job.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: CinemaColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  LinearProgressIndicator(
                                    value: job.progress,
                                    minHeight: 3,
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    '${job.stateLabel} · ${_size(job.received)} / ${_size(job.resource.sizeBytes)}',
                                    style: const TextStyle(
                                      color: CinemaColors.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                  if (job.error != null)
                                    Text(
                                      job.error!,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF994632),
                                      ),
                                    ),
                                  Row(
                                    children: [
                                      TextButton.icon(
                                        onPressed: () =>
                                            job.state == DownloadState.complete
                                            ? _play(context, manager, job)
                                            : [
                                                DownloadState.queued,
                                                DownloadState.preparing,
                                                DownloadState.downloading,
                                              ].contains(job.state)
                                            ? manager.pause(job)
                                            : manager.resume(job),
                                        icon: Icon(
                                          job.state == DownloadState.complete
                                              ? Icons.play_arrow_rounded
                                              : [
                                                  DownloadState.queued,
                                                  DownloadState.preparing,
                                                  DownloadState.downloading,
                                                ].contains(job.state)
                                              ? Icons.pause_rounded
                                              : Icons.download_rounded,
                                          size: 18,
                                        ),
                                        label: Text(
                                          job.state == DownloadState.complete
                                              ? '播放'
                                              : [
                                                  DownloadState.queued,
                                                  DownloadState.preparing,
                                                  DownloadState.downloading,
                                                ].contains(job.state)
                                              ? '暂停'
                                              : '继续',
                                        ),
                                      ),
                                      const Spacer(),
                                      IconButton(
                                        tooltip: '删除下载',
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 19,
                                        ),
                                        onPressed: () =>
                                            _remove(context, manager, job),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  static String _size(int bytes) => bytes >= 1024 * 1024 * 1024
      ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
