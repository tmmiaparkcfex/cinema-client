import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_models.dart';
import '../core/app_scope.dart';
import '../core/episode_choice.dart';
import '../data/api_client.dart';
import '../player/playback_screen.dart';
import 'rex_home.dart';
import 'rex_interactions.dart';
import 'rex_metadata.dart';
import 'rex_scope.dart';
import 'rex_store.dart';
import 'rex_theme.dart';
import 'rex_widgets.dart';

class RexDetail extends StatefulWidget {
  const RexDetail({
    super.key,
    required this.item,
    required this.related,
    required this.onOpen,
    required this.onSearch,
  });
  final VodItem item;
  final List<VodItem> related;
  final ValueChanged<VodItem> onOpen;
  final ValueChanged<String> onSearch;
  @override
  State<RexDetail> createState() => _RexDetailState();
}

class _RexDetailState extends State<RexDetail> {
  VodDetail? _detail;
  Future<VodDetail>? _expanded;
  ApiException? _error;
  bool _loading = true, _introExpanded = false;
  int _season = 1;
  Color _color = const Color(0xFF49303D);
  VodItem get _item => _detail?.item ?? widget.item;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RexScope.of(context).recordOpen(widget.item);
      _load();
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    final services = AppScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await services.api.fetchDetail(
        widget.item.key,
        includeOtherSeasons: false,
      );
      if (!mounted) return;
      _apply(detail);
      _expanded = services.api.expandSeasons(detail);
      unawaited(
        rexPalette(detail.item.heroImage).then((palette) {
          if (mounted) setState(() => _color = palette);
        }),
      );
      final expanded = await _expanded!;
      if (!mounted) return;
      setState(() => _detail = expanded);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  void _apply(VodDetail detail) {
    final resume = AppScope.of(context).store.recordForItem(detail.item);
    setState(() {
      _detail = detail;
      _loading = false;
      _season = resume?.season ?? (_seasons.contains(1) ? 1 : _seasons.first);
    });
    unawaited(RexScope.of(context).recordOpen(detail.item));
  }

  List<int> get _seasons {
    final values = <int>{
      ..._item.seasons
          .map((v) => (v['season'] as num?)?.toInt())
          .whereType<int>(),
      ...?_detail?.allEntries.map((v) => v.season ?? 1),
    }.toList()..sort();
    return values.isEmpty ? [1] : values;
  }

  int get _count {
    if (!_item.isTv) return 1;
    final listed = _item.countForSeason(_season);
    final expected = _detail?.episodeCounts[_season] ?? 0;
    final resourceMax =
        _detail?.allEntries
            .where((v) => (v.season ?? 1) == _season)
            .fold<int>(0, (n, v) => math.max(n, v.episode ?? 0)) ??
        0;
    final count = math.max(math.max(listed, expected), resourceMax);
    return count == 0 && _seasons.length == 1
        ? _item.coverage?.expected ?? 0
        : count;
  }

  EpisodeChoice? _choice(int? episode) {
    final detail = _detail;
    if (detail == null) return null;
    return EpisodeChoice.choiceForEpisode(
          detail,
          season: _season,
          episode: episode,
        ) ??
        (!detail.isSeries ? EpisodeChoice.allFor(detail).firstOrNull : null);
  }

  Future<void> _play([int? episode]) async {
    final detail = _detail;
    if (detail == null) return;
    final record = AppScope.of(context).store.recordForItem(detail.item);
    final resumeEpisode = record?.season == _season ? record?.episode : null;
    final choices = EpisodeChoice.allFor(detail).where((v) => v.isPlayable);
    final choice =
        _choice(episode ?? resumeEpisode ?? (_item.isTv ? 1 : null)) ??
        (episode == null
            ? choices.where((v) => (v.season ?? 1) == _season).firstOrNull ??
                  choices.firstOrNull
            : null);
    if (choice == null || !choice.isPlayable) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaybackScreen(
          detail: detail,
          initialChoice: choice,
          updatedDetail: _expanded,
          rexStyle: true,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _watch(BuildContext anchor) async {
    final store = RexScope.of(context);
    final status = store.status(_item);
    final value = await showRexMenu(
      context,
      anchor: anchor,
      entries: [
        RexMenuEntry(
          'want',
          '待看',
          icon: CupertinoIcons.ticket,
          selected: status == ShelfStatus.want,
        ),
        RexMenuEntry(
          'watching',
          '在看',
          icon: CupertinoIcons.play_rectangle,
          selected: status == ShelfStatus.watching,
        ),
        if (status != null)
          const RexMenuEntry(
            'remove',
            '从片单移除',
            icon: CupertinoIcons.minus_circle,
            destructive: true,
          ),
      ],
    );
    if (!mounted || value == null) return;
    await store.setStatus(
      _item,
      value == 'remove'
          ? null
          : value == 'watching'
          ? ShelfStatus.watching
          : ShelfStatus.want,
    );
    if (mounted && value != 'remove') {
      RexFeedback.ticket(context, _item, value == 'watching' ? '在看' : '待看');
    }
  }

  Future<void> _favorite() async {
    final store = RexScope.of(context);
    await store.toggleFavorite(_item);
    unawaited(HapticFeedback.lightImpact());
    if (mounted) {
      RexFeedback.ticket(
        context,
        _item,
        store.isFavorite(_item) ? '收藏' : '移出收藏',
      );
    }
  }

  Future<void> _pickSeason(BuildContext anchor) async {
    final value = await showRexMenu(
      context,
      anchor: anchor,
      entries: _seasons
          .map(
            (s) => RexMenuEntry(
              s,
              s == 0 ? '特别篇' : '第 $s 季',
              selected: _season == s,
            ),
          )
          .toList(),
    );
    if (mounted && value != null) setState(() => _season = value);
  }

  Future<void> _progress() async {
    final store = RexScope.of(context);
    final result = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => RexProgressSheet(
        item: _item,
        season: _season,
        count: _count,
        selected: store.episodes(_item, _season),
      ),
    );
    if (result != null) await store.setEpisodes(_item, _season, result);
  }

  @override
  Widget build(BuildContext context) {
    final item = _item, store = RexScope.of(context);
    final related = widget.related
        .where(
          (v) =>
              v.identityKey != item.identityKey &&
              (v.mediaType == item.mediaType ||
                  v.categories.any(item.categories.contains)),
        )
        .take(8)
        .toList();
    final canPlay = _detail?.allEntries.any((v) => v.resource != null) == true;
    final top = MediaQuery.paddingOf(context).top;
    final heroHeight = math.min(MediaQuery.sizeOf(context).width * 1.30, 690.0);
    return Scaffold(
      backgroundColor: _color,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: heroHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (rect) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white,
                            Colors.white,
                            Colors.transparent,
                          ],
                          stops: [0, .72, 1],
                        ).createShader(rect),
                        child: RexArtwork(
                          item.heroImage,
                          alignment: Alignment.topCenter,
                        ),
                      ),
                      Positioned(
                        bottom: 18,
                        left: 34,
                        right: 34,
                        child: item.titleLogo != null
                            ? SizedBox(
                                height: 94,
                                child: RexArtwork(
                                  item.titleLogo,
                                  fit: BoxFit.contain,
                                ),
                              )
                            : Text(
                                item.name,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w800,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 10,
                                      color: Colors.black54,
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 15),
                  child: Column(
                    children: [
                      Text(
                        [
                          dateLabel(
                            item.releaseDate,
                            fallback: item.year?.toString(),
                          ),
                          item.countries.take(1).join(),
                          item.isTv && _count > 0
                              ? '$_count 集'
                              : item.runtimeMinutes != null
                              ? '${item.runtimeMinutes} 分钟'
                              : '',
                        ].where((v) => v.isNotEmpty).join(' · '),
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: RexGlass(
                              color: Colors.white.withValues(alpha: .12),
                              child: CupertinoButton(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 11,
                                ),
                                onPressed: canPlay ? _play : null,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (canPlay) ...[
                                      const Icon(
                                        CupertinoIcons.play_fill,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 7),
                                    ],
                                    Text(
                                      _loading
                                          ? '正在匹配资源'
                                          : canPlay
                                          ? AppScope.of(context).store
                                                        .recordForItem(item) ==
                                                    null
                                                ? '开始播放'
                                                : '继续观看'
                                          : '暂无可播放资源',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 11),
                          RexGlass(
                            color: Colors.white.withValues(alpha: .12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Builder(
                                  builder: (anchor) => RexIconButton(
                                    icon: store.status(item) == null
                                        ? CupertinoIcons
                                              .rectangle_stack_badge_plus
                                        : CupertinoIcons.rectangle_stack_fill,
                                    label: '加入片单',
                                    onTap: () => _watch(anchor),
                                  ),
                                ),
                                AnimatedScale(
                                  scale: store.isFavorite(item) ? 1.07 : 1,
                                  duration: const Duration(milliseconds: 200),
                                  child: RexIconButton(
                                    icon: store.isFavorite(item)
                                        ? CupertinoIcons.heart_fill
                                        : CupertinoIcons.heart,
                                    label: store.isFavorite(item)
                                        ? '取消收藏'
                                        : '收藏',
                                    color: store.isFavorite(item)
                                        ? const Color(0xFFFF879E)
                                        : Colors.white,
                                    onTap: _favorite,
                                  ),
                                ),
                                RexIconButton(
                                  icon: CupertinoIcons.calendar_badge_plus,
                                  label: '追剧进度',
                                  onTap: _count > 0 ? _progress : null,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (_error != null)
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '资料暂未更新',
                                style: TextStyle(
                                  color: RexColors.muted,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            CupertinoButton(
                              onPressed: _load,
                              child: const Text(
                                '重试',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      if (item.synopsis.isNotEmpty)
                        CupertinoButton(
                          padding: const EdgeInsets.only(top: 14),
                          minimumSize: Size.zero,
                          onPressed: () =>
                              setState(() => _introExpanded = !_introExpanded),
                          child: Text(
                            item.synopsis,
                            maxLines: _introExpanded ? null : 3,
                            overflow: _introExpanded
                                ? null
                                : TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              height: 1.55,
                            ),
                          ),
                        ),
                      RexRatings(item),
                    ],
                  ),
                ),
              ),
              if (item.isTv) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      children: [
                        Builder(
                          builder: (anchor) => CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => _pickSeason(anchor),
                            child: Row(
                              children: [
                                Text(
                                  '第 $_season 季',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  CupertinoIcons.chevron_down,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (item.metadata['trailers'] is List &&
                            (item.metadata['trailers'] as List).isNotEmpty)
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: _trailer,
                            child: const Text(
                              '预告片',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_count > 0)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 247,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        scrollDirection: Axis.horizontal,
                        itemCount: _count,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, i) {
                          final n = i + 1,
                              info = item.episodeInfo(_season, n),
                              choice = _choice(n);
                          return SizedBox(
                            width: 248,
                            child: CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: choice?.isPlayable == true
                                  ? () => _play(n)
                                  : _progress,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(15),
                                    child: SizedBox(
                                      height: 140,
                                      width: 248,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          RexArtwork(
                                            info?['still'] as String? ??
                                                item.heroImage,
                                          ),
                                          if (store
                                              .episodes(item, _season)
                                              .contains(n))
                                            const Positioned(
                                              right: 9,
                                              bottom: 9,
                                              child: Icon(
                                                CupertinoIcons
                                                    .checkmark_circle_fill,
                                                color: Colors.white,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    choice == null ? '尚未匹配资源' : '已匹配资源',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: RexColors.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '第 $n 集${info?['runtimeMinutes'] != null ? ' · ${info!['runtimeMinutes']} 分钟' : ''}',
                                    style: const TextStyle(
                                      color: RexColors.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Text(
                                    info?['name']?.toString() ??
                                        choice?.entry.label ??
                                        '第 $n 集',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    info?['overview']?.toString() ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: RexColors.muted,
                                      fontSize: 11,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                if (_count == 0 && !_loading)
                  const SliverToBoxAdapter(child: RexEmpty('季集资料暂未补齐')),
              ],
              if (item.people.isNotEmpty)
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      const RexHeading('演职人员'),
                      SizedBox(
                        height: 127,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          scrollDirection: Axis.horizontal,
                          itemCount: item.people.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 18),
                          itemBuilder: (context, i) {
                            final person = item.people[i];
                            return SizedBox(
                              width: 77,
                              child: CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: () =>
                                    widget.onSearch(person['name'].toString()),
                                child: Column(
                                  children: [
                                    ClipOval(
                                      child: SizedBox(
                                        width: 72,
                                        height: 72,
                                        child: RexArtwork(
                                          person['profile'] as String?,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    Text(
                                      person['name']?.toString() ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      person['character']?.toString() ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: RexColors.muted,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              if (item.categories.isNotEmpty)
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const RexHeading('分类'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            for (final genre in item.categories)
                              CupertinoButton(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 13,
                                  vertical: 7,
                                ),
                                minimumSize: const Size(0, 36),
                                color: Colors.white.withValues(alpha: .1),
                                borderRadius: BorderRadius.circular(10),
                                onPressed: () => widget.onSearch(genre),
                                child: Text(
                                  genre,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (item.stillImages.isNotEmpty)
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      const RexHeading('剧照'),
                      SizedBox(
                        height: 142,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          scrollDirection: Axis.horizontal,
                          itemCount: item.stillImages.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (context, i) => CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => _photos(i),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(15),
                              child: SizedBox(
                                width: 248,
                                height: 140,
                                child: RexArtwork(item.stillImages[i]),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (related.isNotEmpty)
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      const RexHeading('相似作品'),
                      RexPosterRow(items: related, onOpen: widget.onOpen),
                    ],
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 55)),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: top,
            child: const IgnorePointer(
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle.light,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black38, Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: top + 6,
            left: 12,
            child: RexGlass(
              color: const Color(0x88312332),
              child: RexIconButton(
                icon: CupertinoIcons.chevron_left,
                label: '返回',
                onTap: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _trailer() async {
    final trailers = (_item.metadata['trailers'] as List).whereType<Map>();
    final url = trailers.firstOrNull?['url']?.toString();
    if (url == null) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('预告片'),
        content: Text(trailers.first['name']?.toString() ?? _item.name),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(context);
            },
            child: const Text('复制预告片链接'),
          ),
        ],
      ),
    );
  }

  void _photos(int initial) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            PageView.builder(
              controller: PageController(initialPage: initial),
              itemCount: _item.stillImages.length,
              itemBuilder: (_, i) => InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: RexArtwork(_item.stillImages[i], fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 12,
              child: RexIconButton(
                icon: CupertinoIcons.xmark,
                label: '关闭剧照',
                onTap: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class RexProgressSheet extends StatefulWidget {
  const RexProgressSheet({
    super.key,
    required this.item,
    required this.season,
    required this.count,
    required this.selected,
  });
  final VodItem item;
  final int season, count;
  final Set<int> selected;
  @override
  State<RexProgressSheet> createState() => _RexProgressSheetState();
}

class _RexProgressSheetState extends State<RexProgressSheet> {
  late Set<int> _selected = Set.of(widget.selected);
  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .84,
    child: Column(
      children: [
        const SizedBox(height: 9),
        Container(
          width: 35,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white30,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 7),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '追剧进度',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '第 ${widget.season} 季 · ${_selected.length} 集 / 共 ${widget.count} 集',
                      style: const TextStyle(
                        color: RexColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              RexIconButton(
                icon: CupertinoIcons.xmark,
                label: '关闭追剧进度',
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 5, 18, 8),
            itemCount: widget.count,
            itemBuilder: (context, i) {
              final n = i + 1, info = widget.item.episodeInfo(widget.season, n);
              return Semantics(
                checked: _selected.contains(n),
                label: '第 $n 集',
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  onPressed: () => setState(() {
                    if (!_selected.add(n)) _selected.remove(n);
                  }),
                  child: Row(
                    children: [
                      Icon(
                        _selected.contains(n)
                            ? CupertinoIcons.checkmark_circle_fill
                            : CupertinoIcons.circle,
                        color: Colors.white,
                        size: 23,
                      ),
                      const SizedBox(width: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 112,
                          height: 68,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              RexArtwork(
                                info?['still'] as String? ??
                                    widget.item.heroImage,
                              ),
                              Positioned(
                                left: 5,
                                top: 4,
                                child: Text(
                                  '$n',
                                  style: const TextStyle(
                                    fontSize: 19,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    shadows: [
                                      Shadow(
                                        blurRadius: 4,
                                        color: Colors.black,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              info?['name']?.toString() ?? '第 $n 集',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              info?['airDate']?.toString() ?? '',
                              style: const TextStyle(
                                fontSize: 10,
                                color: RexColors.muted,
                              ),
                            ),
                            Text(
                              info?['overview']?.toString() ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: RexColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
            child: Row(
              children: [
                RexGlass(
                  color: const Color(0xFF615668),
                  child: Row(
                    children: [
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        onPressed: () => setState(
                          () => _selected = Set.from(
                            List.generate(widget.count, (i) => i + 1),
                          ),
                        ),
                        child: const Text(
                          '全选',
                          style: TextStyle(fontSize: 13, color: Colors.white),
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        onPressed: () => setState(_selected.clear),
                        child: const Text(
                          '取消全选',
                          style: TextStyle(fontSize: 13, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                CupertinoButton.filled(
                  borderRadius: BorderRadius.circular(25),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 25,
                    vertical: 12,
                  ),
                  onPressed: () => Navigator.pop(context, _selected),
                  child: const Text('保存', style: TextStyle(fontSize: 14)),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
