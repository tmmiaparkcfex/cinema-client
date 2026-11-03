import 'package:flutter/material.dart';

import '../core/app_log.dart';
import '../core/app_models.dart';
import '../core/app_scope.dart';
import '../core/app_theme.dart';
import '../data/api_client.dart';
import '../widgets/media_cards.dart';
import 'detail_screen.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, required this.kind, required this.title});

  final MediaKind kind;
  final String title;

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
  String? _genre;
  int? _year;
  bool _sortByYear = false;

  List<VodItem> get _visible {
    final items = _items
        .where(
          (item) =>
              (_genre == null || item.genres.contains(_genre)) &&
              (_year == null || item.year == _year),
        )
        .toList();
    if (_sortByYear) items.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
    return items;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFirst());
  }

  Future<void> _loadFirst() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await AppScope.of(context).api
          .fetchList(widget.kind, page: 1);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(uniqueTitles(value.items));
        _page = value.page;
        _pageCount = value.pageCount;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    } catch (error) {
      AppLog.error('catalog', error);
      if (!mounted) return;
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
    setState(() => _loadingMore = true);
    try {
      final value = await AppScope.of(context).api
          .fetchList(widget.kind, page: _page + 1);
      if (!mounted) return;
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
      if (!mounted) return;
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
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _CatalogError(message: _error!.userMessage, onRetry: _loadFirst)
          : RefreshIndicator(
              color: CinemaColors.accent,
              backgroundColor: CinemaColors.elevated,
              onRefresh: _loadFirst,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '已加载 ${_items.length} 部 · 当前显示 ${visible.length} 部',
                            style: const TextStyle(
                              color: CinemaColors.muted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              PopupMenuButton<String>(
                                initialValue: _genre ?? '',
                                onSelected: (value) => setState(
                                  () => _genre = value.isEmpty ? null : value,
                                ),
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: '',
                                    child: Text('全部类型'),
                                  ),
                                  for (final genre in genres)
                                    PopupMenuItem(
                                      value: genre,
                                      child: Text(genre),
                                    ),
                                ],
                                child: Chip(
                                  label: Text('${_genre ?? '全部类型'} ▾'),
                                ),
                              ),
                              PopupMenuButton<int>(
                                initialValue: _year ?? 0,
                                onSelected: (value) => setState(
                                  () => _year = value == 0 ? null : value,
                                ),
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 0,
                                    child: Text('全部年份'),
                                  ),
                                  for (final year in years)
                                    PopupMenuItem(
                                      value: year,
                                      child: Text('$year'),
                                    ),
                                ],
                                child: Chip(
                                  label: Text('${_year ?? '全部年份'} ▾'),
                                ),
                              ),
                              FilterChip(
                                label: const Text('年份从新到旧'),
                                selected: _sortByYear,
                                onSelected: (value) =>
                                    setState(() => _sortByYear = value),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '筛选范围为已加载作品，可继续加载更多。',
                            style: TextStyle(
                              color: CinemaColors.faint,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 176,
                            mainAxisSpacing: 22,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.56,
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
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
                      child: Center(
                        child: _page >= _pageCount
                            ? const Text(
                                '已经到底',
                                style: TextStyle(
                                  color: CinemaColors.faint,
                                  fontSize: 12,
                                ),
                              )
                            : OutlinedButton(
                                onPressed: _loadingMore ? null : _loadMore,
                                child: Text(_loadingMore ? '加载中…' : '加载更多'),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
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
