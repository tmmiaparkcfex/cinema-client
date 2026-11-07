import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_models.dart';
import '../core/app_scope.dart';
import 'rex_browse.dart';
import 'rex_catalog.dart';
import 'rex_detail.dart';
import 'rex_home.dart';
import 'rex_onboarding.dart';
import 'rex_profile.dart';
import 'rex_search.dart';
import 'rex_store.dart';
import 'rex_theme.dart';
import 'rex_widgets.dart';

class RexEntry extends StatelessWidget {
  const RexEntry({super.key, required this.store, required this.initialHome});
  final RexStore store;
  final HomeFeed? initialHome;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => store.onboarded
        ? RexShell(initialHome: initialHome)
        : RexOnboarding(onDone: store.finishOnboarding),
  );
}

class RexShell extends StatefulWidget {
  const RexShell({super.key, required this.initialHome});
  final HomeFeed? initialHome;
  @override
  State<RexShell> createState() => _RexShellState();
}

class _RexShellState extends State<RexShell> {
  RexCatalog? _catalog;
  int _tab = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_catalog != null) return;
    final services = AppScope.of(context);
    _catalog = RexCatalog(services, widget.initialHome);
    services.settings.addListener(_sourceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_catalog!.refresh());
    });
  }

  void _sourceChanged() {
    _catalog?.changeSource();
  }

  @override
  void dispose() {
    _catalog?.services.settings.removeListener(_sourceChanged);
    _catalog?.dispose();
    super.dispose();
  }

  void _open(VodItem item, {bool fullScreen = false}) {
    FocusManager.instance.primaryFocus?.unfocus();
    Widget detail([ScrollController? controller]) => RexDetail(
      item: item,
      related: _catalog!.items,
      onOpen: (v) => _open(v, fullScreen: true),
      onSearch: _search,
      scrollController: controller,
      sheet: !fullScreen,
    );
    if (fullScreen) {
      Navigator.of(context)
          .push(CupertinoPageRoute<void>(builder: (_) => detail()));
    } else {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => DraggableScrollableSheet(
          initialChildSize: .98,
          minChildSize: .55,
          maxChildSize: .98,
          expand: false,
          shouldCloseOnMinExtent: true,
          builder: (_, controller) => ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: detail(controller),
          ),
        ),
      );
    }
  }

  void _search([String query = '']) => Navigator.of(context).push(
    CupertinoPageRoute<void>(
      builder: (_) =>
          RexSearch(catalog: _catalog!, initialQuery: query, onOpen: _open),
    ),
  );
  void _browse(
    String title,
    List<VodItem> items,
    MediaKind? kind,
    String? category,
    String? studio,
  ) => Navigator.of(context).push(
    CupertinoPageRoute<void>(
      builder: (_) => RexBrowse(
        title: title,
        initial: items,
        kind: kind,
        category: category,
        studio: studio,
        onOpen: (v) => _open(v, fullScreen: true),
      ),
    ),
  );
  void _list(String title, List<VodItem> items) => Navigator.of(context).push(
    CupertinoPageRoute<void>(
      builder: (_) => RexBrowse(
        title: title,
        initial: items,
        localOnly: true,
        onOpen: (v) => _open(v, fullScreen: true),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final catalog = _catalog!;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: _tab,
              children: [
                RexHome(catalog: catalog, onOpen: _open, onBrowse: _browse),
                ListenableBuilder(
                  listenable: Listenable.merge([
                    catalog,
                    catalog.services.store,
                  ]),
                  builder: (_, _) => RexProfile(
                    catalog: catalog,
                    onOpen: _open,
                    onList: _list,
                    onSearch: _search,
                  ),
                ),
                const _RexLibrary(),
                const RexSettings(),
              ],
            ),
          ),
          Positioned(
            bottom: MediaQuery.paddingOf(context).bottom + 7,
            left: 18,
            right: 18,
            child: Center(
              child: SizedBox(
                width: math.min(370, MediaQuery.sizeOf(context).width - 36),
                child: Row(
                  children: [
                    Expanded(
                      child: RexGlass(
                        color: const Color(0xC26A6068),
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: Row(
                            children: [
                              for (var i = 0; i < 4; i++)
                                Expanded(
                                  child: Semantics(
                                    selected: _tab == i,
                                    button: true,
                                    label: ['发现', '我的', '资源库', '设置'][i],
                                    child: CupertinoButton(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(44, 46),
                                      onPressed: () => setState(() => _tab = i),
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _tab == i
                                              ? const Color(0x55FFFFFF)
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (i == 0)
                                              ClipOval(
                                                child: SizedBox(
                                                  width: 23,
                                                  height: 23,
                                                  child: RexArtwork(
                                                    'asset:assets/rex/discoverAvatar.jpg',
                                                  ),
                                                ),
                                              )
                                            else
                                              Icon(
                                                [
                                                  CupertinoIcons
                                                      .moon_stars_fill,
                                                  CupertinoIcons
                                                      .person_crop_circle_fill,
                                                  CupertinoIcons.tray_2_fill,
                                                  CupertinoIcons.gear_solid,
                                                ][i],
                                                color: Colors.white,
                                                size: 23,
                                              ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${['发现', '我的', '资源库', '设置'][i]}${_tab == i ? ' ⌃' : ''}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 9,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    RexGlass(
                      color: const Color(0xD36A6068),
                      child: SizedBox(
                        width: 55,
                        height: 55,
                        child: RexIconButton(
                          icon: CupertinoIcons.search,
                          label: '搜索',
                          onTap: _search,
                          size: 27,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RexLibrary extends StatelessWidget {
  const _RexLibrary();
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 28, 20, 0),
          child: Text(
            '资源库',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
          ),
        ),
        const Expanded(
          child: Center(
            child: RexEmpty(
              '资源库将在后续版本开放',
              subtitle: '目前可在发现页浏览影院接口中的影片',
              icon: CupertinoIcons.tray_2,
            ),
          ),
        ),
      ],
    ),
  );
}

class RexSettings extends StatelessWidget {
  const RexSettings({super.key});
  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 115),
      children: [
        const Text(
          '设置',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 27),
        RexGlass(
          radius: 22,
          color: const Color(0xFF504158),
          child: Column(
            children: [
              _row(
                CupertinoIcons.link,
                '影视接口',
                () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => const _SourceSettings(),
                  ),
                ),
              ),
              const Divider(height: 1, indent: 48, color: Color(0x18FFFFFF)),
              _row(
                CupertinoIcons.sparkles,
                '重新认识影院',
                () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (context) => RexOnboarding(
                      onDone: () async {
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const RexEmpty('其他设置将在后续版本完善', icon: CupertinoIcons.gear),
        const SizedBox(height: 15),
        const Center(
          child: Text(
            '影视资料来源 TheMovieDB',
            style: TextStyle(fontSize: 11, color: RexColors.muted),
          ),
        ),
      ],
    ),
  );
  Widget _row(IconData icon, String label, VoidCallback action) =>
      CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        onPressed: action,
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 19),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 15, color: Colors.white),
              ),
            ),
            const Icon(
              CupertinoIcons.chevron_right,
              size: 15,
              color: RexColors.muted,
            ),
          ],
        ),
      );
}

class _SourceSettings extends StatefulWidget {
  const _SourceSettings();
  @override
  State<_SourceSettings> createState() => _SourceSettingsState();
}

class _SourceSettingsState extends State<_SourceSettings> {
  final _text = TextEditingController();
  bool _initialized = false;
  String? _error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _text.text = AppScope.of(context).settings.baseUrl;
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('影视接口', style: TextStyle(fontSize: 18))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('影院接口地址', style: TextStyle(fontSize: 14)),
        const SizedBox(height: 12),
        CupertinoTextField(
          controller: _text,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textCapitalization: TextCapitalization.none,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: RexColors.card,
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFFFF91A8), fontSize: 12),
            ),
          ),
        const SizedBox(height: 20),
        CupertinoButton.filled(
          borderRadius: BorderRadius.circular(25),
          onPressed: () async {
            final settings = AppScope.of(context).settings;
            final success = await settings.updateBaseUrl(_text.text);
            if (!context.mounted) return;
            if (success) {
              Navigator.pop(context);
            } else {
              setState(() => _error = '请输入有效的 http 或 https 接口根地址');
            }
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
}
