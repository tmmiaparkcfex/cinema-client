import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_models.dart';
import '../core/episode_choice.dart';
import '../rex/rex_metadata.dart';
import '../rex/rex_widgets.dart';

enum RexPlayerPanel { episodes, resources, comments }

String playbackClock(Duration time) {
  String two(int v) => v.toString().padLeft(2, '0');
  final rest = '${two(time.inMinutes % 60)}:${two(time.inSeconds % 60)}';
  return time.inHours > 0 ? '${time.inHours}:$rest' : rest;
}

String playbackQuality(MediaResource? resource) {
  final width = resource?.width ?? 0;
  final height = resource?.height ?? 0;
  if (width >= 3700 || height >= 2100) return '4K';
  if (width >= 2500 || height >= 1400) return '2K';
  if (width >= 1850 || height >= 1000) return '1080P';
  if (width >= 1200 || height >= 700) return '720P';
  return height > 0 ? '${height}P' : '线路';
}

class RexPlayerControls extends StatelessWidget {
  const RexPlayerControls({
    super.key,
    required this.title,
    required this.playing,
    required this.visible,
    required this.position,
    required this.duration,
    required this.buffer,
    required this.quality,
    required this.rate,
    required this.locked,
    required this.onBack,
    required this.onPlay,
    required this.onNext,
    required this.onSeekStart,
    required this.onSeekChanged,
    required this.onSeekEnd,
    required this.onMenu,
    required this.onLock,
    this.panel,
    this.airPlay,
    this.hasEpisodes = true,
  });

  final String title, quality;
  final bool playing, visible, locked;
  final Duration position, duration, buffer;
  final double rate;
  final VoidCallback onBack, onPlay, onLock;
  final VoidCallback? onNext;
  final ValueChanged<double> onSeekStart, onSeekChanged, onSeekEnd;
  final void Function(String, BuildContext) onMenu;
  final Widget? panel;
  final Widget? airPlay;
  final bool hasEpisodes;

  static const _tools = [
    ('投屏', Icons.airplay_rounded),
    ('弹幕', CupertinoIcons.text_bubble),
    ('画中画', Icons.picture_in_picture_alt_rounded),
    ('片段', CupertinoIcons.film),
    ('填充模式', CupertinoIcons.arrow_up_left_arrow_down_right),
    ('音轨', CupertinoIcons.waveform_circle),
    ('字幕', CupertinoIcons.captions_bubble),
  ];

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, bounds) => _build(context, bounds.maxWidth),
    );
  }

  Widget _build(BuildContext context, double width) {
    final media = MediaQuery.of(context);
    final inset = math.min(40.0, width * .047);
    if (locked) {
      return SafeArea(
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.only(left: inset),
            child: RexGlass(
              color: const Color(0x99322F32),
              child: RexIconButton(
                icon: CupertinoIcons.lock_fill,
                label: '解锁控制',
                onTap: onLock,
              ),
            ),
          ),
        ),
      );
    }
    final narrow = width < 560;
    final max = math.max(1.0, duration.inMilliseconds.toDouble());
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              height: 112,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x99000000), Colors.transparent],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              height: panel == null ? 112 : 230,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xC0000000), Colors.transparent],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: media.viewPadding.top + (narrow ? 3 : 22),
          left: math.max(inset, media.viewPadding.left),
          right: math.max(inset, media.viewPadding.right),
          child: Column(
            children: [
              Row(
                children: [
                  RexIconButton(
                    icon: CupertinoIcons.xmark,
                    label: '退出播放',
                    onTap: onBack,
                    size: 22,
                  ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (!narrow)
                    for (final tool in _tools) _tool(tool),
                ],
              ),
              if (narrow)
                Wrap(
                  alignment: WrapAlignment.end,
                  children: [for (final tool in _tools) _tool(tool)],
                ),
            ],
          ),
        ),
        Positioned(
          bottom: media.viewPadding.bottom + 14,
          left: math.max(inset, media.viewPadding.left),
          right: math.max(inset, media.viewPadding.right),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _time(position),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        trackHeight: 5,
                        activeTrackColor: Colors.white,
                        secondaryActiveTrackColor: Colors.white38,
                        inactiveTrackColor: const Color(0x55403942),
                        thumbShape: SliderComponentShape.noThumb,
                        overlayShape: SliderComponentShape.noOverlay,
                        trackShape: const RoundedRectSliderTrackShape(),
                      ),
                      child: Slider(
                        value: position.inMilliseconds.toDouble().clamp(0, max),
                        max: max,
                        secondaryTrackValue: buffer.inMilliseconds
                            .toDouble()
                            .clamp(0, max),
                        onChangeStart: duration > Duration.zero
                            ? onSeekStart
                            : null,
                        onChanged: duration > Duration.zero
                            ? onSeekChanged
                            : null,
                        onChangeEnd: duration > Duration.zero
                            ? onSeekEnd
                            : null,
                        label: playbackClock(position),
                      ),
                    ),
                  ),
                  _time(duration),
                ],
              ),
              if (panel == null)
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    RexIconButton(
                      icon: playing
                          ? CupertinoIcons.pause_fill
                          : CupertinoIcons.play_fill,
                      label: playing ? '暂停' : '播放',
                      onTap: onPlay,
                      size: 25,
                    ),
                    if (onNext != null)
                      RexIconButton(
                        icon: CupertinoIcons.forward_end_fill,
                        label: '下一集',
                        onTap: onNext,
                        size: 19,
                      ),
                    if (!narrow) SizedBox(width: math.max(0, width - 495)),
                    RexIconButton(
                      icon: CupertinoIcons.lock_open,
                      label: '锁定控制',
                      onTap: onLock,
                      size: 17,
                    ),
                    _label(quality, '线路'),
                    if (hasEpisodes) _label('选集', '选集'),
                    _label(
                      rate == 1
                          ? '倍速'
                          : '${rate.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')}×',
                      '倍速',
                    ),
                  ],
                )
              else
                panel!,
            ],
          ),
        ),
      ],
    );
  }

  Widget _tool((String, IconData) tool) {
    if (tool.$1 == '投屏' && airPlay != null) {
      return Semantics(
        label: 'AirPlay',
        child: SizedBox(width: 44, height: 44, child: airPlay),
      );
    }
    return Builder(
      builder: (anchor) => RexIconButton(
        icon: tool.$2,
        label: tool.$1,
        onTap: () => onMenu(tool.$1, anchor),
        size: 20,
      ),
    );
  }

  Widget _label(String label, String action) => Builder(
    builder: (anchor) => CupertinoButton(
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      onPressed: () => onMenu(action, anchor),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
  Widget _time(Duration value) => Text(
    playbackClock(value),
    style: const TextStyle(
      fontSize: 12,
      color: Colors.white,
      fontWeight: FontWeight.w600,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
  );
}

class RexPlayerDock extends StatelessWidget {
  const RexPlayerDock({
    super.key,
    required this.panel,
    required this.detail,
    required this.current,
    required this.season,
    required this.onSeason,
    required this.onClose,
    required this.onChoice,
  });
  final RexPlayerPanel panel;
  final VodDetail detail;
  final EpisodeChoice current;
  final int season;
  final ValueChanged<int> onSeason;
  final VoidCallback onClose;
  final ValueChanged<EpisodeChoice> onChoice;

  @override
  Widget build(BuildContext context) {
    final all = EpisodeChoice.allFor(detail)
        .where((choice) => choice.isPlayable)
        .toList();
    final seasons = all.map((v) => v.season ?? 1).toSet().toList()..sort();
    final byEpisode = <int, EpisodeChoice>{};
    for (final v in all.where((v) => (v.season ?? 1) == season)) {
      final number = v.episode ?? 0;
      if (v.line.group == current.line.group ||
          !byEpisode.containsKey(number)) {
        byEpisode[number] = v;
      }
    }
    final episodes = byEpisode.values.toList()
      ..sort((a, b) => (a.episode ?? 0).compareTo(b.episode ?? 0));
    final lines = all
        .where((v) => EpisodeChoice.isSameEpisode(current, v))
        .toList();
    final choices = panel == RexPlayerPanel.episodes ? episodes : lines;
    return RexGlass(
      radius: 17,
      color: const Color(0xA1343033),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 6, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: panel == RexPlayerPanel.episodes
                      ? SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final s in seasons)
                                CupertinoButton(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                  ),
                                  onPressed: () => onSeason(s),
                                  child: Text(
                                    '${season == s ? '✓  ' : ''}${s == 0 ? '特别篇' : '第 $s 季'}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        )
                      : const Padding(
                          padding: EdgeInsets.only(left: 7),
                          child: Text(
                            '播放资源',
                            style: TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),
                ),
                RexIconButton(
                  icon: CupertinoIcons.xmark,
                  label: '关闭面板',
                  onTap: onClose,
                  size: 17,
                ),
              ],
            ),
            SizedBox(
              height: 100,
              child: choices.isEmpty
                  ? const Center(
                      child: Text(
                        '暂无可播放资源',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : ListView.separated(
                      key: PageStorageKey((panel, season)),
                      scrollDirection: Axis.horizontal,
                      itemCount: choices.length,
                      controller: null,
                      separatorBuilder: (_, _) => const SizedBox(width: 9),
                      itemBuilder: (context, i) {
                        final choice = choices[i];
                        final selected =
                            choice.resource?.id == current.resource?.id;
                        final info = detail.item.episodeInfo(
                          choice.season ?? 1,
                          choice.episode ?? 1,
                        );
                        return panel == RexPlayerPanel.episodes
                            ? _episode(choice, info, selected)
                            : _resource(choice, selected);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _episode(
    EpisodeChoice choice,
    Map<String, dynamic>? info,
    bool selected,
  ) => SizedBox(
    width: 121,
    child: CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () => onChoice(choice),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: selected ? Colors.white : Colors.transparent,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 67,
                width: 119,
                child: RexArtwork(
                  info?['still'] as String? ?? detail.item.heroImage,
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            choice.episodeLabel,
            maxLines: 1,
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
          Text(
            info?['name']?.toString() ?? choice.entry.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    ),
  );

  Widget _resource(EpisodeChoice choice, bool selected) {
    final resource = choice.resource!;
    final size = resource.sizeBytes > 0
        ? '${(resource.sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB'
        : '';
    final bitrate = (resource.bitrate ?? 0) > 0
        ? '${(resource.bitrate! / 1000000).toStringAsFixed(2)} Mbps'
        : '';
    final format = [
      resource.hdr,
      resource.audioCodec?.toUpperCase(),
      size,
      bitrate,
    ].whereType<String>().where((v) => v.isNotEmpty).join(' · ');
    return SizedBox(
      width: 189,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () => onChoice(choice),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: const Color(0xA35A555A),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected ? Colors.white70 : Colors.white24,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${playbackQuality(resource)}  ·  ${choice.line.group}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                format,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  const Icon(
                    CupertinoIcons.cloud,
                    size: 14,
                    color: Color(0xFFB6EC91),
                  ),
                  const SizedBox(width: 5),
                  const Expanded(
                    child: Text(
                      '影院资源',
                      style: TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                  if (selected)
                    const Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      color: Color(0xFFC6F284),
                      size: 15,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
