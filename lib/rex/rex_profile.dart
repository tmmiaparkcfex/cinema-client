import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_models.dart';
import '../core/app_scope.dart';
import 'rex_catalog.dart';
import 'rex_home.dart';
import 'rex_interactions.dart';
import 'rex_metadata.dart';
import 'rex_scope.dart';
import 'rex_store.dart';
import 'rex_theme.dart';
import 'rex_widgets.dart';

class RexProfile extends StatefulWidget {
  const RexProfile({
    super.key,
    required this.catalog,
    required this.onOpen,
    required this.onList,
    required this.onSearch,
  });
  final RexCatalog catalog;
  final ValueChanged<VodItem> onOpen;
  final void Function(String, List<VodItem>) onList;
  final VoidCallback onSearch;
  @override
  State<RexProfile> createState() => _RexProfileState();
}

class _RexProfileState extends State<RexProfile> {
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  int _stat = 0;
  final _stats = PageController();
  @override
  void dispose() {
    _stats.dispose();
    super.dispose();
  }

  Future<void> _edit(BuildContext anchor) async {
    final store = RexScope.of(context);
    final key = await showRexMenu(
      context,
      anchor: anchor,
      entries: [
        for (final pair in [
          ('calendar', '追剧日历'),
          ('stats', '观看统计'),
          ('history', '历史观看'),
          ('watch', '待看列表'),
        ])
          RexMenuEntry(
            pair.$1,
            pair.$2,
            selected: store.modules[pair.$1] == true,
          ),
      ],
    );
    if (key != null) await store.toggleModule(key);
  }

  Future<void> _month() async {
    final chosen = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => RexMonth(selected: _day),
    );
    if (chosen != null && mounted) setState(() => _day = chosen);
  }

  @override
  Widget build(BuildContext context) {
    final store = RexScope.of(context), playback = AppScope.of(context).store;
    final start = _day.subtract(Duration(days: _day.weekday % 7));
    final want = store.shelf.values
        .where((v) => v.status == ShelfStatus.want)
        .map((v) => v.item)
        .toList();
    final watching = store.shelf.values
        .where((v) => v.status == ShelfStatus.watching)
        .map((v) => v.item)
        .toList();
    final history = uniqueTitles(playback.history.map((v) => v.toItem()));
    final onDay = <(VodItem, Map<String, dynamic>)>[];
    for (final title in [...want, ...watching]) {
      final item =
          widget.catalog.items
              .where((v) => v.identityKey == title.identityKey)
              .firstOrNull ??
          title;
      for (final episode in item.episodes) {
        final date = DateTime.tryParse(episode['airDate']?.toString() ?? '');
        if (date != null && DateUtils.isSameDay(date, _day)) {
          onDay.add((item, episode));
        }
      }
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3C354F), Color(0xFF5B3B5D), Color(0xFF302838)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: ListView(
          key: const PageStorageKey('rex-profile-scroll'),
          padding: const EdgeInsets.fromLTRB(15, 9, 15, 115),
          children: [
            Row(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: RexArtwork('asset:assets/rex/avatar.jpg'),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '默认环境',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Builder(
                  builder: (anchor) => CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    onPressed: () => _edit(anchor),
                    child: const Text(
                      '编辑',
                      style: TextStyle(fontSize: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            if (store.modules['calendar'] == true) ...[
              Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: CupertinoButton(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        minimumSize: Size.zero,
                        onPressed: () =>
                            setState(() => _day = start.add(Duration(days: i))),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 5,
                          ),
                          decoration: BoxDecoration(
                            color:
                                DateUtils.isSameDay(
                                  start.add(Duration(days: i)),
                                  _day,
                                )
                                ? const Color(0xFFAAA0B3)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Column(
                            children: [
                              Text(
                                '${start.add(Duration(days: i)).day}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                ['周日', '周一', '周二', '周三', '周四', '周五', '周六'][i],
                                style: TextStyle(
                                  fontSize: 9,
                                  color:
                                      DateUtils.isSameDay(
                                        start.add(Duration(days: i)),
                                        DateTime.now(),
                                      )
                                      ? const Color(0xFFFF9FBB)
                                      : Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  RexIconButton(
                    icon: CupertinoIcons.arrow_up_right_square,
                    label: '打开追剧日历',
                    onTap: _month,
                  ),
                ],
              ),
              _Panel(
                child: onDay.isEmpty
                    ? const RexEmpty('这天没有播出的剧', subtitle: '换一天看看，或者在日历里添加追剧')
                    : Column(
                        children: [
                          for (final row in onDay)
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              onTap: () => widget.onOpen(row.$1),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 44,
                                  child: RexArtwork(row.$1.posterImage),
                                ),
                              ),
                              title: Text(
                                row.$1.name,
                                style: const TextStyle(fontSize: 13),
                              ),
                              subtitle: Text(
                                row.$2['name']?.toString() ??
                                    '第 ${row.$2['episode']} 集',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 22),
            ],
            if (store.modules['stats'] == true) ...[
              SizedBox(
                height: 180,
                child: PageView.builder(
                  controller: _stats,
                  itemCount: 3,
                  onPageChanged: (i) => setState(() => _stat = i),
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: _StatsPanel(index: i, store: store),
                  ),
                ),
              ),
              Center(
                child: RexDots(
                  count: 3,
                  index: _stat,
                  onSelect: (i) => _stats.animateToPage(
                    i,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                  ),
                ),
              ),
              const SizedBox(height: 5),
            ],
            if (store.modules['history'] == true) ...[
              _Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 7, 8, 0),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('历史观看', style: TextStyle(fontSize: 13)),
                          ),
                          if (history.isNotEmpty)
                            RexIconButton(
                              icon: CupertinoIcons.chevron_right,
                              label: '全部观看历史',
                              onTap: () => widget.onList('历史观看', history),
                              size: 16,
                            ),
                        ],
                      ),
                    ),
                    if (history.isEmpty)
                      const RexEmpty(
                        '暂无观看记录',
                        icon: CupertinoIcons.square_grid_2x2,
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: RexPosterRow(
                          items: history.take(8).toList(),
                          onOpen: widget.onOpen,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 15),
            ],
            if (store.modules['watch'] == true) ...[
              Row(
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => widget.onList('待看', want),
                    child: Row(
                      children: [
                        Text(
                          '待看 ${want.length}',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                        const Icon(
                          CupertinoIcons.chevron_right,
                          color: Colors.white,
                          size: 17,
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Builder(
                    builder: (anchor) => RexIconButton(
                      icon: CupertinoIcons.ellipsis,
                      label: '片单菜单',
                      onTap: () async {
                        final result = await showRexMenu(
                          context,
                          anchor: anchor,
                          entries: const [
                            RexMenuEntry(
                              'add',
                              '添加作品',
                              icon: CupertinoIcons.add,
                            ),
                            RexMenuEntry(
                              'watching',
                              '在看',
                              icon: CupertinoIcons.play_rectangle,
                            ),
                            RexMenuEntry(
                              'favorites',
                              '收藏',
                              icon: CupertinoIcons.heart,
                            ),
                          ],
                        );
                        if (!mounted) return;
                        if (result == 'add') widget.onSearch();
                        if (result == 'watching') widget.onList('在看', watching);
                        if (result == 'favorites') {
                          widget.onList('收藏', store.favorites.values.toList());
                        }
                      },
                    ),
                  ),
                ],
              ),
              if (want.isEmpty)
                _Panel(
                  child: RexEmpty(
                    '把想看的故事收进来',
                    icon: CupertinoIcons.ticket,
                    subtitle: '在影片详情里加入待看',
                  ),
                )
              else
                for (final item in want)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: RexTicket(
                      item: item,
                      onTap: () => widget.onOpen(item),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: const Color(0x665E526B),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0x16FFFFFF)),
    ),
    child: child,
  );
}

class _StatsPanel extends StatelessWidget {
  const _StatsPanel({required this.index, required this.store});
  final int index;
  final RexStore store;
  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final start = index == 0
        ? today
        : index == 1
        ? today.subtract(const Duration(days: 6))
        : today.subtract(Duration(days: today.weekday - 1));
    final end = today.add(const Duration(days: 1));
    final days = List.generate(
      index == 0 ? 24 : 7,
      (i) => index == 0
          ? 0
          : store.episodesIn(
              start.add(Duration(days: i)),
              start.add(Duration(days: i + 1)),
            ),
    );
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  ['今天', '最近 7 天', '本周观看'][index],
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  dateLabel(today),
                  style: const TextStyle(fontSize: 11, color: RexColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 23),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${store.episodesIn(start, end)} 集',
                      style: const TextStyle(
                        fontSize: 29,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Text(
                      '已标记看过',
                      style: TextStyle(fontSize: 11, color: RexColors.muted),
                    ),
                  ],
                ),
                const SizedBox(width: 25),
                Expanded(
                  child: SizedBox(
                    height: 70,
                    child: CustomPaint(painter: _StatsChart(days, index == 1)),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              index == 0
                  ? '00:00                                    24:00'
                  : '周一                                  周日',
              style: const TextStyle(fontSize: 9, color: RexColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsChart extends CustomPainter {
  _StatsChart(this.values, this.line);
  final List<int> values;
  final bool line;
  @override
  void paint(Canvas canvas, Size size) {
    final maxValue = math.max(1, values.fold<int>(0, math.max));
    final paint = Paint()..color = const Color(0xFFB38AF7);
    final points = [
      for (var i = 0; i < values.length; i++)
        Offset(
          i * size.width / math.max(1, values.length - 1),
          size.height - values[i] / maxValue * (size.height - 7),
        ),
    ];
    if (line) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      final area = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x668B5CE9), Color(0x058B5CE9)],
          ).createShader(Offset.zero & size),
      );
    } else {
      final width = size.width / values.length;
      for (var i = 0; i < values.length; i++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              i * width + 2,
              points[i].dy - 3,
              math.max(2, width - 5),
              math.max(3, size.height - points[i].dy),
            ),
            const Radius.circular(3),
          ),
          paint
            ..color = values[i] == 0
                ? const Color(0xFF8B7E94)
                : const Color(0xFFB38AF7),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_StatsChart oldDelegate) =>
      oldDelegate.values != values || oldDelegate.line != line;
}

class RexMonth extends StatefulWidget {
  const RexMonth({super.key, required this.selected});
  final DateTime selected;
  @override
  State<RexMonth> createState() => _RexMonthState();
}

class _RexMonthState extends State<RexMonth> {
  late DateTime _month = DateTime(widget.selected.year, widget.selected.month);
  @override
  Widget build(BuildContext context) {
    final firstWeekday = _month.weekday % 7,
        count = DateTime(_month.year, _month.month + 1, 0).day;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 35,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white30,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            Row(
              children: [
                RexIconButton(
                  icon: CupertinoIcons.chevron_left,
                  label: '上个月',
                  onTap: () => setState(
                    () => _month = DateTime(_month.year, _month.month - 1),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${_month.year} 年 ${_month.month} 月',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                RexIconButton(
                  icon: CupertinoIcons.chevron_right,
                  label: '下个月',
                  onTap: () => setState(
                    () => _month = DateTime(_month.year, _month.month + 1),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                for (final label in ['日', '一', '二', '三', '四', '五', '六'])
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 12,
                          color: RexColors.muted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: firstWeekday + count,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemBuilder: (context, i) {
                if (i < firstWeekday) return const SizedBox();
                final date = DateTime(
                  _month.year,
                  _month.month,
                  i - firstWeekday + 1,
                );
                return CupertinoButton(
                  padding: EdgeInsets.zero,
                  color: DateUtils.isSameDay(date, widget.selected)
                      ? RexColors.purple
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  onPressed: () => Navigator.pop(context, date),
                  child: Text(
                    '${date.day}',
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                );
              },
            ),
            CupertinoButton(
              onPressed: () =>
                  Navigator.pop(context, DateUtils.dateOnly(DateTime.now())),
              child: const Text('今天'),
            ),
          ],
        ),
      ),
    );
  }
}
