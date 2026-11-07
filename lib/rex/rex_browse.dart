import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_models.dart';
import '../core/app_scope.dart';
import '../data/api_client.dart';
import 'rex_metadata.dart';
import 'rex_widgets.dart';

class RexBrowse extends StatefulWidget {
  const RexBrowse({
    super.key,
    required this.title,
    required this.initial,
    required this.onOpen,
    this.kind,
    this.category,
    this.studio,
    this.localOnly = false,
  });
  final String title;
  final List<VodItem> initial;
  final ValueChanged<VodItem> onOpen;
  final MediaKind? kind;
  final String? category, studio;
  final bool localOnly;
  @override
  State<RexBrowse> createState() => _RexBrowseState();
}

class _RexBrowseState extends State<RexBrowse> {
  late List<VodItem> _items = [...widget.initial];
  int _page = 0;
  bool _loading = false, _more = true;
  ApiException? _error;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    if (!widget.localOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading || !_more || widget.localOnly) return;
    final request = ++_request;
    final api = AppScope.of(context).api;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pages = await Future.wait([
        for (final kind
            in widget.kind == null
                ? [MediaKind.movie, MediaKind.tv]
                : [widget.kind!])
          api.fetchList(kind, page: _page + 1),
      ]);
      if (!mounted || request != _request) return;
      setState(() {
        _page++;
        _more = pages.any((v) => v.page < v.pageCount);
        _items = uniqueTitles([..._items, ...pages.expand((v) => v.items)]);
      });
    } on ApiException catch (error) {
      if (mounted && request == _request) setState(() => _error = error);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items
        .where(
          (v) =>
              (widget.category == null ||
                  v.categories.contains(widget.category)) &&
              (widget.studio == null || v.studios.contains(widget.studio)),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 17)),
        leading: RexIconButton(
          icon: CupertinoIcons.chevron_left,
          label: '返回',
          onTap: () => Navigator.pop(context),
        ),
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 500 && !_loading && _more) {
            unawaited(_load());
          }
          return false;
        },
        child: CustomScrollView(
          slivers: [
            if (items.isEmpty && !_loading)
              SliverToBoxAdapter(
                child: RexEmpty('暂时没有符合条件的作品', subtitle: _error?.userMessage),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              sliver: SliverLayoutBuilder(
                builder: (context, bounds) {
                  final columns = (bounds.crossAxisExtent / 160).floor().clamp(
                    3,
                    7,
                  );
                  final width =
                      (bounds.crossAxisExtent - (columns - 1) * 12) / columns;
                  return SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => RexPoster(
                        item: items[i],
                        width: width,
                        onTap: () => widget.onOpen(items[i]),
                      ),
                      childCount: items.length,
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 14,
                      mainAxisExtent: width * 1.5 + 49,
                    ),
                  );
                },
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(22),
                  child: CupertinoActivityIndicator(),
                ),
              ),
            if (!widget.localOnly && _more && !_loading)
              SliverToBoxAdapter(
                child: CupertinoButton(
                  onPressed: _load,
                  child: Text(_error == null ? '加载更多' : '重试'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
