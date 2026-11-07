import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_models.dart';
import 'rex_catalog.dart';
import 'rex_metadata.dart';
import 'rex_theme.dart';
import 'rex_widgets.dart';

class RexHome extends StatefulWidget {
  const RexHome({
    super.key,
    required this.catalog,
    required this.onOpen,
    required this.onBrowse,
  });
  final RexCatalog catalog;
  final ValueChanged<VodItem> onOpen;
  final void Function(
    String title,
    List<VodItem> items,
    MediaKind? kind,
    String? category,
    String? studio,
  )
  onBrowse;
  @override
  State<RexHome> createState() => _RexHomeState();
}

class _RexHomeState extends State<RexHome> {
  final _pager = PageController();
  int _hero = 0;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 7), (_) {
      final n = widget.catalog.items.take(10).length;
      if (mounted &&
          n > 1 &&
          _pager.hasClients &&
          !MediaQuery.disableAnimationsOf(context) &&
          ModalRoute.of(context)?.isCurrent == true) {
        _pager.animateToPage(
          (_hero + 1) % n,
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.catalog,
    builder: (context, _) {
      final all = widget.catalog.items;
      if (all.isEmpty && widget.catalog.loading) {
        return const Center(child: CupertinoActivityIndicator(radius: 13));
      }
      if (all.isEmpty) {
        return Center(
          child: RexEmpty(
            '暂时无法加载影片',
            subtitle: widget.catalog.error?.userMessage,
            onRetry: widget.catalog.refresh,
          ),
        );
      }
      final heroes = all.take(10).toList();
      final movies = all.where((v) => v.mediaType == MediaKind.movie).toList();
      final tv = all.where((v) => v.mediaType == MediaKind.tv).toList();
      final variety = all
          .where(
            (v) =>
                v.categories.any((c) => c.contains('综艺') || c.contains('真人秀')),
          )
          .toList();
      final animation = all
          .where((v) => v.categories.any((c) => c.contains('动画')))
          .toList();
      final categories = all
          .expand((v) => v.categories)
          .toSet()
          .take(8)
          .toList();
      final studios = all.expand((v) => v.studios).toSet().take(10).toList();
      return RefreshIndicator(
        onRefresh: widget.catalog.refresh,
        color: RexColors.purple,
        child: CustomScrollView(
          key: const PageStorageKey('rex-home-scroll'),
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: math.max(
                  500,
                  math.min(700, MediaQuery.sizeOf(context).height * .70),
                ),
                child: Stack(
                  children: [
                    PageView.builder(
                      controller: _pager,
                      itemCount: heroes.length,
                      onPageChanged: (i) => setState(() => _hero = i),
                      itemBuilder: (context, i) => _HeroFeature(
                        item: heroes[i],
                        onTap: () => widget.onOpen(heroes[i]),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: RexDots(
                          count: heroes.length,
                          index: _hero.clamp(0, heroes.length - 1),
                          onSelect: (i) => _pager.animateToPage(
                            i,
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.catalog.error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '更新暂未完成，正在显示已加载的内容',
                          style: TextStyle(
                            color: RexColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      CupertinoButton(
                        onPressed: widget.catalog.refresh,
                        child: const Text('重试', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ),
            for (final section in [
              ('正在热映', movies, MediaKind.movie, false),
              ('正在播出', tv, MediaKind.tv, false),
              ('本周趋势', all, null, true),
              ('近一月 · 热门综艺', variety, MediaKind.tv, true),
              ('今日动漫', animation, null, false),
            ])
              if (section.$2.isNotEmpty)
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      RexHeading(
                        section.$1,
                        onMore: () => widget.onBrowse(
                          section.$1,
                          section.$2,
                          section.$3,
                          null,
                          null,
                        ),
                      ),
                      RexPosterRow(
                        items: section.$2.take(12).toList(),
                        onOpen: widget.onOpen,
                        wide: section.$4,
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
            if (categories.isNotEmpty)
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    const RexHeading('分类浏览'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final category in categories)
                            SizedBox(
                              width:
                                  (math.min(
                                        MediaQuery.sizeOf(context).width,
                                        900,
                                      ) -
                                      48) /
                                  2,
                              child: CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: () => widget.onBrowse(
                                  category,
                                  all
                                      .where(
                                        (v) => v.categories.contains(category),
                                      )
                                      .toList(),
                                  null,
                                  category,
                                  null,
                                ),
                                child: Container(
                                  height: 76,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF241B2A),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: SizedBox(
                                          width: 43,
                                          height: 60,
                                          child: RexArtwork(
                                            all
                                                .firstWhere(
                                                  (v) => v.categories.contains(
                                                    category,
                                                  ),
                                                )
                                                .posterImage,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          category,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
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
            if (studios.isNotEmpty)
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    const RexHeading('电影公司'),
                    SizedBox(
                      height: 93,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        scrollDirection: Axis.horizontal,
                        itemCount: studios.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, i) => CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => widget.onBrowse(
                            studios[i],
                            all
                                .where((v) => v.studios.contains(studios[i]))
                                .toList(),
                            null,
                            null,
                            studios[i],
                          ),
                          child: Container(
                            width: 180,
                            padding: const EdgeInsets.all(15),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF4A3B53), Color(0xFF211B2D)],
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              studios[i],
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      );
    },
  );
}

class _HeroFeature extends StatefulWidget {
  const _HeroFeature({required this.item, required this.onTap});
  final VodItem item;
  final VoidCallback onTap;
  @override
  State<_HeroFeature> createState() => _HeroFeatureState();
}

class _HeroFeatureState extends State<_HeroFeature> {
  Color _color = RexColors.background;
  @override
  void initState() {
    super.initState();
    _palette();
  }

  @override
  void didUpdateWidget(_HeroFeature oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.heroImage != widget.item.heroImage) _palette();
  }

  Future<void> _palette() async {
    final url = widget.item.heroImage;
    final color = await rexPalette(url);
    if (mounted && url == widget.item.heroImage) setState(() => _color = color);
  }

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 450),
    color: _color,
    child: LayoutBuilder(
      builder: (context, bounds) => GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: bounds.maxHeight - 80,
              child: ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, Colors.white, Colors.transparent],
                  stops: [0, .62, 1],
                ).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: RexArtwork(
                  widget.item.heroImage,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
            Positioned(
              bottom: 31,
              left: 22,
              right: 22,
              child: Column(
                children: [
                  if (widget.item.titleLogo != null)
                    SizedBox(
                      height: 82,
                      width: 270,
                      child: RexArtwork(
                        widget.item.titleLogo,
                        fit: BoxFit.contain,
                      ),
                    )
                  else
                    Text(
                      widget.item.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 35,
                        fontWeight: FontWeight.w800,
                        shadows: [
                          Shadow(color: Colors.black54, blurRadius: 16),
                        ],
                      ),
                    ),
                  const SizedBox(height: 11),
                  Text(
                    '${widget.item.categories.take(2).join(' / ')}　${dateLabel(widget.item.releaseDate, fallback: widget.item.year?.toString())}',
                    maxLines: 1,
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (widget.item.synopsis.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 9),
                      child: Text(
                        widget.item.synopsis,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11, height: 1.45),
                      ),
                    ),
                  RexRatings(widget.item),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

final _palettes = <String, Future<Color>>{};
Future<Color> rexPalette(String? url) async {
  if (url == null || !url.startsWith('http')) return RexColors.background;
  return _palettes.putIfAbsent(url, () async {
    try {
      final scheme = await ColorScheme.fromImageProvider(
        provider: NetworkImage(url),
        brightness: Brightness.dark,
      );
      return Color.lerp(scheme.primaryContainer, RexColors.background, .38)!;
    } catch (_) {
      return RexColors.background;
    }
  });
}

String dateLabel(DateTime? date, {String? fallback}) => date == null
    ? fallback ?? ''
    : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
