import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_models.dart';
import '../core/app_theme.dart';
import '../widgets/cinema_surface.dart';
import 'home_screen.dart';
import 'catalog_screen.dart';
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
  String? _artwork;
  VodItem? _featured;
  @override
  void initState() {
    super.initState();
    _initialHome = widget.initialHome;
    final item = _initialHome?.all.firstOrNull;
    _featured = item;
    _artwork = item?.poster ?? item?.backdrop;
  }

  void _search() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          PosterSurface(imageUrl: _artwork, child: const SearchScreen()),
    ),
  );
  void _serverChanged() => setState(() {
    _homeGeneration++;
    _initialHome = null;
    _artwork = null;
    _featured = null;
    _index = 0;
  });
  @override
  Widget build(BuildContext context) => PosterSurface(
    imageUrl: _artwork,
    child: Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(
            key: ValueKey('home-$_homeGeneration'),
            initialFeed: _initialHome,
            onOpenSearch: _search,
            onOpenProfile: () => setState(() => _index = 2),
            onFeaturedChanged: (item) {
              final url = item.poster ?? item.backdrop;
              if (url != _artwork) {
                setState(() {
                  _artwork = url;
                  _featured = item;
                });
              }
            },
          ),
          CatalogScreen(
            key: ValueKey('catalog-$_homeGeneration'),
            kind: MediaKind.movie,
            title: '片库',
            embedded: true,
            onSearch: _search,
            onMore: () => setState(() => _index = 2),
          ),
          ProfileScreen(
            onServerChanged: _serverChanged,
            artworkUrl: _artwork,
            artworkItem: _featured,
            onSearch: _search,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
          child: CinemaGlass(
            radius: 32,
            child: SizedBox(
              height: 62,
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++)
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _index = i),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                          (_index == i ? [
                            CupertinoIcons.house_fill,
                            CupertinoIcons.square_grid_2x2_fill,
                            CupertinoIcons.person_fill,
                          ] : [
                            CupertinoIcons.house,
                            CupertinoIcons.square_grid_2x2,
                            CupertinoIcons.person,
                          ])[i],
                              size: 23,
                              color: _index == i
                                  ? CinemaColors.accent
                                  : CinemaColors.muted,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              ['首页', '片库', '我的'][i],
                              style: TextStyle(
                                fontSize: 11,
                                color: _index == i
                                    ? CinemaColors.accent
                                    : CinemaColors.muted,
                                fontWeight: _index == i
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
