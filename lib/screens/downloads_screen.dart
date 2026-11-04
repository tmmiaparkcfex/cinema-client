import 'dart:io';

import 'package:flutter/material.dart';

import '../core/app_models.dart';
import '../core/app_scope.dart';
import '../core/app_theme.dart';
import '../core/episode_choice.dart';
import '../data/download_manager.dart';
import '../player/playback_screen.dart';
import '../widgets/poster_artwork.dart';
import '../widgets/cinema_surface.dart';
import '../widgets/reference_chrome.dart';

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
    final image = manager?.jobs.firstOrNull?.item.poster;
    return PosterSurface(
      imageUrl: image,
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            children: [
              const ReferencePageHeader(title: '我的下载'),
              if (manager == null)
                const Expanded(child: Center(child: Text('下载服务尚未初始化')))
              else
                Expanded(
                  child: AnimatedBuilder(
                    animation: manager,
                    builder: (context, _) {
                      final active = manager.jobs
                          .where((job) => job.state != DownloadState.complete)
                          .toList();
                      final complete = manager.jobs
                          .where((job) => job.state == DownloadState.complete)
                          .toList();
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: CinemaGlass(
                              radius: 24,
                              child: TabBar(
                                dividerColor: Colors.transparent,
                                indicatorSize: TabBarIndicatorSize.tab,
                                indicator: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                tabs: [
                                  Tab(text: '下载中 (${active.length})'),
                                  Tab(text: '已完成 (${complete.length})'),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _jobs(context, manager, active),
                                _jobs(context, manager, complete),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _jobs(
    BuildContext context,
    DownloadManager manager,
    List<DownloadJob> jobs,
  ) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
    children: [
      if (jobs.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 120),
          child: Column(
            children: [
              Icon(
                Icons.download_outlined,
                size: 44,
                color: CinemaColors.muted,
              ),
              SizedBox(height: 16),
              Text('还没有下载'),
              SizedBox(height: 8),
              Text(
                '从影片详情选择剧集或版本',
                style: TextStyle(color: CinemaColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      for (final job in jobs)
        Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                job.item.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 125,
                    height: 76,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: BackdropArtwork(item: job.item),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          job.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_size(job.received)} / ${_size(job.resource.sizeBytes)} · ${job.stateLabel}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: CinemaColors.muted,
                          ),
                        ),
                        const SizedBox(height: 9),
                        LinearProgressIndicator(
                          value: job.progress,
                          minHeight: 3,
                          color: CinemaColors.accent,
                          backgroundColor: Colors.white38,
                        ),
                        if (job.error != null)
                          Text(
                            job.error!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF994632),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: job.state == DownloadState.complete
                        ? '播放下载'
                        : '暂停或继续',
                    onPressed: () => job.state == DownloadState.complete
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
                          ? Icons.play_circle_outline_rounded
                          : [
                              DownloadState.queued,
                              DownloadState.preparing,
                              DownloadState.downloading,
                            ].contains(job.state)
                          ? Icons.pause_circle_outline_rounded
                          : Icons.arrow_circle_down_outlined,
                      color: CinemaColors.accent,
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _remove(context, manager, job),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('删除', style: TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ),
        ),
      if (jobs.isNotEmpty)
        const Text(
          '请保持应用在前台。播放或切到后台会暂停下载。',
          style: TextStyle(fontSize: 12, color: CinemaColors.muted),
        ),
    ],
  );

  static String _size(int bytes) => bytes >= 1024 * 1024 * 1024
      ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
