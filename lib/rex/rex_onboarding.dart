import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_models.dart';
import 'rex_sound.dart';
import 'rex_theme.dart';
import 'rex_widgets.dart';

class RexOnboarding extends StatefulWidget {
  const RexOnboarding({super.key, required this.onDone});
  final Future<void> Function() onDone;
  @override
  State<RexOnboarding> createState() => _RexOnboardingState();
}

class _RexOnboardingState extends State<RexOnboarding>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _pages = PageController();
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );
  int _index = 0;
  bool _sound = true, _finishing = false;
  static const _copy = [
    ('想看的，正在来到眼前', '从海量影片中，发现下一部心动之作。'),
    ('首页，由你定义', '电影、剧集和分类，随手发现，尽兴探索。'),
    ('一张票，收好想看的', '在详情页加入待看，想看的作品随时都能回来。'),
    ('更好时间，一眼掌握', '追剧日历与观看进度，让每一个故事都有下文。'),
    ('连接你的所有资源', '统一浏览，连接属于你的影视世界。'),
    ('每一次观看，都有迹可循', '记录看过的故事，也珍藏投入其中的时光。'),
  ];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!MediaQuery.disableAnimationsOf(context)) {
        _motion.repeat(reverse: true);
      }
      unawaited(RexSound.play('welcome'));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(RexSound.stop());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pages.dispose();
    _motion.dispose();
    unawaited(RexSound.stop());
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await RexSound.stop();
    if (_sound) {
      await RexSound.play('complete');
      await Future<void>.delayed(const Duration(milliseconds: 480));
    }
    if (!mounted) return;
    await widget.onDone();
  }

  void _select(int i) => _pages.animateToPage(
    i,
    duration: const Duration(milliseconds: 420),
    curve: Curves.easeInOutCubic,
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF27304A), Color(0xFF583455), Color(0xFF34232D)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Row(
                children: [
                  RexIconButton(
                    icon: _sound
                        ? CupertinoIcons.speaker_2
                        : CupertinoIcons.speaker_slash,
                    label: _sound ? '关闭引导音效' : '打开引导音效',
                    onTap: () {
                      setState(() => _sound = !_sound);
                      if (!_sound) {
                        unawaited(RexSound.stop());
                      } else {
                        unawaited(RexSound.play('page'));
                      }
                    },
                  ),
                  const Spacer(),
                  RexGlass(
                    color: const Color(0x334C4657),
                    child: RexIconButton(
                      icon: CupertinoIcons.xmark,
                      label: '跳过引导',
                      onTap: _finish,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _copy.length,
                onPageChanged: (i) {
                  setState(() => _index = i);
                  if (_sound) unawaited(RexSound.play('page'));
                },
                itemBuilder: (context, i) => Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: AnimatedBuilder(
                            animation: _motion,
                            builder: (context, _) => Transform.translate(
                              offset: Offset(
                                0,
                                math.sin(_motion.value * math.pi) * 9,
                              ),
                              child: _OnboardScene(index: i),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 9),
                      child: Text(
                        _copy[i].$1,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _copy[i].$2,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.6,
                          color: Color(0xFFE2D9E6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            RexDots(count: _copy.length, index: _index, onSelect: _select),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 3, 20, 7),
              child: SizedBox(
                width: 520,
                child: CupertinoButton.filled(
                  borderRadius: BorderRadius.circular(30),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  onPressed: _finishing
                      ? null
                      : () => _index == 5 ? _finish() : _select(_index + 1),
                  child: Text(
                    _index == 5 ? '开始使用' : '继续',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const Text(
              '影片信息来源 TheMovieDB',
              style: TextStyle(fontSize: 9, color: RexColors.muted),
            ),
            const SizedBox(height: 9),
          ],
        ),
      ),
    ),
  );
}

class _OnboardScene extends StatelessWidget {
  const _OnboardScene({required this.index});
  final int index;
  static const _posters = [
    'posterRed',
    'batman',
    'movie0',
    'posterJade',
    'movie2',
    'movie1',
    'xianNi',
    'mentalist',
  ];
  Widget _poster(int n, {double width = 78}) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(
      width: width,
      height: width * 1.5,
      child: RexArtwork(
        'asset:assets/rex/${_posters[n % _posters.length]}.jpg',
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (index == 0) {
      return LayoutBuilder(
        builder: (context, bounds) {
          final w = bounds.maxWidth, h = bounds.maxHeight;
          return Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < 8; i++)
                Positioned(
                  left: (i % 3) * (w - 80) / 2 + (i.isOdd ? 15 : 0),
                  top: (i ~/ 3) * h / 3 + 16,
                  child: Transform.rotate(
                    angle: (i % 3 - 1) * .08,
                    child: Opacity(
                      opacity: i % 3 == 2 ? .4 : .95,
                      child: _poster(i, width: i % 3 == 2 ? 58 : 72),
                    ),
                  ),
                ),
              const Center(
                child: Icon(
                  CupertinoIcons.moon_stars_fill,
                  size: 82,
                  color: Colors.white,
                ),
              ),
            ],
          );
        },
      );
    }
    if (index == 1) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(3, (i) => _poster(i, width: 84)),
            ),
            const SizedBox(height: 17),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(3, (i) => _poster(i + 3, width: 84)),
            ),
          ],
        ),
      );
    }
    if (index == 2) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 3; i++)
            Transform.translate(
              offset: Offset(i.isOdd ? -14 : 14, 0),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 7,
                  horizontal: 35,
                ),
                child: Transform.rotate(
                  angle: (i - 1) * .025,
                  child: RexTicket(
                    item: VodItem(
                      key: 'intro$i',
                      name: ['嫁金钗', '现在就出发', '蝙蝠侠：黑暗骑士'][i],
                      mediaType: i == 2 ? MediaKind.movie : MediaKind.tv,
                      poster:
                          'asset:assets/rex/${['posterRed', 'posterJade', 'batman'][i]}.jpg',
                      year: [2026, 2023, 2008][i],
                    ),
                    label: '想看的，收好',
                    compact: true,
                    onTap: () {},
                  ),
                ),
              ),
            ),
        ],
      );
    }
    if (index == 3) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: RexGlass(
          radius: 24,
          color: const Color(0xBB51435E),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '追剧日历',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(
                    7,
                    (i) => Column(
                      children: [
                        Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 18,
                            color: i == 3 ? RexColors.purple : Colors.white,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          ['日', '一', '二', '三', '四', '五', '六'][i],
                          style: const TextStyle(
                            fontSize: 11,
                            color: RexColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 27),
                Row(
                  children: [
                    _poster(0, width: 58),
                    const SizedBox(width: 15),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('故事继续，准时相见'),
                          SizedBox(height: 10),
                          Text(
                            '追剧进度，随手记录',
                            style: TextStyle(
                              fontSize: 12,
                              color: RexColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (index == 4) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(CupertinoIcons.cloud, size: 78, color: Color(0xFF87C9FC)),
          const SizedBox(height: 25),
          _poster(3, width: 100),
          const SizedBox(height: 25),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Icon(
                CupertinoIcons.play_rectangle,
                size: 42,
                color: RexColors.purple,
              ),
              Icon(CupertinoIcons.folder, size: 42, color: Color(0xFF77BEEA)),
              Icon(
                CupertinoIcons.desktopcomputer,
                size: 42,
                color: Color(0xFF83C8B0),
              ),
            ],
          ),
        ],
      );
    }
    final bars = List.generate(
      12,
      (i) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Container(
            height: 10 + ((i * 17) % 85).toDouble(),
            decoration: BoxDecoration(
              color: Color.lerp(
                RexColors.purple,
                const Color(0xFFEAD760),
                i / 12,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            '每一帧，都是你的时光',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 22),
          RexGlass(
            radius: 22,
            color: const Color(0xBB4B4356),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('观看统计', style: TextStyle(fontSize: 15)),
                  const SizedBox(height: 30),
                  SizedBox(
                    height: 95,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: bars,
                    ),
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    '看过的故事，都在这里',
                    style: TextStyle(fontSize: 12, color: RexColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
