import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../core/app_log.dart';
import '../core/app_scope.dart';
import '../core/app_theme.dart';
import '../quark/quark_login_screen.dart';
import '../quark/quark_playback_service.dart';
import '../widgets/cinema_surface.dart';
import '../widgets/reference_chrome.dart';
import 'downloads_screen.dart';
import 'library_screen.dart';
import 'account_screen.dart';
import 'support_screen.dart';
import 'playback_settings_screen.dart';
import 'privacy_notification_screen.dart';
import '../core/app_models.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.onServerChanged,
    this.artworkUrl,
    this.artworkItem,
    this.onSearch,
    this.settingsMode = false,
  });

  final VoidCallback onServerChanged;
  final String? artworkUrl;
  final VodItem? artworkItem;
  final VoidCallback? onSearch;
  final bool settingsMode;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool? _hasQuark;
  String? _accountMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshQuarkStatus());
  }

  Future<void> _refreshQuarkStatus() async {
    try {
      final has = await AppScope.of(context).quark.hasAccount;
      if (mounted) setState(() => _hasQuark = has);
    } catch (error) {
      AppLog.error('quark-account', error);
      if (mounted) {
        setState(() {
          _hasQuark = false;
          _accountMessage = '无法读取系统安全存储中的登录状态。';
        });
      }
    }
  }

  Future<void> _loginQuark() async {
    final quark = AppScope.of(context).quark;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => QuarkLoginScreen(playbackService: quark),
      ),
    );
    if (changed == true) {
      await _refreshQuarkStatus();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('夸克账号会话已保存在本机安全存储。')));
      }
    }
  }

  Future<void> _validateQuark() async {
    setState(() => _accountMessage = '正在检查会话…');
    try {
      await AppScope.of(context).quark.validateAccount();
      if (!mounted) return;
      setState(() => _accountMessage = '会话有效，可以播放。');
    } on QuarkException catch (error) {
      if (!mounted) return;
      setState(() {
        _accountMessage = error.userMessage;
        if (error.kind == QuarkFailureKind.authExpired ||
            error.kind == QuarkFailureKind.authRequired) {
          _hasQuark = false;
        }
      });
    } catch (error) {
      AppLog.error('quark-validate', error);
      if (!mounted) return;
      setState(() => _accountMessage = '检查会话失败，请稍后再试。');
    }
  }

  Future<void> _logoutQuark() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('断开夸克账号？'),
        content: const Text('只删除本应用保存的夸克会话，不会删除网盘文件，也不会退出夸克网页端。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('断开'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final quark = AppScope.of(context).quark;
    await quark.accountStore.clear();
    await quark.reloadAccount();
    if (!mounted) return;
    setState(() {
      _hasQuark = false;
      _accountMessage = null;
    });
  }

  Future<void> _editServer() async {
    final services = AppScope.of(context);
    final controller = TextEditingController(text: services.settings.baseUrl);
    String? error;
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('影视接口地址'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: 'http://172.16.3.70:8790',
                  errorText: error,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '只填写 api 所在根地址，不要填写分享链接。局域网 HTTP 只适合测试；正式使用建议 HTTPS。',
                style: TextStyle(
                  color: CinemaColors.faint,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final ok = await services.settings.updateBaseUrl(
                  controller.text,
                );
                if (!ok) {
                  setDialogState(
                    () => error = '请输入有效的 http/https 根地址，不能包含账号、查询参数或片段。',
                  );
                  return;
                }
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (changed == true) {
      widget.onServerChanged();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('接口地址已更新，首页将重新加载。')));
      }
    }
  }

  Future<void> _cleanupTemporaryFiles() async {
    try {
      await AppScope.of(context).quark.cleanupStale();
      if (!mounted) return;
      final remaining = await AppScope.of(context).quark.pendingCleanupCount;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            remaining == 0
                ? '本次可确认的播放临时文件已处理。'
                : '还有 $remaining 项临时记录待处理，请稍后重试。',
          ),
        ),
      );
    } catch (error) {
      AppLog.error('quark-cleanup', error);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('临时文件清理未能全部完成，下次启动会继续重试。')));
    }
  }

  Future<void> _copyLog() async {
    final path = AppLog.filePath;
    if (path.isEmpty || !await File(path).exists()) return;
    final text = await File(path).readAsString();
    await Clipboard.setData(
      ClipboardData(
        text: text.length > 24000 ? text.substring(text.length - 24000) : text,
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('最近的诊断日志已复制。')));
    }
  }

  void _about() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '影院',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                '0.4.1 · 原画随心看',
                style: TextStyle(color: CinemaColors.muted),
              ),
              const SizedBox(height: 24),
              const Text(
                '播放与设备',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              const Text(
                '原生 libmpv / FFmpeg 播放。影片信息页可查看当前解码方式、视频掉帧及系统热状态。原画文件不会被转码，显示输出按屏幕像素匹配。',
                style: TextStyle(height: 1.7, color: CinemaColors.muted),
              ),
              const SizedBox(height: 18),
              const Text(
                '隐私与本地数据',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              const Text(
                '夸克登录保存在系统安全存储。收藏、观看进度和下载保存在本机。诊断日志会过滤 Cookie、密码和私有地址。',
                style: TextStyle(height: 1.7, color: CinemaColors.muted),
              ),
              const SizedBox(height: 18),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.copy_outlined),
                title: const Text('复制最近诊断日志'),
                subtitle: const Text('用于排查起播、卡顿和发热问题'),
                onTap: AppLog.filePath.isEmpty ? null : _copyLog,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.code_rounded),
                title: const Text('开源组件许可'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: '影院',
                  applicationVersion: '0.4.1',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _settings() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PosterSurface(
        imageUrl: widget.artworkUrl,
        child: ProfileScreen(
          onServerChanged: widget.onServerChanged,
          artworkUrl: widget.artworkUrl,
          artworkItem: widget.artworkItem,
          settingsMode: true,
        ),
      ),
    ),
  );

  void _account(AccountPage page) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => AccountScreen(page: page, artwork: widget.artworkItem),
    ),
  );
  void _help() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => SupportScreen(artworkUrl: widget.artworkUrl),
    ),
  );
  void _playbackSettings() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => PlaybackSettingsScreen(artworkUrl: widget.artworkUrl),
    ),
  );

  void _privacy({bool notifications = false}) => Navigator.push(context,
    MaterialPageRoute<void>(builder: (_) => PrivacyNotificationScreen(
      artworkUrl: widget.artworkUrl, notifications: notifications)));

  @override
  Widget build(BuildContext context) {
    if (widget.settingsMode) return _buildSettings();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 110),
          children: [
            ReferenceHeader(
              onSearch: widget.onSearch ?? () {},
              onMore: _settings,
            ),
            const SizedBox(height: 48),
            InkWell(
              onTap: () => _account(AccountPage.phone),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 39,
                    backgroundColor: Color(0x80F8EFE6),
                    child: Icon(
                      CupertinoIcons.person_fill,
                      size: 46,
                      color: CinemaColors.accent,
                    ),
                  ),
                  const SizedBox(width: 18),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '点击登录',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '游客 · 记录保存在本机',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xDEFFFFFF),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    CupertinoIcons.chevron_right,
                    color: Colors.white,
                    size: 18,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            CinemaGlass(
              padding: const EdgeInsets.symmetric(vertical: 23),
              child: Row(
                children: [
                  _shortcut(CupertinoIcons.clock, '观看历史', () => _library(1)),
                  _shortcut(CupertinoIcons.heart, '我的收藏', () => _library(0)),
                  _shortcut(
                    CupertinoIcons.arrow_down_circle,
                    '我的下载',
                    _downloads,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            CinemaGlass(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                children: [
                  _row(CupertinoIcons.gear, '设置', '', _settings),
                  const Divider(height: 1, color: Color(0x22765440)),
                  _row(CupertinoIcons.question_circle, '帮助与反馈', '', _help),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shortcut(IconData icon, String text, VoidCallback action) => Expanded(
    child: InkWell(
      onTap: action,
      child: Column(
        children: [
          Icon(icon, size: 27, color: CinemaColors.accent),
          const SizedBox(height: 9),
          Text(
            text,
            style: const TextStyle(fontSize: 13, color: CinemaColors.accent),
          ),
        ],
      ),
    ),
  );

  Widget _buildSettings() => Scaffold(
    backgroundColor: Colors.transparent,
    body: Column(
      children: [
        const ReferencePageHeader(title: '设置'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
            children: [
              CinemaGlass(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    radius: 25,
                    backgroundColor: Color(0x55FFFFFF),
                    child: Icon(
                      CupertinoIcons.person,
                      color: CinemaColors.accent,
                    ),
                  ),
                  title: const Text('游客'),
                  subtitle: const Text(
                    '编辑个人资料',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(CupertinoIcons.chevron_right, size: 17),
                  onTap: () => _account(AccountPage.profile),
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: '账号与安全',
                children: [
                  _row(
                    CupertinoIcons.person_crop_circle,
                    '账号与安全',
                    '',
                    () => _account(AccountPage.security),
                  ),
                  _row(
                    CupertinoIcons.cloud,
                    '夸克播放账号',
                    _hasQuark == true ? '已连接' : '连接后播放原画',
                    _hasQuark == true ? _validateQuark : _loginQuark,
                  ),
                  if (_accountMessage != null)
                    Text(
                      _accountMessage!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  if (_hasQuark == true)
                    Row(
                      children: [
                        TextButton(
                          onPressed: _loginQuark,
                          child: const Text('重新登录'),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _logoutQuark,
                          child: const Text('断开连接'),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _SectionCard(
                title: '播放与通知',
                children: [
                  _row(
                    CupertinoIcons.play_circle,
                    '播放设置',
                    '原画 · 自动硬件解码',
                    _playbackSettings,
                  ),
                  _row(CupertinoIcons.bell, '通知设置', '', () => _privacy(notifications: true)),
                  _row(
                    CupertinoIcons.link,
                    '影视接口',
                    AppScope.of(context).settings.baseUrl,
                    _editServer,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SectionCard(
                title: '隐私与存储',
                children: [
                  _row(
                    CupertinoIcons.lock,
                    '隐私与权限',
                    '',
                    _privacy,
                  ),
                  _row(
                    CupertinoIcons.trash,
                    '清理播放临时文件',
                    '清理本应用创建的网盘临时文件',
                    _cleanupTemporaryFiles,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SectionCard(
                title: '帮助',
                children: [
                  _row(CupertinoIcons.question_circle, '帮助与反馈', '', _help),
                  _row(CupertinoIcons.info_circle, '关于影院', '0.4.1', _about),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _row(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: CinemaColors.accent),
    title: Text(title),
    subtitle: subtitle.isEmpty
        ? null
        : Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: CinemaColors.muted),
          ),
    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
    onTap: onTap,
  );
  void _library(int index) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PosterSurface(
        imageUrl: widget.artworkUrl,
        child: LibraryScreen(initialIndex: index),
      ),
    ),
  );
  Future<void> _downloads() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const DownloadsScreen()));
    if (mounted) setState(() {});
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => CinemaGlass(
    radius: 24,
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    ),
  );
}
