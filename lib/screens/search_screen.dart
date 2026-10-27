import 'package:flutter/material.dart';

import '../core/app_log.dart';
import '../core/app_models.dart';
import '../core/app_scope.dart';
import '../core/app_theme.dart';
import '../data/api_client.dart';
import '../widgets/media_cards.dart';
import 'detail_screen.dart';

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
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: wide ? null : AppBar(title: const Text('搜索')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                wide ? 52 : 18,
                wide ? 28 : 10,
                wide ? 52 : 18,
                12,
              ),
              child: Row(
                children: [
                  if (wide)
                    const Padding(
                      padding: EdgeInsets.only(right: 22),
                      child: Text(
                        '搜索',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      textInputAction: TextInputAction.search,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _search(),
                      decoration: InputDecoration(
                        hintText: '搜索电影或电视剧名称',
                        hintStyle: const TextStyle(color: CinemaColors.faint),
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _controller.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '清空',
                                onPressed: () => setState(_controller.clear),
                                icon: const Icon(Icons.close_rounded),
                              ),
                        filled: true,
                        fillColor: CinemaColors.elevated,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _loading ? null : () => _search(),
                      child: const Text('搜索'),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
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
      return const _SearchMessage(
        icon: Icons.search_rounded,
        title: '搜索你的影院',
        message: '按作品名称搜索已核验的 4K 电影和电视剧。',
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
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 176,
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
