import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../core/app_log.dart';
import '../core/app_models.dart';
import '../core/app_scope.dart';
import '../core/app_theme.dart';
import '../core/episode_choice.dart';
import '../core/media_metadata.dart';
import '../data/api_client.dart';
import '../player/playback_screen.dart';
import '../widgets/poster_artwork.dart';
import '../widgets/cinema_surface.dart';
import 'downloads_screen.dart';
import 'search_screen.dart';
import '../widgets/reference_chrome.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.item, this.autoPlay = false});

  final VodItem item;
  final bool autoPlay;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  VodDetail? _detail;
  ApiException? _error;
  bool _loading = true;
  bool _updating = false;
  String? _group;
  int? _season;
  bool _autoPlayHandled = false;
  int _episodeGroup = 0;
  int _loadGeneration = 0;
  Future<VodDetail>? _detailsUpdate;
  final _loadedEpisodeKeys = <String>{};

  Future<void> _selectSeason(int? season) async {
    if (season == null) return;
    setState(() {
      _season = season;
      _episodeGroup = 0;
    });
    final key = _episodes.firstOrNull?.resource?.catalogKey ?? '';
    if (key.isEmpty ||
        key == _detail?.item.key ||
        !_loadedEpisodeKeys.add(key)) {
      return;
    }
    final generation = _loadGeneration;
    try {
      final extra = await AppScope.of(context).api
          .fetchDetail(key, includeOtherSeasons: false);
      if (!mounted ||
          generation != _loadGeneration ||
          extra.item.workId != _detail?.item.workId) {
        return;
      }
      final current = _detail!;
      final metadata = current.item.metadata;
      final rows = <String, Map<String, dynamic>>{};
      for (final row in [
        ...metadata.episodeData,
        ...extra.item.metadata.episodeData,
      ]) {
        rows['${row['season']}/${row['episode']}'] = row;
      }
      setState(
        () => _detail = VodDetail(
          item: current.item.copyWith(
            metadata: MediaMetadata(
              data: metadata.data,
              episodeData: rows.values.toList(),
            ),
          ),
          lines: current.lines,
          seasonsLoaded: current.seasonsLoaded,
          episodeCounts: current.episodeCounts,
        ),
      );
    } on ApiException catch (error) {
      _loadedEpisodeKeys.remove(key);
      AppLog.error('episode-metadata', error);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    final services = AppScope.of(context);
    if (_detail == null) {
      _present(
        VodDetail(
          item: widget.item,
          lines: widget.item.catalogLines,
          seasonsLoaded: false,
        ),
      );
    }
    setState(() {
      _loading = _detail == null;
      _updating = true;
      _error = null;
    });
    try {
      if (_detail != null && widget.item.catalogLines.isNotEmpty) {
        _detailsUpdate = services.api.fetchDetail(widget.item.key);
        _triggerAutoPlay();
      } else {
        final current = await services.api.fetchDetail(
          widget.item.key,
          includeOtherSeasons: false,
        );
        if (!mounted || generation != _loadGeneration) return;
        _detailsUpdate = services.api.expandSeasons(current);
        _present(current);
        _triggerAutoPlay();
      }
      final updated = await _detailsUpdate!;
      if (!mounted || generation != _loadGeneration) return;
      _present(updated);
      setState(() => _updating = false);
    } on ApiException catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = error;
        _loading = false;
        _updating = false;
      });
    } catch (error) {
      AppLog.error('detail', error);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = ApiException(
          ApiFailureKind.protocol,
          error.toString(),
          endpoint: '/api/detail',
        );
        _loading = false;
        _updating = false;
      });
    }
  }

  void _present(VodDetail detail) {
    final record = AppScope.of(context).store.recordForItem(detail.item);
    final selected = detail.playableLines.where(
      (line) => line.group == (_group ?? record?.lineGroup),
    );
    final line = selected.isNotEmpty
        ? selected.first
        : detail.playableLines.firstOrNull;
    final seasons = line == null ? <int>[] : EpisodeChoice.seasonsForLine(line);
    setState(() {
      _detail = detail;
      _group = line?.group;
      _season = seasons.contains(_season)
          ? _season
          : seasons.contains(record?.season)
          ? record?.season
          : seasons.firstOrNull;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _triggerAutoPlay() async {
    if (!widget.autoPlay || _autoPlayHandled) return;
    _autoPlayHandled = true;
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (mounted) _playDefault();
  }

  MediaLine? get _selectedLine {
    final detail = _detail;
    if (detail == null) return null;
    for (final line in detail.playableLines) {
      if (line.group == _group) return line;
    }
    return detail.playableLines.isEmpty ? null : detail.playableLines.first;
  }

  List<EpisodeChoice> get _episodes {
    final line = _selectedLine;
    if (line == null) return const [];
    final choices = EpisodeChoice.forLine(line);
    if (_detail?.isSeries != true || _season == null) return choices;
    return choices.where((choice) => (choice.season ?? 1) == _season).toList();
  }

  EpisodeChoice? _defaultChoice() {
    final detail = _detail;
    if (detail == null) return null;
    final episodes = _episodes;
    final record = AppScope.of(context).store.recordForItem(detail.item);
    if (record != null) {
      for (final choice in episodes) {
        if (choice.resource?.id == record.resourceId) return choice;
      }
      for (final choice in episodes) {
        if ((choice.season ?? 1) == (record.season ?? 1) &&
            choice.episode == record.episode) {
          return choice;
        }
      }
    }
    return episodes.isEmpty ? null : episodes.first;
  }

  Future<void> _play(EpisodeChoice choice) async {
    final detail = _detail;
    if (detail == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaybackScreen(
          detail: detail,
          initialChoice: choice,
          updatedDetail: _detailsUpdate,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _playDefault() {
    final choice = _defaultChoice();
    if (choice == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('该线路还没有可播放的客户端资源描述。')));
      return;
    }
    _play(choice);
  }

  Future<void> _toggleFavorite() async {
    final detail = _detail;
    if (detail == null) return;
    await AppScope.of(context).store.toggleFavorite(detail.item);
  }

  Future<void> _download() async {
    final detail = _detail;
    final manager = AppScope.of(context).downloads;
    if (detail == null || manager == null) return;
    final choices = _episodes;
    if (choices.isEmpty) return;
    final choice = await showModalBottomSheet<EpisodeChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  '选择原画文件',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: choices.length,
                  itemBuilder: (context, index) {
                    final choice = choices[index];
                    return ListTile(
                      title: Text(choice.episodeLabel),
                      subtitle: Text(
                        choice.resource?.technicalSummary ?? '文件信息待补齐',
                      ),
                      trailing: const Icon(Icons.download_rounded),
                      onTap: choice.resource == null
                          ? null
                          : () => Navigator.pop(context, choice),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice?.resource == null || !mounted) return;
    try {
      await manager.enqueue(
        detail.item,
        choice!.resource!,
        choice.episodeLabel,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('已加入下载队列'),
          action: SnackBarAction(
            label: '查看',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DownloadsScreen()),
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('文件信息不完整，暂时无法下载。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _detail?.item ?? widget.item;
    return PosterSurface(
      imageUrl: item.poster ?? item.backdrop,
      child: Builder(builder: _buildDetail),
    );
  }

  Widget _buildDetail(BuildContext context) {
    final detail = _detail;
    final width = MediaQuery.sizeOf(context).width;
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (detail == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: _ErrorBody(
          message: _error?.userMessage ?? '暂时无法读取影片',
          onRetry: _load,
        ),
      );
    }
    final h = width >= 900 ? 56.0 : 16.0;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + 24,
        ),
        child: Column(
          children: [
            SizedBox(
              height: width >= 900 ? 530 : width * 0.67,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Hero(item: detail.item, height: width * 0.67),
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ReferenceHeader(
                          onBack: () => Navigator.pop(context),
                          onSearch: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => PosterSurface(
                                imageUrl: detail.item.poster,
                                child: const SearchScreen(),
                              ),
                            ),
                          ),
                          onMore: () => _more(detail),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: h),
              child: Column(
                children: [
                  FeatureTitle(item: detail.item, height: 60),
                  const SizedBox(height: 8),
                  Text(
                    [
                      if (detail.item.genres.isNotEmpty)
                        detail.item.genres.first,
                      if (detail.isSeries) '第${_season ?? 1}季',
                      if (detail.item.coverage != null &&
                          detail.item.coverage!.expected > 0)
                        '全${detail.item.coverage!.expected}集'
                      else if (detail.item.year != null)
                        '${detail.item.year}',
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _selectedLine
                            ?.entries
                            .firstOrNull
                            ?.resource
                            ?.technicalSummary ??
                        '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: CinemaColors.muted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _actionRow(detail),
                  const SizedBox(height: 12),
                  AnimatedBuilder(
                    animation: AppScope.of(context).store,
                    builder: (context, _) {
                      final store = AppScope.of(context).store;
                      final watched = store.hasWatched(detail.item);
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: () => store.toggleWatched(detail.item),
                            icon: Icon(
                              watched
                                  ? CupertinoIcons.checkmark_circle_fill
                                  : CupertinoIcons.checkmark_circle,
                              size: 24,
                            ),
                            label: Text(watched ? '已看' : '看过'),
                          ),
                          Container(
                            width: 1,
                            height: 16,
                            margin: const EdgeInsets.symmetric(horizontal: 20),
                            color: const Color(0x55765440),
                          ),
                          TextButton.icon(
                            onPressed: _toggleFavorite,
                            icon: Icon(
                              store.isFavoriteItem(detail.item)
                                  ? CupertinoIcons.heart_fill
                                  : CupertinoIcons.heart,
                              size: 24,
                            ),
                            label: const Text('收藏'),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => _intro(detail),
                    child: Text(
                      detail.item.metadata.tagline.isNotEmpty
                          ? detail.item.metadata.tagline
                          : detail.item.overview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: CinemaColors.muted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (_updating || _error != null || !detail.seasonsLoaded)
                    TextButton.icon(
                      onPressed: _updating ? null : _load,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(_updating ? '正在读取剧集…' : '重试读取剧集'),
                    ),
                  if (detail.isSeries)
                    _episodeSection(detail)
                  else
                    _movieVersionSection(),
                  if (detail.item.metadata.credits.isNotEmpty ||
                      detail.item.actors.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    _credits(detail.item),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionRow(VodDetail detail) => SizedBox(
    width: double.infinity,
    height: 42,
    child: FilledButton.icon(
      onPressed: detail.playableLines.isEmpty ? null : _playDefault,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: CinemaColors.text,
      ),
      icon: const Icon(CupertinoIcons.play_fill, size: 22),
      label: const Text(
        '播放',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
    ),
  );

  void _intro(VodDetail detail) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => PosterSurface(
        imageUrl: detail.item.poster,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            children: [
              const ReferencePageHeader(title: '剧情与演职员'),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 84,
                          height: 126,
                          child: PosterArtwork(item: detail.item),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                detail.item.name,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                [
                                  detail.item.year,
                                  ...detail.item.genres,
                                ].where((v) => v != null).join(' · '),
                              ),
                              const SizedBox(height: 10),
                              FilledButton.icon(
                                onPressed: _playDefault,
                                icon: const Icon(CupertinoIcons.play_fill),
                                label: const Text('播放'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      '剧情简介',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      detail.item.overview.isEmpty
                          ? '暂无剧情简介'
                          : detail.item.overview,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.75,
                        color: CinemaColors.muted,
                      ),
                    ),
                    const SizedBox(height: 26),
                    _credits(detail.item),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  void _more(VodDetail detail) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(CupertinoIcons.info_circle),
              title: const Text('剧情与演职员'),
              onTap: () {
                Navigator.pop(sheetContext);
                _intro(detail);
              },
            ),
            if (AppScope.of(context).downloads != null)
              ListTile(
                leading: const Icon(CupertinoIcons.arrow_down_circle),
                title: const Text('下载原画'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _download();
                },
              ),
            StatefulBuilder(
              builder: (context, update) => GestureDetector(
                onTap: () => update(() {}),
                child: _linePicker(detail, onChanged: () => update(() {})),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _credits(VodItem item) {
    final credits = item.metadata.credits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '演职人员',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 8),
        if (credits.isNotEmpty)
          SizedBox(
            height: 204,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: credits.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final person = credits[index];
                return SizedBox(
                  width: 92,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 92,
                          height: 126,
                          child: person.portrait == null
                              ? const ColoredBox(
                                  color: CinemaColors.elevatedHigh,
                                  child: Icon(
                                    Icons.person_outline,
                                    color: CinemaColors.faint,
                                  ),
                                )
                              : Image.network(
                                  person.portrait!,
                                  fit: BoxFit.cover,
                                  cacheWidth: 240,
                                  frameBuilder: (_, child, frame, _) =>
                                      frame == null
                                      ? _photoPlaceholder(Icons.person_outline)
                                      : child,
                                  errorBuilder: (_, _, _) => const ColoredBox(
                                    color: CinemaColors.elevatedHigh,
                                    child: Icon(
                                      Icons.person_outline,
                                      color: CinemaColors.faint,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        person.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        person.role,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: CinemaColors.faint,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        if (credits.isEmpty) ...[
          if (item.directors.isNotEmpty)
            Text(
              '导演：${item.directors}',
              style: const TextStyle(color: CinemaColors.muted),
            ),
          if (item.actors.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              '主演：${item.actors}',
              style: const TextStyle(color: CinemaColors.muted),
            ),
          ],
        ],
      ],
    );
  }

  Widget _linePicker(VodDetail detail, {VoidCallback? onChanged}) {
    if (detail.playableLines.length <= 1) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '线路与版本',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final line in detail.playableLines)
              _ChoicePill(
                label: line.group,
                selected: line.group == _selectedLine?.group,
                onTap: () {
                  final seasons = EpisodeChoice.seasonsForLine(line);
                  setState(() {
                    _group = line.group;
                    _episodeGroup = 0;
                    if (seasons.isNotEmpty && !seasons.contains(_season)) {
                      _season = seasons.first;
                    }
                  });
                  onChanged?.call();
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _episodeSection(VodDetail detail) {
    final line = _selectedLine;
    if (line == null) {
      return const Text(
        '没有可播放线路。',
        style: TextStyle(color: CinemaColors.faint),
      );
    }
    final seasons = EpisodeChoice.seasonsForLine(line);
    final episodes = _episodes;
    final groupCount = (episodes.length / 5).ceil();
    final group = _episodeGroup.clamp(0, groupCount > 0 ? groupCount - 1 : 0);
    final record = AppScope.of(context).store.recordForItem(detail.item);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PopupMenuButton<int>(onSelected: _selectSeason,
              itemBuilder: (_) => [for (final season in seasons)
                PopupMenuItem(value: season, child: Text('第$season季'))],
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('第${_season ?? 1}季', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                const SizedBox(width: 8), const Icon(CupertinoIcons.chevron_down, size: 18),
              ])),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (pageContext) =>
                PosterSurface(imageUrl: detail.item.poster, child: Scaffold(backgroundColor: Colors.transparent,
                  body: Column(children: [const ReferencePageHeader(title: '全部剧集'),
                    Expanded(child: ListView.separated(padding: const EdgeInsets.all(18),
                      itemCount: episodes.length, separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final choice = episodes[index];
                        return _EpisodeTile(choice: choice,
                          info: detail.item.metadata.episode(choice.season ?? 1, choice.episode ?? 0),
                          selected: record?.resourceId == choice.resource?.id,
                          onTap: () { Navigator.pop(pageContext); _play(choice); });
                      })),
                  ]))))),
              child: const Text('全部剧集 ›'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (groupCount > 1) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < groupCount; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _ChoicePill(
                      label:
                          '${i * 5 + 1}–${((i + 1) * 5).clamp(1, episodes.length)}',
                      selected: group == i,
                      onTap: () => setState(() => _episodeGroup = i),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        SizedBox(
          height: (MediaQuery.sizeOf(context).width - 44) / 2 * 0.5625 + 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: episodes.skip(group * 5).take(5).length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final choice = episodes[group * 5 + index];
              final info = detail.item.metadata.episode(
                choice.season ?? 1,
                choice.episode ?? 0,
              );
              return _EpisodeCard(
                choice: choice,
                info: info,
                selected: record?.resourceId == choice.resource?.id,
                onTap: () => _play(choice),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _movieVersionSection() {
    final line = _selectedLine;
    if (line == null) return const SizedBox.shrink();
    final choices = EpisodeChoice.forLine(line);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '播放版本',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 10),
        for (final choice in choices)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _EpisodeTile(
              choice: choice,
              selected: false,
              onTap: () => _play(choice),
            ),
          ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.item, required this.height});
  final VodItem item;
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: FeaturePoster(item: item, faded: true),
  );
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.32),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? CinemaColors.text : CinemaColors.muted,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

Widget _photoPlaceholder(IconData icon) => ColoredBox(
  color: CinemaColors.elevatedHigh,
  child: Icon(icon, color: CinemaColors.faint),
);

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.choice,
    required this.selected,
    required this.onTap,
    this.info,
  });
  final EpisodeChoice choice;
  final bool selected;
  final VoidCallback onTap;
  final EpisodeInfo? info;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: (MediaQuery.sizeOf(context).width - 44) / 2,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: (MediaQuery.sizeOf(context).width - 44) / 2 * 0.5625,
              width: (MediaQuery.sizeOf(context).width - 44) / 2,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (info?.still.isNotEmpty == true)
                    Image.network(
                      info!.still,
                      fit: BoxFit.cover,
                      cacheWidth: 600,
                      errorBuilder: (_, _, _) =>
                          _photoPlaceholder(Icons.movie_outlined),
                    )
                  else
                    _photoPlaceholder(Icons.movie_outlined),
                  if (selected)
                    Positioned(
                      left: 10,
                      bottom: 10,
                      child: CinemaGlass(
                        radius: 12,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        child: const Text(
                          '上次观看',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${choice.episodeLabel}${info?.name.isNotEmpty == true ? ' · ${info!.name}' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            info?.overview.isNotEmpty == true
                ? info!.overview
                : choice.resource?.technicalSummary ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: CinemaColors.muted,
            ),
          ),
          if (info?.runtimeMinutes != null && info!.runtimeMinutes > 0)
            Text(
              '${info!.runtimeMinutes} 分钟',
              style: const TextStyle(fontSize: 11, color: CinemaColors.faint),
            ),
        ],
      ),
    ),
  );
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.choice,
    required this.selected,
    required this.onTap,
    this.info,
  });

  final EpisodeChoice choice;
  final bool selected;
  final VoidCallback onTap;
  final EpisodeInfo? info;

  @override
  Widget build(BuildContext context) {
    final resource = choice.resource;
    return Material(
      color: selected ? const Color(0xFFE2D3C6) : CinemaColors.elevated,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              if (info != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: SizedBox(
                    width: 104,
                    height: 64,
                    child: info!.still.isEmpty
                        ? const ColoredBox(
                            color: CinemaColors.elevatedHigh,
                            child: Icon(
                              Icons.movie_outlined,
                              color: CinemaColors.faint,
                            ),
                          )
                        : Image.network(
                            info!.still,
                            fit: BoxFit.cover,
                            cacheWidth: 320,
                            frameBuilder: (_, child, frame, _) => frame == null
                                ? _photoPlaceholder(Icons.movie_outlined)
                                : child,
                            errorBuilder: (_, _, _) => const ColoredBox(
                              color: CinemaColors.elevatedHigh,
                              child: Icon(
                                Icons.movie_outlined,
                                color: CinemaColors.faint,
                              ),
                            ),
                          ),
                  ),
                )
              else
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? CinemaColors.accent
                        : CinemaColors.elevatedHigh,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(
                    selected
                        ? Icons.play_arrow_rounded
                        : Icons.play_arrow_outlined,
                    size: 20,
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${choice.episodeLabel}${info?.name.isNotEmpty == true ? ' · ${info!.name}' : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    if (info?.overview.isNotEmpty == true) ...[
                      Text(
                        info!.overview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CinemaColors.muted,
                          fontSize: 11,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 5),
                    ],
                    if (info != null &&
                        (info!.runtimeMinutes > 0 || info!.airDate.isNotEmpty))
                      Text(
                        [
                          if (info!.runtimeMinutes > 0)
                            '${info!.runtimeMinutes} 分钟',
                          if (info!.airDate.isNotEmpty) info!.airDate,
                        ].join(' · '),
                        style: const TextStyle(
                          color: CinemaColors.faint,
                          fontSize: 10,
                        ),
                      ),
                    Text(
                      resource?.technicalSummary.isNotEmpty == true
                          ? resource!.technicalSummary
                          : '画质资料待补齐',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CinemaColors.faint,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Text(
                  '上次观看',
                  style: TextStyle(color: CinemaColors.accent, fontSize: 11),
                ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: CinemaColors.faint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 42,
              color: CinemaColors.faint,
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
