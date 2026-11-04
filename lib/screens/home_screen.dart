import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../core/app_log.dart';
import '../core/app_models.dart';
import '../core/app_scope.dart';
import '../core/app_theme.dart';
import '../data/api_client.dart';
import '../widgets/media_cards.dart';
import '../widgets/poster_artwork.dart';
import '../widgets/cinema_surface.dart';
import '../widgets/reference_chrome.dart';
import 'catalog_screen.dart';
import 'detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.initialFeed,
    required this.onOpenSearch,
    required this.onOpenProfile,
    this.onFeaturedChanged,
  });

  final HomeFeed? initialFeed;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenProfile;
  final ValueChanged<VodItem>? onFeaturedChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeFeed? _feed;
  ApiException? _error;
  bool _loading = false;
  MediaKind? _filter;
  int _featuredIndex = 0;
  bool _anime = false;

  @override
  void initState() {
    super.initState();
    _feed = widget.initialFeed;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _refresh(silent: _feed != null),
    );
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final services = AppScope.of(context);
    final apiBase = services.settings.baseUrl;
    try {
      final feed = await services.api.fetchHome();
      // /api/home can currently contain unresolved rows whose mediaType is null.
      // If that leaves too few usable rows, fill from the typed catalog endpoints
      // rather than mislabelling series as movies or scraping filenames locally.
      var merged = feed;
      if (mounted && services.settings.baseUrl == apiBase) {
        setState(() => _feed = feed);
      }
      final resolved = feed.all.where((item) => item.isResolved).length;
      final needMovies =
          resolved < 8 ||
          !feed.all.any((item) => item.mediaType == MediaKind.movie);
      final needSeries =
          resolved < 8 ||
          !feed.all.any((item) => item.mediaType == MediaKind.tv);
      if (needMovies || needSeries) {
        final extra = await Future.wait([
          needMovies
              ? services.api
                    .fetchList(MediaKind.movie)
                    .then((page) => page.items)
                    .catchError((Object _) => <VodItem>[])
              : Future.value(<VodItem>[]),
          needSeries
              ? services.api
                    .fetchList(MediaKind.tv)
                    .then((page) => page.items)
                    .catchError((Object _) => <VodItem>[])
              : Future.value(<VodItem>[]),
        ]);
        merged = _mergeHome(feed, [extra[0], extra[1]]);
      }
      if (!mounted || services.settings.baseUrl != apiBase) return;
      await services.homeCache.write(services.settings, merged);
      if (!mounted) return;
      setState(() {
        _feed = merged;
        _loading = false;
      });
      if (_filteredAll.isNotEmpty) {
        widget.onFeaturedChanged?.call(_filteredAll.first);
      }
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
    final merged = all
        .where((item) => item.isResolved && seen.add(item.identityKey))
        .toList(growable: false);
    return HomeFeed(
      fourK: merged,
      latest: original.latest.any((item) => item.isResolved)
          ? original.latest
          : merged,
      stats: original.stats,
    );
  }

  List<VodItem> get _filteredAll {
    final feed = _feed;
    if (feed == null) return const [];
    return feed.all
        .where((item) => item.isResolved)
        .where((item) => _filter == null || item.mediaType == _filter)
        .where(
          (item) =>
              !_anime ||
              item.genres.any((g) => ['动画', '动漫', 'Animation'].contains(g)),
        )
        .toList(growable: false);
  }

  List<VodItem> get _movies => _filteredAll
      .where((item) => item.mediaType == MediaKind.movie)
      .toList(growable: false);

  List<VodItem> get _series => _filteredAll
      .where((item) => item.mediaType == MediaKind.tv)
      .toList(growable: false);

  List<VodItem> get _latest {
    final feed = _feed;
    if (feed == null) return const [];
    return uniqueTitles(
      feed.latest
          .where((item) => item.isResolved)
          .where((item) => _filter == null || item.mediaType == _filter)
          .toList(growable: false),
    );
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
    final all = _filteredAll;
    final hero = all.isEmpty
        ? null
        : all[_featuredIndex.clamp(0, all.take(5).length - 1)];
    final child = Builder(builder: (context) => _buildHome(context, hero));
    return PosterTone.exists(context)
        ? child
        : PosterSurface(imageUrl: hero?.poster ?? hero?.backdrop, child: child);
  }

  void _category(int index) {
    setState(() {
      _filter = index == 1
          ? MediaKind.movie
          : index == 2
          ? MediaKind.tv
          : null;
      _anime = index == 3;
      _featuredIndex = 0;
    });
    if (_filteredAll.isNotEmpty) {
      widget.onFeaturedChanged?.call(_filteredAll.first);
    }
  }

  Widget _buildHome(BuildContext context, VodItem? hero) {
    final services = AppScope.of(context);
    final featured = _filteredAll.take(5).toList();
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width >= 900 ? 48.0 : 16.0;
    final heroHeight = width >= 900
        ? 600.0
        : width * 0.97 + MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: heroHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hero != null)
                      PageView.builder(
                        itemCount: featured.length,
                        key: ValueKey('$_filter-$_anime'),
                        onPageChanged: (index) {
                          setState(() => _featuredIndex = index);
                          widget.onFeaturedChanged?.call(featured[index]);
                        },
                        itemBuilder: (_, index) =>
                            FeaturePoster(item: featured[index], faded: true),
                      ),
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontal + 6,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            ReferenceHeader(
                              onSearch: widget.onOpenSearch,
                              onMore: widget.onOpenProfile,
                            ),
                            const SizedBox(height: 14),
                            ReferenceTabs(
                              labels: const ['推荐', '电影', '电视剧', '动漫'],
                              selected: _anime
                                  ? 3
                                  : _filter == MediaKind.movie
                                  ? 1
                                  : _filter == MediaKind.tv
                                  ? 2
                                  : 0,
                              onSelected: _category,
                              light: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: horizontal,
                      right: horizontal,
                      bottom: 4,
                      child: hero == null
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: Column(
                                children: [
                                  Text(
                                    _loading ? '正在读取片库…' : '暂时没有影片',
                                    style: const TextStyle(fontSize: 22),
                                  ),
                                  if (_error != null) Text(_error!.userMessage),
                                ],
                              ),
                            )
                          : Column(
                              children: [
                                FeatureTitle(item: hero, height: 62),
                                const SizedBox(height: 8),
                                Text(
                                  [
                                    if (hero.genres.isNotEmpty)
                                      hero.genres.first,
                                    if (hero.isTv) '第1季',
                                    if (hero.coverage?.expected != null &&
                                        hero.coverage!.expected > 0)
                                      '全${hero.coverage!.expected}集',
                                    if (hero.isTv == false && hero.year != null)
                                      '${hero.year}',
                                  ].join(' · '),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: CinemaColors.text,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (var i = 0; i < featured.length; i++)
                                      Container(
                                        width: 6,
                                        height: 6,
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: i == _featuredIndex
                                              ? Colors.white
                                              : Colors.white.withValues(
                                                  alpha: 0.32,
                                                ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 30,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: SizedBox(
                                          height: 40,
                                          child: FilledButton.icon(
                                            style: FilledButton.styleFrom(
                                              backgroundColor: Colors.white,
                                              foregroundColor:
                                                  CinemaColors.text,
                                            ),
                                            onPressed: () =>
                                                _open(hero, autoPlay: true),
                                            icon: const Icon(
                                              CupertinoIcons.play_fill,
                                              size: 21,
                                            ),
                                            label: const Text(
                                              '立即播放',
                                              style: TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 9),
                                      AnimatedBuilder(
                                        animation: services.store,
                                        builder: (context, _) => SizedBox(
                                          width: 40,
                                          height: 40,
                                          child: CinemaGlass(
                                            radius: 22,
                                            child: IconButton(
                                              tooltip: '收藏',
                                              padding: EdgeInsets.zero,
                                              onPressed: () => services.store
                                                  .toggleFavorite(hero),
                                              icon: Icon(
                                                services.store.isFavoriteItem(
                                                      hero,
                                                    )
                                                    ? CupertinoIcons.heart_fill
                                                    : CupertinoIcons.heart,
                                                size: 25,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CinemaGlass(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(child: Text(_error!.userMessage)),
                        TextButton(
                          onPressed: () => _refresh(),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: AnimatedBuilder(
                animation: services.store,
                builder: (context, _) {
                  final records = services.store.history.take(5).toList();
                  if (records.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '继续观看',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 74,
                          child: PageView.builder(
                            itemCount: records.length,
                            itemBuilder: (context, index) => ContinueCard(
                              record: records[index],
                              onTap: () => _open(
                                records[index].toItem(),
                                autoPlay: true,
                              ),
                              onRemove: () => services.store
                                  .removeHistoryRecord(records[index].itemKey),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            SliverToBoxAdapter(child: _row('为你推荐', _filteredAll, horizontal)),
            if (_movies.isNotEmpty)
              SliverToBoxAdapter(
                child: _row('电影', _movies, horizontal, kind: MediaKind.movie),
              ),
            if (_series.isNotEmpty)
              SliverToBoxAdapter(
                child: _row('电视剧', _series, horizontal, kind: MediaKind.tv),
              ),
            if (_latest.isNotEmpty)
              SliverToBoxAdapter(child: _row('最新上线', _latest, horizontal)),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _row(
    String title,
    List<VodItem> items,
    double horizontal, {
    MediaKind? kind,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    final tileWidth =
        (MediaQuery.sizeOf(context).width - 2 * horizontal - 12) / 3;
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontal, 20, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: kind == null ? null : () => _openCatalog(kind),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(CupertinoIcons.chevron_right, size: 18),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: tileWidth * 1.5 + 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) => MediaCard(
                item: items[index],
                width: tileWidth,
                onTap: () => _open(items[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
