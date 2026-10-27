import 'package:flutter/material.dart';

import '../core/app_log.dart';
import '../core/app_models.dart';
import '../core/app_scope.dart';
import '../core/app_theme.dart';
import '../data/api_client.dart';
import '../widgets/media_cards.dart';
import '../widgets/poster_artwork.dart';
import 'catalog_screen.dart';
import 'detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.initialFeed,
    required this.onOpenSearch,
    required this.onOpenProfile,
  });

  final HomeFeed? initialFeed;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenProfile;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeFeed? _feed;
  ApiException? _error;
  bool _loading = false;
  MediaKind? _filter;

  @override
  void initState() {
    super.initState();
    _feed = widget.initialFeed;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh(silent: _feed != null));
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final services = AppScope.of(context);
    try {
      final feed = await services.api.fetchHome();
      // /api/home can currently contain unresolved rows whose mediaType is null.
      // If that leaves too few usable rows, fill from the typed catalog endpoints
      // rather than mislabelling series as movies or scraping filenames locally.
      var merged = feed;
      final resolved = feed.all.where((item) => item.isResolved).length;
      if (resolved < 8) {
        final extra = await Future.wait([
          services.api.fetchList(MediaKind.movie).then((page) => page.items).catchError((Object _) => <VodItem>[]),
          services.api.fetchList(MediaKind.tv).then((page) => page.items).catchError((Object _) => <VodItem>[]),
        ]);
        merged = _mergeHome(feed, [extra[0], extra[1]]);
      }
      await services.homeCache.write(services.settings, merged);
      if (!mounted) return;
      setState(() {
        _feed = merged;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
      if (silent && _feed != null) {
        AppLog.error('home-refresh', error);
      }
    } catch (error) {
      AppLog.error('home-refresh', error);
      if (!mounted) return;
      setState(() {
        _error = ApiException(
          ApiFailureKind.protocol,
          error.toString(),
          endpoint: '/api/home',
        );
        _loading = false;
      });
    }
  }

  HomeFeed _mergeHome(HomeFeed original, List<List<VodItem>> additions) {
    final seen = <String>{};
    final all = [
      ...original.fourK,
      ...original.latest,
      for (final group in additions) ...group,
    ];
    final merged = all.where((item) => item.isResolved && seen.add(item.key)).toList(growable: false);
    return HomeFeed(
      fourK: merged,
      latest: merged.reversed.toList(growable: false),
      stats: original.stats,
    );
  }

  List<VodItem> get _filteredAll {
    final feed = _feed;
    if (feed == null) return const [];
    return feed.all
        .where((item) => item.isResolved)
        .where((item) => _filter == null || item.mediaType == _filter)
        .toList(growable: false);
  }

  List<VodItem> get _movies =>
      _filteredAll.where((item) => item.mediaType == MediaKind.movie).toList(growable: false);

  List<VodItem> get _series =>
      _filteredAll.where((item) => item.mediaType == MediaKind.tv).toList(growable: false);

  List<VodItem> get _latest {
    final feed = _feed;
    if (feed == null) return const [];
    return feed.latest
        .where((item) => item.isResolved)
        .where((item) => _filter == null || item.mediaType == _filter)
        .toList(growable: false);
  }

  Future<void> _open(VodItem item, {bool autoPlay = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetailScreen(item: item, autoPlay: autoPlay),
      ),
    );
  }

  Future<void> _openCatalog(MediaKind kind) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CatalogScreen(
          kind: kind,
          title: kind == MediaKind.tv ? '电视剧' : '电影',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final all = _filteredAll;
    final hero = all.isEmpty ? null : all.first;
    final mediaSize = MediaQuery.sizeOf(context);
    final width = mediaSize.width;
    final wide = width >= 900;
    final heroHeight = wide ? 520.0 : (mediaSize.height < 700 ? 430.0 : 470.0);
    return Scaffold(
      backgroundColor: CinemaColors.background,
      body: RefreshIndicator(
        color: CinemaColors.red,
        backgroundColor: CinemaColors.elevated,
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Stack(
                children: [
                  if (hero != null)
                    SizedBox(
                      height: heroHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          BackdropArtwork(item: hero),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0xB307080B),
                                  Color(0x2207080B),
                                  CinemaColors.background,
                                ],
                                stops: [0, 0.45, 1],
                              ),
                            ),
                          ),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [Color(0x9907080B), Colors.transparent],
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    const SizedBox(height: 260),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: wide ? 52 : 20),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: hero == null
                            ? _emptyHero()
                            : _heroContent(services, hero),
                      ),
                    ),
                  ),
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(wide ? 36 : 10, 4, wide ? 36 : 10, 0),
                      child: Row(
                        children: [
                          if (wide) const _SideBrand(),
                          if (!wide)
                            const Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Text(
                                  '影院',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.6,
                                  ),
                                ),
                              ),
                            ),
                          const Spacer(),
                          IconButton(
                            tooltip: '搜索',
                            onPressed: widget.onOpenSearch,
                            icon: const Icon(Icons.search_rounded, size: 25),
                          ),
                          IconButton(
                            tooltip: '我的',
                            onPressed: widget.onOpenProfile,
                            icon: const Icon(Icons.person_outline_rounded, size: 24),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(wide ? 52 : 18, 12, wide ? 52 : 18, 0),
                child: Row(
                  children: [
                    _FilterChip(
                      label: '精选',
                      selected: _filter == null,
                      onTap: () => setState(() => _filter = null),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: '电影',
                      selected: _filter == MediaKind.movie,
                      onTap: () => setState(() => _filter = MediaKind.movie),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: '电视剧',
                      selected: _filter == MediaKind.tv,
                      onTap: () => setState(() => _filter = MediaKind.tv),
                    ),
                    const Spacer(),
                    if (_error != null)
                      IconButton(
                        tooltip: '刷新失败，点击重试',
                        onPressed: () => _refresh(),
                        icon: const Icon(Icons.cloud_off_rounded, color: CinemaColors.red, size: 20),
                      ),
                  ],
                ),
              ),
            ),
            if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(wide ? 52 : 18, 12, wide ? 52 : 18, 0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF291416),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _feed == null
                                ? _error!.userMessage
                                : '${_error!.userMessage} 正在显示上次缓存。',
                            style: const TextStyle(color: Color(0xFFFFB9B9), fontSize: 12, height: 1.45),
                          ),
                        ),
                        TextButton(onPressed: () => _refresh(), child: const Text('重试')),
                      ],
                    ),
                  ),
                ),
              ),
            if (services.store.history.isNotEmpty)
              SliverToBoxAdapter(
                child: AnimatedBuilder(
                  animation: services.store,
                  builder: (context, _) {
                    final history = services.store.history.take(10).toList();
                    return _Section(
                      title: '继续观看',
                      horizontalPadding: wide ? 52 : 18,
                      child: SizedBox(
                        height: 86,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: history.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final record = history[index];
                            return ContinueCard(
                              record: record,
                              onTap: () => _open(record.toItem(), autoPlay: true),
                              onRemove: () async {
                                await services.store.removeHistoryRecord(record.itemKey);
                              },
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            SliverToBoxAdapter(
              child: _PosterSection(
                title: '电影',
                items: _movies,
                onMore: () => _openCatalog(MediaKind.movie),
                onItemTap: (item) => _open(item),
                horizontalPadding: wide ? 52 : 18,
              ),
            ),
            SliverToBoxAdapter(
              child: _PosterSection(
                title: '电视剧',
                items: _series,
                onMore: () => _openCatalog(MediaKind.tv),
                onItemTap: (item) => _open(item),
                horizontalPadding: wide ? 52 : 18,
              ),
            ),
            SliverToBoxAdapter(
              child: _PosterSection(
                title: switch (_filter) {
                  MediaKind.movie => '最新电影',
                  MediaKind.tv => '最新剧集',
                  _ => '最新上线',
                },
                items: _latest,
                onMore: _filter == null ? null : () => _openCatalog(_filter!),
                onItemTap: (item) => _open(item),
                horizontalPadding: wide ? 52 : 18,
              ),
            ),
            if (_loading && _feed == null)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        ),
      ),
    );
  }

  Widget _heroContent(AppServices services, VodItem hero) {
    final meta = <String>[
      if (hero.year != null) '${hero.year}',
      hero.typeLabel,
      if (hero.score.isNotEmpty) '评分 ${hero.score}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 5,
          children: [for (final value in meta) _MetaLabel(value)],
        ),
        const SizedBox(height: 10),
        Text(
          hero.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: MediaQuery.sizeOf(context).width >= 900 ? 54 : 42,
            height: 1.06,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.2,
            shadows: const [Shadow(color: Colors.black87, blurRadius: 14)],
          ),
        ),
        const SizedBox(height: 12),
        if (hero.remarks.isNotEmpty)
          Text(
            hero.remarks.first,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFD3D6DD), fontSize: 12),
          ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              height: 45,
              width: 142,
              child: FilledButton.icon(
                onPressed: () => _open(hero, autoPlay: true),
                icon: const Icon(Icons.play_arrow_rounded, size: 23),
                label: const Text('播放'),
              ),
            ),
            SizedBox(
              height: 45,
              child: AnimatedBuilder(
                animation: services.store,
                builder: (context, _) {
                  final favorite = services.store.isFavorite(hero.key);
                  return OutlinedButton.icon(
                    onPressed: () => services.store.toggleFavorite(hero),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: const Color(0x44000000),
                    ),
                    icon: Icon(favorite ? Icons.check_rounded : Icons.add_rounded, size: 20),
                    label: Text(favorite ? '已加入片单' : '我的片单'),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _emptyHero() {
    return Container(
      height: 230,
      alignment: Alignment.bottomLeft,
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '影院',
            style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: -1),
          ),
          const SizedBox(height: 8),
          Text(
            _loading
                ? '正在读取影视库…'
                : '影视库暂时没有可显示的作品。类型资料未补齐的条目不会进入精选，避免把剧集误标为电影。',
            style: const TextStyle(color: CinemaColors.muted, height: 1.45),
          ),
          if (!_loading)
            TextButton(onPressed: () => _refresh(), child: const Text('重新加载')),
        ],
      ),
    );
  }
}

class _PosterSection extends StatelessWidget {
  const _PosterSection({
    required this.title,
    required this.items,
    required this.onMore,
    required this.onItemTap,
    required this.horizontalPadding,
  });

  final String title;
  final List<VodItem> items;
  final VoidCallback? onMore;
  final ValueChanged<VodItem> onItemTap;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return _Section(
      title: title,
      horizontalPadding: horizontalPadding,
      action: onMore == null ? null : TextButton(onPressed: onMore, child: const Text('更多')),
      child: SizedBox(
        height: 250,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, index) => MediaCard(
            item: items[index],
            onTap: () => onItemTap(items[index]),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    required this.horizontalPadding,
    this.action,
  });

  final String title;
  final Widget child;
  final double horizontalPadding;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 22, horizontalPadding, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const Spacer(),
              ?action,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.white : const Color(0x66171A20),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? Colors.white : const Color(0x333F4653),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : CinemaColors.muted,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _MetaLabel extends StatelessWidget {
  const _MetaLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0x44000000),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11, color: Color(0xFFE5E7EB))),
    );
  }
}

class _SideBrand extends StatelessWidget {
  const _SideBrand();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Text('CINEMA', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: 2.2)),
        SizedBox(width: 8),
        Text('影院', style: TextStyle(fontSize: 13, color: CinemaColors.muted)),
      ],
    );
  }
}
