import 'package:flutter/material.dart';

import '../core/app_log.dart';
import '../core/app_models.dart';
import '../core/app_scope.dart';
import '../core/app_theme.dart';
import '../core/episode_choice.dart';
import '../core/media_metadata.dart';
import '../data/api_client.dart';
import '../player/playback_screen.dart';
import '../widgets/poster_artwork.dart';

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
  int _loadGeneration = 0;
  Future<VodDetail>? _detailsUpdate;
  final _loadedEpisodeKeys = <String>{};

  Future<void> _selectSeason(int? season) async {
    if (season == null) return;
    setState(() => _season = season);
    final key = _episodes.firstOrNull?.resource?.catalogKey ?? '';
    if (key.isEmpty || key == _detail?.item.key || !_loadedEpisodeKeys.add(key)) return;
    final generation = _loadGeneration;
    try {
      final extra = await AppScope.of(context).api.fetchDetail(key, includeOtherSeasons: false);
      if (!mounted || generation != _loadGeneration ||
          extra.item.workId != _detail?.item.workId) return;
      final current = _detail!;
      final metadata = current.item.metadata;
      final rows = <String, Map<String, dynamic>>{};
      for (final row in [...metadata.episodeData, ...extra.item.metadata.episodeData]) {
        rows['${row['season']}/${row['episode']}'] = row;
      }
      setState(() => _detail = VodDetail(
        item: current.item.copyWith(metadata: MediaMetadata(data: metadata.data,
            episodeData: rows.values.toList())),
        lines: current.lines, seasonsLoaded: current.seasonsLoaded,
        episodeCounts: current.episodeCounts,
      ));
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

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final services = AppScope.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontal = screenWidth >= 900 ? 56.0 : 18.0;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null && detail == null
                ? _ErrorBody(message: _error!.userMessage, onRetry: _load)
                : detail == null
                ? const SizedBox.shrink()
                : SingleChildScrollView(
                    padding: EdgeInsets.only(
                      bottom: 40 + MediaQuery.paddingOf(context).bottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          children: [
                            _Hero(
                              item: detail.item,
                              height: screenWidth >= 900 ? 430 : 350,
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 0,
                              child: SafeArea(
                                bottom: false,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    6,
                                    10,
                                    12,
                                  ),
                                  child: Row(
                                    children: [
                                      _RoundButton(
                                        icon: Icons.arrow_back_ios_new_rounded,
                                        onTap: () =>
                                            Navigator.of(context).pop(),
                                        tooltip: '返回',
                                      ),
                                      const Spacer(),
                                      AnimatedBuilder(
                                        animation: services.store,
                                        builder: (context, _) {
                                          final favorite = services.store
                                              .isFavoriteItem(detail.item);
                                          return _RoundButton(
                                            icon: favorite
                                                ? Icons.check_rounded
                                                : Icons.add_rounded,
                                            tooltip: favorite ? '已在片单' : '加入片单',
                                            onTap: _toggleFavorite,
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Transform.translate(
                          offset: const Offset(0, -64),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontal,
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1040),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _titleBlock(detail),
                                  const SizedBox(height: 18),
                                  _actionRow(detail),
                                  const SizedBox(height: 26),
                                  _description(detail.item),
                                  const SizedBox(height: 30),
                                  _linePicker(detail),
                                  if (_updating ||
                                      _error != null ||
                                      !detail.seasonsLoaded)
                                    TextButton.icon(
                                      onPressed: _updating ? null : _load,
                                      icon: const Icon(Icons.refresh),
                                      label: Text(
                                        _updating
                                            ? '正在读取片源与其他季…'
                                            : _error?.userMessage ??
                                                  '部分季暂未读取，重试',
                                      ),
                                    ),
                                  const SizedBox(height: 24),
                                  if (detail.isSeries)
                                    _episodeSection(detail)
                                  else
                                    _movieVersionSection(),
                                  if (detail.item.metadata.credits.isNotEmpty ||
                                      detail.item.actors.isNotEmpty ||
                                      detail.item.directors.isNotEmpty) ...[
                                    const SizedBox(height: 28),
                                    _credits(detail.item),
                                  ],
                                  if (detail.item.metadata.studios.isNotEmpty) ...[
                                    const SizedBox(height: 24),
                                    Text(detail.item.metadata.studios.join(' · '),
                                      style: const TextStyle(color: CinemaColors.faint, fontSize: 12)),
                                  ],
                                  if (detail.item.metadata.source.isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    Text('影视资料来自 ${detail.item.metadata.source.toUpperCase()}',
                                      style: const TextStyle(color: CinemaColors.faint, fontSize: 11)),
                                  ],
                                ],
                              ),
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

  Widget _titleBlock(VodDetail detail) {
    final meta = <String>[
      if (detail.item.year != null) '${detail.item.year}',
      detail.item.typeLabel,
      if (detail.item.area.isNotEmpty) detail.item.area,
      if (detail.item.language.isNotEmpty) detail.item.language,
      ...detail.item.genres,
      if (detail.item.runtimeMinutes != null)
        '${detail.item.runtimeMinutes} 分钟',
      if (detail.item.score.isNotEmpty) '评分 ${detail.item.score}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          detail.item.name,
          style: const TextStyle(
            fontSize: 32,
            height: 1.08,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.8,
          ),
        ),
        if (detail.item.metadata.originalTitle.isNotEmpty &&
            detail.item.metadata.originalTitle != detail.item.name) ...[
          const SizedBox(height: 7),
          Text(detail.item.metadata.originalTitle,
            style: const TextStyle(color: CinemaColors.muted, fontSize: 14)),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [for (final text in meta) _MetaChip(text: text)],
        ),
        if (detail.isSeries) ...[
          const SizedBox(height: 10),
          Text(
            '${detail.allEntries.map((e) => e.season ?? 1).toSet().length} 季 · ${detail.allEntries.where((e) => e.episode != null).map((e) => '${e.season ?? 1}/${e.episode}').toSet().length} 集可播',
            style: const TextStyle(color: CinemaColors.muted, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _actionRow(VodDetail detail) {
    final store = AppScope.of(context).store;
    final record = store.recordForItem(detail.item);
    final buttonLabel = record?.completed == true
        ? '重新播放'
        : record == null
        ? '播放'
        : record.episodeText.isEmpty
        ? '继续播放'
        : '继续播放 ${record.episodeText}';
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      children: [
        SizedBox(
          width: 240,
          height: 48,
          child: FilledButton.icon(
            onPressed: detail.playableLines.isEmpty ? null : _playDefault,
            style: FilledButton.styleFrom(
              backgroundColor: CinemaColors.accent,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.play_arrow_rounded, size: 25),
            label: Text(buttonLabel),
          ),
        ),
        SizedBox(
          height: 48,
          child: AnimatedBuilder(
            animation: store,
            builder: (context, _) {
              final favorite = store.isFavoriteItem(detail.item);
              return OutlinedButton.icon(
                onPressed: _toggleFavorite,
                icon: Icon(
                  favorite ? Icons.check_rounded : Icons.add_rounded,
                  size: 20,
                ),
                label: Text(favorite ? '已加入片单' : '我的片单'),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _description(VodItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '剧情简介',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Text(
          item.overview.isEmpty ? '简介暂未提供，等待片库资料补齐。' : item.overview,
          style: TextStyle(
            color: item.overview.isEmpty
                ? CinemaColors.faint
                : CinemaColors.muted,
            height: 1.6,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _credits(VodItem item) {
    final credits = item.metadata.credits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '演职员',
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
                return SizedBox(width: 92, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(borderRadius: BorderRadius.circular(10),
                      child: SizedBox(width: 92, height: 126,
                        child: person.portrait == null
                          ? const ColoredBox(color: CinemaColors.elevatedHigh,
                              child: Icon(Icons.person_outline, color: CinemaColors.faint))
                          : Image.network(person.portrait!, fit: BoxFit.cover, cacheWidth: 240,
                              errorBuilder: (_, _, _) => const ColoredBox(
                                color: CinemaColors.elevatedHigh,
                                child: Icon(Icons.person_outline, color: CinemaColors.faint))),
                      )),
                    const SizedBox(height: 8),
                    Text(person.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(person.role, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: CinemaColors.faint)),
                  ],
                ));
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

  Widget _linePicker(VodDetail detail) {
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
                    if (seasons.isNotEmpty && !seasons.contains(_season)) {
                      _season = seasons.first;
                    }
                  });
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
    final record = AppScope.of(context).store.recordForItem(detail.item);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '剧集',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const Spacer(),
            if (seasons.length > 1)
              DropdownButton<int>(
                value: _season ?? seasons.first,
                dropdownColor: CinemaColors.elevatedHigh,
                underline: const SizedBox.shrink(),
                items: [
                  for (final season in seasons)
                    DropdownMenuItem(value: season, child: Text('第$season季')),
                ],
                onChanged: _selectSeason,
              ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 760 ? 2 : 1;
            final width = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                for (final choice in episodes)
                  SizedBox(
                    width: width,
                    child: _EpisodeTile(
                      choice: choice,
                      info: detail.item.metadata.episode(choice.season ?? 1, choice.episode ?? 0),
                      selected: record?.resourceId == choice.resource?.id,
                      onTap: () => _play(choice),
                    ),
                  ),
              ],
            );
          },
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
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          BackdropArtwork(item: item),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xAA07080B),
                  Color(0x2207080B),
                  Color(0xFF07080B),
                ],
                stops: [0, 0.48, 1],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xAA07080B), Colors.transparent],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0x33FFFFFF),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, color: CinemaColors.muted),
      ),
    );
  }
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
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? CinemaColors.accent : CinemaColors.elevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? CinemaColors.accent : CinemaColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : CinemaColors.muted,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
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
      color: selected ? const Color(0xFF142339) : CinemaColors.elevated,
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
                  child: SizedBox(width: 104, height: 64,
                    child: info!.still.isEmpty
                      ? const ColoredBox(color: CinemaColors.elevatedHigh,
                          child: Icon(Icons.movie_outlined, color: CinemaColors.faint))
                      : Image.network(info!.still, fit: BoxFit.cover, cacheWidth: 320,
                          errorBuilder: (_, _, _) => const ColoredBox(
                            color: CinemaColors.elevatedHigh,
                            child: Icon(Icons.movie_outlined, color: CinemaColors.faint))),
                  ),
                )
              else Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? CinemaColors.accent : const Color(0xFF252A34),
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
                      Text(info!.overview, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: CinemaColors.muted, fontSize: 11, height: 1.5)),
                      const SizedBox(height: 5),
                    ],
                    if (info != null && (info!.runtimeMinutes > 0 || info!.airDate.isNotEmpty))
                      Text([
                        if (info!.runtimeMinutes > 0) '${info!.runtimeMinutes} 分钟',
                        if (info!.airDate.isNotEmpty) info!.airDate,
                      ].join(' · '), style: const TextStyle(color: CinemaColors.faint, fontSize: 10)),
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

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x77000000),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, size: 20),
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
