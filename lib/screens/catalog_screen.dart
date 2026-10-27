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
  int _total = 0;

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
      final value = await AppScope.of(context).api.fetchList(widget.kind, page: 1);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(value.items);
        _page = value.page;
        _pageCount = value.pageCount;
        _total = value.total;
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
        _error = ApiException(ApiFailureKind.protocol, error.toString(), endpoint: '/api/list');
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _page >= _pageCount) return;
    setState(() => _loadingMore = true);
    try {
      final value = await AppScope.of(context).api.fetchList(widget.kind, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _items.addAll(value.items);
        _page = value.page;
        _pageCount = value.pageCount;
        _loadingMore = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.userMessage)));
    }
  }

  void _open(VodItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DetailScreen(item: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _CatalogError(message: _error!.userMessage, onRetry: _loadFirst)
              : RefreshIndicator(
                  color: CinemaColors.red,
                  backgroundColor: CinemaColors.elevated,
                  onRefresh: _loadFirst,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                          child: Text(
                            '$_total 部已核验作品',
                            style: const TextStyle(color: CinemaColors.muted, fontSize: 12),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 176,
                            mainAxisSpacing: 22,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.56,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => MediaCard(
                              item: _items[index],
                              width: double.infinity,
                              onTap: () => _open(_items[index]),
                            ),
                            childCount: _items.length,
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
                                    style: TextStyle(color: CinemaColors.faint, fontSize: 12),
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
            const Icon(Icons.cloud_off_rounded, color: CinemaColors.faint, size: 40),
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
