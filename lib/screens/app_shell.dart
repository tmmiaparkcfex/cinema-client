import 'package:flutter/material.dart';

import '../core/app_models.dart';
import '../core/app_theme.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.initialHome});

  final HomeFeed? initialHome;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  int _homeGeneration = 0;
  HomeFeed? _initialHome;

  @override
  void initState() {
    super.initState();
    _initialHome = widget.initialHome;
  }

  void _select(int index) {
    if (_index == index) return;
    setState(() => _index = index);
  }

  void _serverChanged() {
    setState(() {
      _homeGeneration++;
      _initialHome = null;
      _index = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final pages = <Widget>[
          HomeScreen(
            key: ValueKey('home-$_homeGeneration'),
            initialFeed: _initialHome,
            onOpenSearch: () => _select(1),
            onOpenProfile: () => _select(3),
          ),
          const SearchScreen(),
          const LibraryScreen(),
          ProfileScreen(onServerChanged: _serverChanged),
        ];
        if (wide) {
          return Scaffold(
            backgroundColor: CinemaColors.background,
            body: Row(
              children: [
                _SideNavigation(index: _index, onSelect: _select),
                const VerticalDivider(width: 1),
                Expanded(
                  child: IndexedStack(index: _index, children: pages),
                ),
              ],
            ),
          );
        }
        return Scaffold(
          backgroundColor: CinemaColors.background,
          body: IndexedStack(index: _index, children: pages),
          bottomNavigationBar: NavigationBar(
            height: 64,
            backgroundColor: const Color(0xF20A0B0E),
            indicatorColor: const Color(0x33E50914),
            selectedIndex: _index,
            onDestinationSelected: _select,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded, color: Colors.white),
                label: '首页',
              ),
              NavigationDestination(
                icon: Icon(Icons.search_rounded),
                label: '搜索',
              ),
              NavigationDestination(
                icon: Icon(Icons.bookmark_border_rounded),
                selectedIcon: Icon(Icons.bookmark_rounded, color: Colors.white),
                label: '我的片单',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded, color: Colors.white),
                label: '我的',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SideNavigation extends StatelessWidget {
  const _SideNavigation({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const _items = [
    (Icons.home_outlined, '首页'),
    (Icons.search_rounded, '搜索'),
    (Icons.bookmark_border_rounded, '我的片单'),
    (Icons.person_outline_rounded, '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 206,
      color: const Color(0xFF0A0B0E),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 26, 20, 34),
              child: Text(
                'CINEMA',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.5,
                ),
              ),
            ),
            for (var i = 0; i < _items.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                child: Material(
                  color: i == index
                      ? const Color(0x1AE50914)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(7),
                    onTap: () => onSelect(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _items[i].$1,
                            size: 21,
                            color: i == index
                                ? Colors.white
                                : CinemaColors.muted,
                          ),
                          const SizedBox(width: 14),
                          Text(
                            _items[i].$2,
                            style: TextStyle(
                              color: i == index
                                  ? Colors.white
                                  : CinemaColors.muted,
                              fontWeight: i == index
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          if (i == index) ...[
                            const Spacer(),
                            Container(
                              width: 3,
                              height: 16,
                              decoration: BoxDecoration(
                                color: CinemaColors.red,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Text(
                '0.2.0 · 内测版\n播放使用观看者自己的账号',
                style: TextStyle(
                  color: CinemaColors.faint,
                  fontSize: 10,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
