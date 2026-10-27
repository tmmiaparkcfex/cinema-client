import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_log.dart';
import '../core/app_scope.dart';
import '../core/app_theme.dart';
import '../quark/quark_login_screen.dart';
import '../quark/quark_playback_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.onServerChanged});

  final VoidCallback onServerChanged;

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

  void _copyLogPath() {
    final path = AppLog.filePath;
    if (path.isEmpty) return;
    Clipboard.setData(ClipboardData(text: path));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('日志路径已复制。')));
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: wide
          ? AppBar(
              title: const Text(
                '我的',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              leading: const SizedBox(width: 52),
              automaticallyImplyLeading: false,
            )
          : AppBar(title: const Text('我的')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(wide ? 52 : 18, 10, wide ? 52 : 18, 30),
        children: [
          _SectionCard(
            title: '账号与设备',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.cloud_outlined,
                  color: CinemaColors.muted,
                ),
                title: const Text('夸克账号'),
                subtitle: Text(
                  _hasQuark == true ? '已在本机连接 · 播放使用你的账号和流量' : '未连接 · 播放前需要授权',
                  style: const TextStyle(
                    color: CinemaColors.muted,
                    fontSize: 12,
                  ),
                ),
                trailing: _hasQuark == true
                    ? TextButton(
                        onPressed: _logoutQuark,
                        child: const Text('断开'),
                      )
                    : FilledButton(
                        onPressed: _loginQuark,
                        child: const Text('连接'),
                      ),
              ),
              if (_hasQuark == true) ...[
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: _validateQuark,
                      child: const Text('检查会话'),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: _loginQuark,
                      child: const Text('重新登录'),
                    ),
                  ],
                ),
                if (_accountMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _accountMessage!,
                    style: const TextStyle(
                      color: CinemaColors.muted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
              const Divider(height: 26),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.devices_outlined,
                  color: CinemaColors.muted,
                ),
                title: Text('跨设备接续'),
                subtitle: Text(
                  '未接入。当前观看进度只保存在本机；夸克登录不等于观看记录同步。',
                  style: TextStyle(
                    color: CinemaColors.faint,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                trailing: _StatusTag(text: '未完成'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: '影视接口',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.dns_outlined,
                  color: CinemaColors.muted,
                ),
                title: const Text('接口根地址'),
                subtitle: SelectableText(
                  services.settings.baseUrl,
                  style: const TextStyle(
                    color: CinemaColors.muted,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                trailing: TextButton(
                  onPressed: _editServer,
                  child: const Text('修改'),
                ),
              ),
              if (services.settings.baseUrl.startsWith('http://'))
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '当前为 HTTP 明文接口。只建议在可信局域网测试；正式部署请配置 HTTPS。',
                    style: TextStyle(
                      color: Color(0xFFD8A35F),
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ),
              const Divider(height: 26),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.cleaning_services_outlined,
                  color: CinemaColors.muted,
                ),
                title: const Text('清理本应用临时文件'),
                subtitle: const Text(
                  '只处理本应用记录、由专用目录创建的文件；不删除用户原有文件。',
                  style: TextStyle(
                    color: CinemaColors.faint,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                trailing: TextButton(
                  onPressed: _cleanupTemporaryFiles,
                  child: const Text('清理'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: '当前能力边界',
            children: [
              const _CapabilityRow(label: '首页、详情、搜索、片单、本地续播', status: '已实现'),
              const _CapabilityRow(
                label: '设备内夸克授权、专用目录转存、原生 libmpv 起播',
                status: '代码已实现',
              ),
              const _CapabilityRow(
                label: '内嵌音轨与字幕切换、倍速、比例、线路切换',
                status: '代码已实现',
              ),
              const _CapabilityRow(
                label: 'iPhone 真机 4K/HDR/功耗与真实账号闭环',
                status: '未验证',
              ),
              const _CapabilityRow(
                label: '在线字幕、截图/GIF/OCR、调色、均衡器、投屏',
                status: '未实现',
              ),
              const _CapabilityRow(label: '观看记录和偏好跨设备同步', status: '未实现'),
              const _CapabilityRow(
                label: 'Android 手机 / Android TV / Windows 正式产物',
                status: '未构建',
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: '诊断',
            children: [
              const Text(
                '应用日志不记录 Cookie、密码、私有播放地址或分享地址。',
                style: TextStyle(
                  color: CinemaColors.muted,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 10),
              if (AppLog.filePath.isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        AppLog.filePath,
                        style: const TextStyle(
                          color: CinemaColors.faint,
                          fontFamily: 'monospace',
                          fontSize: 10,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '复制日志路径',
                      onPressed: _copyLogPath,
                      icon: const Icon(Icons.copy_rounded, size: 18),
                    ),
                  ],
                )
              else
                const Text(
                  '日志文件尚未初始化。',
                  style: TextStyle(color: CinemaColors.faint),
                ),
              const Divider(height: 26),
              const Text(
                '影院客户端 0.1.0+1\nFlutter 3.47.8 · media_kit 1.2.6 / libmpv',
                style: TextStyle(
                  color: CinemaColors.faint,
                  fontSize: 11,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: CinemaColors.elevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CinemaColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({required this.label, required this.status});

  final String label;
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      '已实现' => const Color(0xFF7DD3A7),
      '代码已实现' => const Color(0xFF8DB9E8),
      '未验证' => const Color(0xFFE2B674),
      '未实现' || '未构建' => CinemaColors.faint,
      _ => CinemaColors.muted,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
          const SizedBox(width: 8),
          Text(status, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(color: CinemaColors.faint, fontSize: 10),
      ),
    );
  }
}
