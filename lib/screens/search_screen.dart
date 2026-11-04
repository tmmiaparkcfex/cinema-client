import 'package:flutter/material.dart';

import '../core/app_log.dart';
import '../core/app_models.dart';
import '../core/app_scope.dart';
import '../core/app_theme.dart';
import '../data/api_client.dart';
import '../widgets/media_cards.dart';
import 'detail_screen.dart';
import '../widgets/cinema_surface.dart';

import 'package:flutter/cupertino.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final List<VodItem> _items = [];
  ApiException? _error;
  bool _loading = false;
  bool _searched = false;
  int _page = 1;
  int _pageCount = 1;
  String _query = '';
  int _requestGeneration = 0;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _search({int page = 1, bool append = false}) async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    final generation = ++_requestGeneration;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _query = query;
      if (!append) {
        _items.clear();
        _searched = true;
      }
    });
    try {
      final value = await AppScope.of(context).api.search(query, page: page);
      if (!mounted || generation != _requestGeneration) return;
      await AppScope.of(context).settings.rememberSearch(query);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        final merged = uniqueTitles([..._items, ...value.items]);
        _items
          ..clear()
          ..addAll(merged);
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
      AppLog.error('search', error);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _error = ApiException(
          ApiFailureKind.protocol,
          error.toString(),
          endpoint: '/api/search',
        );
        _loading = false;
      });
    }
  }

  void _open(VodItem item) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => DetailScreen(item: item)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
            child: Row(
              children: [
                const Text(
                  '影视',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '搜索影片、电视剧',
                      prefixIcon: const Icon(CupertinoIcons.search, size: 20),
                      suffixIcon: _controller.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清空输入',
                              onPressed: () => setState(_controller.clear),
                              icon: const Icon(
                                CupertinoIcons.clear_circled_solid,
                                size: 16,
                              ),
                            ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    ),
  );

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空搜索记录？'),
        content: const Text('清空后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await AppScope.of(context).settings.clearSearchHistory();
    if (mounted) setState(() {});
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _SearchMessage(
        icon: Icons.cloud_off_rounded,
        title: '搜索失败',
        message: _error!.userMessage,
        actionLabel: '重试',
        onAction: () => _search(page: 1),
      );
    }
    if (!_searched) {
      final settings = AppScope.of(context).settings;
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        children: [
          Row(
            children: [
              const Text(
                '最近搜索',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: settings.searchHistory.isEmpty
                    ? null
                    : _clearHistory,
                icon: const Icon(CupertinoIcons.trash, size: 15),
                label: const Text('清空'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (settings.searchHistory.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                '暂无搜索记录',
                style: TextStyle(color: CinemaColors.muted),
              ),
            ),
          for (final query in settings.searchHistory)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: CinemaGlass(
                radius: 12,
                child: ListTile(
                  dense: true,
                  leading: const Icon(CupertinoIcons.clock, size: 19),
                  title: Text(query),
                  onTap: () {
                    _controller.text = query;
                    _search();
                  },
                  trailing: IconButton(
                    tooltip: '删除记录',
                    icon: const Icon(CupertinoIcons.xmark, size: 14),
                    onPressed: () async {
                      await settings.removeSearch(query);
                      if (mounted) setState(() {});
                    },
                  ),
                ),
              ),
            ),
        ],
      );
    }
    if (_items.isEmpty) {
      return _SearchMessage(
        icon: Icons.search_off_rounded,
        title: '没有找到“$_query”',
        message: '可以换一个片名再试。片库资料补齐后，搜索结果会同步增加。',
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '“$_query” · 已加载 ${_items.length} 部作品',
              style: const TextStyle(color: CinemaColors.muted, fontSize: 12),
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 22,
              crossAxisSpacing: 12,
              childAspectRatio: 0.56,
            ),
            itemCount: _items.length,
            itemBuilder: (context, index) => MediaCard(
              item: _items[index],
              width: double.infinity,
              onTap: () => _open(_items[index]),
            ),
          ),
        ),
        if (_page < _pageCount)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: OutlinedButton(
              onPressed: () => _search(page: _page + 1, append: true),
              child: const Text('加载更多'),
            ),
          ),
      ],
    );
  }
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: CinemaColors.faint, size: 44),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: CinemaColors.muted, height: 1.5),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
