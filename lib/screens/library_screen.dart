import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/app_theme.dart';
import '../data/local_store.dart';
import '../widgets/media_cards.dart';
import '../widgets/poster_artwork.dart';
import 'detail_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: wide
              ? const Text('我的片单', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800))
              : const Text('我的片单'),
          leading: wide ? const SizedBox(width: 52) : null,
          automaticallyImplyLeading: !wide,
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: CinemaColors.red,
            labelColor: CinemaColors.text,
            unselectedLabelColor: CinemaColors.muted,
            tabs: [
              Tab(text: '收藏'),
              Tab(text: '观看记录'),
            ],
          ),
        ),
        body: AnimatedBuilder(
          animation: services.store,
          builder: (context, _) {
            return TabBarView(
              children: [
                _FavoritesTab(store: services.store),
                _HistoryTab(store: services.store),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FavoritesTab extends StatelessWidget {
  const _FavoritesTab({required this.store});

  final LocalStore store;

  @override
  Widget build(BuildContext context) {
    final items = store.favorites;
    if (items.isEmpty) {
      return const _Empty(
        icon: Icons.bookmark_border_rounded,
        title: '片单还是空的',
        message: '在作品详情或首页加入片单，之后可以从这里继续找片。',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 176,
        mainAxisSpacing: 22,
        crossAxisSpacing: 12,
        childAspectRatio: 0.56,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final saved = items[index];
        return MediaCard(
          item: saved.toItem(),
          width: double.infinity,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => DetailScreen(item: saved.toItem())),
          ),
        );
      },
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.store});

  final LocalStore store;

  @override
  Widget build(BuildContext context) {
    final records = store.history;
    if (records.isEmpty) {
      return const _Empty(
        icon: Icons.history_rounded,
        title: '还没有观看记录',
        message: '开始播放后，进度会保存在本机。连接不同设备后的同步服务尚未接入。',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      itemCount: records.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == records.length) {
          return Center(
            child: TextButton(
              onPressed: () => _confirmClear(context),
              child: const Text('清空观看记录'),
            ),
          );
        }
        final record = records[index];
        return Material(
          color: CinemaColors.elevated,
          borderRadius: BorderRadius.circular(9),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DetailScreen(item: record.toItem(), autoPlay: true),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    height: 62,
                    child: PosterArtwork(item: record.toItem(), compact: true, borderRadius: 6),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (record.episodeText.isNotEmpty) record.episodeText,
                            record.completed ? '已播完' : '${(record.progress * 100).round()}%',
                            record.lineGroup,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: CinemaColors.muted, fontSize: 11),
                        ),
                        const SizedBox(height: 7),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: record.progress,
                            minHeight: 3,
                            backgroundColor: Colors.white12,
                            color: CinemaColors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '移除记录',
                    onPressed: () => store.removeHistoryRecord(record.itemKey),
                    icon: const Icon(Icons.close_rounded, size: 17, color: CinemaColors.faint),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空观看记录？'),
        content: const Text('只清除本机的观看进度，不删除夸克文件或影视接口数据。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('清空')),
        ],
      ),
    );
    if (confirmed == true) await store.clearHistory();
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: CinemaColors.faint),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: CinemaColors.muted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
