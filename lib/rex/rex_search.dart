import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_models.dart';
import '../core/app_scope.dart';
import '../data/api_client.dart';
import 'rex_catalog.dart';
import 'rex_interactions.dart';
import 'rex_metadata.dart';
import 'rex_scope.dart';
import 'rex_theme.dart';
import 'rex_widgets.dart';

class RexSearch extends StatefulWidget {
  const RexSearch({
    super.key,
    required this.catalog,
    required this.onOpen,
    this.initialQuery = '',
  });
  final RexCatalog catalog;
  final ValueChanged<VodItem> onOpen;
  final String initialQuery;
  @override
  State<RexSearch> createState() => _RexSearchState();
}

class _RexSearchState extends State<RexSearch> {
  late final _query = TextEditingController(text: widget.initialQuery);
  final _focus = FocusNode();
  Timer? _debounce;
  List<VodItem> _results = [];
  String _kind = '不限', _genre = '不限', _year = '不限';
  bool _loading = false, _more = false;
  int _request = 0, _page = 0;
  ApiException? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_query.text.isNotEmpty) _search();
    });
  }

  @override
  void dispose() {
    _request++;
    _debounce?.cancel();
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _change(String value) {
    _debounce?.cancel();
    _request++;
    setState(() {
      _loading = value.trim().isNotEmpty;
      _error = null;
    });
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search({bool append = false}) async {
    final query = _query.text.trim();
    final request = ++_request;
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _loading = false;
        _more = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = AppScope.of(context).api;
    try {
      final page = await api.search(query, page: append ? _page + 1 : 1);
      if (!mounted || request != _request) return;
      final known = widget.catalog.items.where(
        (v) =>
            v.name.contains(query) ||
            v.people.any((p) => p['name']?.toString().contains(query) == true),
      );
      setState(() {
        _results = uniqueTitles([
          ...known,
          if (append) ..._results,
          ...page.items,
        ]);
        _page = page.page;
        _more = page.page < page.pageCount;
      });
    } on ApiException catch (error) {
      if (mounted && request == _request) setState(() => _error = error);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  bool _matches(VodItem item) =>
      (_kind == '不限' || item.typeLabel == _kind) &&
      (_genre == '不限' || item.categories.contains(_genre)) &&
      (_year == '不限' || item.year?.toString() == _year);
  Future<void> _filter(BuildContext anchor, String name) async {
    final data = uniqueTitles([...widget.catalog.items, ..._results]);
    final options = name == '类型'
        ? ['不限', '电影', '电视剧']
        : name == '分类'
        ? ['不限', ...data.expand((v) => v.categories).toSet()]
        : [
            '不限',
            ...(data
                .map((v) => v.year?.toString())
                .whereType<String>()
                .toSet()
                .toList()
              ..sort((a, b) => b.compareTo(a))),
          ];
    final selected = name == '类型'
        ? _kind
        : name == '分类'
        ? _genre
        : _year;
    final value = await showRexMenu(
      context,
      anchor: anchor,
      entries: options
          .map((v) => RexMenuEntry(v, v, selected: selected == v))
          .toList(),
    );
    if (!mounted || value == null) return;
    setState(() {
      if (name == '类型') {
        _kind = value;
      } else if (name == '分类') {
        _genre = value;
      } else {
        _year = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = RexScope.of(context);
    final all = (_query.text.trim().isEmpty ? widget.catalog.items : _results)
        .where(_matches)
        .toList();
    final people = <String, Map<String, dynamic>>{};
    for (final item in widget.catalog.items) {
      for (final p in item.people) {
        if (p['name'] is String) people[p['name'] as String] = p;
      }
    }
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 12),
            const Text(
              '搜索',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              child: Row(
                children: [
                  for (final pair in [
                    ('类型', _kind),
                    ('分类', _genre),
                    ('年份', _year),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Builder(
                          builder: (anchor) => RexGlass(
                            color: const Color(0xFF403646),
                            child: CupertinoButton(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 9,
                              ),
                              minimumSize: const Size(0, 40),
                              onPressed: () => _filter(anchor, pair.$1),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      '${pair.$1}：${pair.$2}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  const Icon(
                                    CupertinoIcons.chevron_down,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.axis == Axis.vertical &&
                      n.metrics.extentAfter < 300 &&
                      _more &&
                      !_loading) {
                    unawaited(_search(append: true));
                  }
                  return false;
                },
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 15),
                  children: [
                    if (people.isNotEmpty)
                      SizedBox(
                        height: 108,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          scrollDirection: Axis.horizontal,
                          itemCount: people.length.clamp(0, 12),
                          separatorBuilder: (_, _) => const SizedBox(width: 15),
                          itemBuilder: (context, i) {
                            final p = people.values.elementAt(i);
                            return SizedBox(
                              width: 68,
                              child: CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: () {
                                  _query.text = p['name'] as String;
                                  _focus.unfocus();
                                  _search();
                                },
                                child: Column(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(15),
                                      child: SizedBox(
                                        width: 62,
                                        height: 65,
                                        child: RexArtwork(
                                          p['profile'] as String?,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    Text(
                                      p['name'] as String,
                                      maxLines: 1,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    for (final kind in [MediaKind.movie, MediaKind.tv]) ...[
                      RexHeading(kind == MediaKind.movie ? '电影' : '电视剧'),
                      if (all.any((v) => v.mediaType == kind))
                        SizedBox(
                          height: 138,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            scrollDirection: Axis.horizontal,
                            itemCount: all
                                .where((v) => v.mediaType == kind)
                                .length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, i) {
                              final item = all
                                  .where((v) => v.mediaType == kind)
                                  .elementAt(i);
                              return RexSearchCard(
                                item: item,
                                onTap: () => widget.onOpen(item),
                              );
                            },
                          ),
                        )
                      else if (!_loading)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(18, 4, 18, 14),
                          child: Text(
                            '暂无匹配结果',
                            style: TextStyle(
                              color: RexColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: CupertinoActivityIndicator(),
                      ),
                    if (_error != null)
                      RexEmpty(
                        '搜索暂未完成',
                        subtitle: _error!.userMessage,
                        onRetry: _search,
                      ),
                    if (_more && !_loading)
                      CupertinoButton(
                        onPressed: () => _search(append: true),
                        child: const Text('加载更多'),
                      ),
                    RexHeading(
                      '最近打开',
                      trailing: CupertinoButton(
                        onPressed: store.clearRecent,
                        child: const Text(
                          '清空',
                          style: TextStyle(
                            fontSize: 11,
                            color: RexColors.muted,
                          ),
                        ),
                      ),
                    ),
                    if (store.recentItems.isNotEmpty)
                      SizedBox(
                        height: 138,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          scrollDirection: Axis.horizontal,
                          itemCount: store.recentItems.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (context, i) {
                            final item = store.recentItems[i];
                            return RexSearchCard(
                              item: item,
                              onTap: () => widget.onOpen(item),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                9,
                10,
                MediaQuery.paddingOf(context).bottom + 9,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: RexGlass(
                      color: const Color(0xDC51445A),
                      child: CupertinoTextField(
                        controller: _query,
                        focusNode: _focus,
                        onChanged: _change,
                        onSubmitted: (_) => _search(),
                        placeholder: '搜索电影、电视剧',
                        placeholderStyle: const TextStyle(
                          color: RexColors.muted,
                          fontSize: 14,
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        prefix: const Padding(
                          padding: EdgeInsets.only(left: 14),
                          child: Icon(
                            CupertinoIcons.search,
                            color: RexColors.muted,
                            size: 20,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 13,
                        ),
                        decoration: const BoxDecoration(),
                        clearButtonMode: OverlayVisibilityMode.editing,
                        textInputAction: TextInputAction.search,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.only(left: 14, right: 4),
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      '取消',
                      style: TextStyle(fontSize: 14, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RexSearchCard extends StatelessWidget {
  const RexSearchCard({super.key, required this.item, required this.onTap});
  final VodItem item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 286,
    child: CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: const Color(0xFF3C3048),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x22A392AF)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 79,
                height: 120,
                child: RexArtwork(item.posterImage),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${item.typeLabel} · ${item.year ?? ''}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: RexColors.muted,
                    ),
                  ),
                  if (item.score.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '★ ${item.score}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFFFD157),
                        ),
                      ),
                    ),
                  const SizedBox(height: 5),
                  Text(
                    item.synopsis,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: RexColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
