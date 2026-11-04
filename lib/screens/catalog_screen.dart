import 'package:flutter/material.dart';

import '../core/app_log.dart';
import '../core/app_models.dart';
import '../core/app_scope.dart';
import '../core/app_theme.dart';
import '../data/api_client.dart';
import '../widgets/media_cards.dart';
import '../widgets/reference_chrome.dart';
import 'detail_screen.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.kind,
    required this.title,
    this.embedded = false,
    this.onSearch,
    this.onMore,
  });

  final MediaKind kind;
  final String title;
  final bool embedded;
  final VoidCallback? onSearch;
  final VoidCallback? onMore;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final List<VodItem> _items = [];
  ApiException? _error;
  bool _loading = true;
  bool _loadingMore = false;
  int _page = 1;
  int _pageCount = 1;
  int _requestGeneration = 0;
  String? _genre;
  int? _year;
  bool _sortByYear = false;
  late MediaKind _kind;
  bool _anime = false;

  List<VodItem> get _visible {
    final items = _items
        .where(
          (item) =>
              (_genre == null || item.genres.contains(_genre)) &&
              (_year == null || item.year == _year) &&
              (!_anime ||
                  item.genres.any(
                    (g) => ['动画', '动漫', 'Animation'].contains(g),
                  )),
        )
        .toList();
    if (_sortByYear) items.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
    return items;
  }

  @override
  void initState() {
    super.initState();
    _kind = widget.kind;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFirst());
  }

  Future<void> _loadFirst() async {
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
    });
    try {
      final value = await AppScope.of(context).api.fetchList(_kind, page: 1);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _items
          ..clear()
          ..addAll(uniqueTitles(value.items));
        _page = value.page;
        _pageCount = value.pageCount;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    } catch (error) {
      AppLog.error('catalog', error);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _error = ApiException(
          ApiFailureKind.protocol,
          error.toString(),
          endpoint: '/api/list',
        );
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _page >= _pageCount) return;
    final generation = _requestGeneration;
    setState(() => _loadingMore = true);
    try {
      final value = await AppScope.of(context).api
          .fetchList(_kind, page: _page + 1);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        final merged = uniqueTitles([..._items, ...value.items]);
        _items
          ..clear()
          ..addAll(merged);
        _page = value.page;
        _pageCount = value.pageCount;
        _loadingMore = false;
      });
    } on ApiException catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.userMessage)));
    }
  }

  void _open(VodItem item) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => DetailScreen(item: item)));
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final genres = _items.expand((item) => item.genres).toSet().toList()
      ..sort();
    final years =
        _items.map((item) => item.year).whereType<int>().toSet().toList()
          ..sort((a, b) => b.compareTo(a));
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          if (widget.embedded)
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 14),
                child: ReferenceHeader(
                  onSearch: widget.onSearch!,
                  onMore: widget.onMore!,
                ),
              ),
            )
          else
            ReferencePageHeader(title: widget.title),
          if (widget.embedded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: ReferenceTabs(
                labels: const ['电影', '电视剧', '动漫'],
                selected: _anime
                    ? 2
                    : _kind == MediaKind.tv
                    ? 1
                    : 0,
                onSelected: (index) {
                  if (_loading) return;
                  setState(() {
                    _kind = index == 0 ? MediaKind.movie : MediaKind.tv;
                    _anime = index == 2;
                    _genre = null;
                    _year = null;
                  });
                  _loadFirst();
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Row(
              children: [
                const Icon(Icons.tune_rounded, size: 18),
                const SizedBox(width: 10),
                PopupMenuButton<String>(
                  initialValue: _genre ?? '',
                  onSelected: (value) =>
                      setState(() => _genre = value.isEmpty ? null : value),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: '', child: Text('全部类型')),
                    for (final genre in genres)
                      PopupMenuItem(value: genre, child: Text(genre)),
                  ],
                  child: _filterLabel(_genre ?? '类型'),
                ),
                const SizedBox(width: 10),
                PopupMenuButton<int>(
                  initialValue: _year ?? 0,
                  onSelected: (value) =>
                      setState(() => _year = value == 0 ? null : value),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 0, child: Text('全部年份')),
                    for (final year in years)
                      PopupMenuItem(value: year, child: Text('$year')),
                  ],
                  child: _filterLabel(_year?.toString() ?? '年份'),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => setState(() => _sortByYear = !_sortByYear),
                  child: _filterLabel(_sortByYear ? '最新年份' : '排序'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _CatalogError(
                    message: _error!.userMessage,
                    onRetry: _loadFirst,
                  )
                : RefreshIndicator(
                    onRefresh: _loadFirst,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount:
                                      MediaQuery.sizeOf(context).width >= 900
                                      ? 6
                                      : 3,
                                  mainAxisSpacing: 14,
                                  crossAxisSpacing: 7,
                                  childAspectRatio: 0.52,
                                ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => MediaCard(
                                item: visible[index],
                                width: double.infinity,
                                onTap: () => _open(visible[index]),
                              ),
                              childCount: visible.length,
                            ),
                          ),
                        ),
                        if (visible.isEmpty)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(28),
                              child: Text('当前结果中没有符合条件的影片'),
                            ),
                          ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
                            child: Column(
                              children: [
                                if (_genre != null || _year != null || _anime)
                                  const Text(
                                    '筛选当前已读取的影片',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: CinemaColors.muted,
                                    ),
                                  ),
                                if (_page < _pageCount)
                                  TextButton(
                                    onPressed: _loadingMore ? null : _loadMore,
                                    child: Text(_loadingMore ? '加载中…' : '加载更多'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterLabel(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.32),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text('$label ⌄', style: const TextStyle(fontSize: 12)),
  );
}

class _CatalogError extends StatelessWidget {
  const _CatalogError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: CinemaColors.faint,
              size: 40,
            ),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
