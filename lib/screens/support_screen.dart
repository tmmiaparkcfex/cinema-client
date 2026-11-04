import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../widgets/cinema_surface.dart';
import '../widgets/reference_chrome.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, this.artworkUrl, this.feedback = false});
  final String? artworkUrl;
  final bool feedback;
  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _description = TextEditingController();
  final _contact = TextEditingController();
  String _query = '';
  String _category = '播放异常';
  final _screenshots = <XFile>[];
  static const _answers = {
    '播放时出现转圈怎么办？': '可先暂停片刻，等待缓冲后继续。仍频繁转圈时，打开播放器线路选项切换同集资源。播放信息和本机日志可帮助定位问题。',
    '画面卡住，但声音正常？': '打开播放器的播放信息，查看实际解码方式和丢帧情况。记录片名、集数和时间点，便于进一步排查。',
    '如何离线观看？': '在影片详情右上角的更多菜单选择下载原画。下载期间请保持应用在前台，完成后从我的下载播放。',
    '收藏和观看记录保存在哪里？': '当前保存在本机。账号与云同步服务暂未开放。',
    '为什么需要连接夸克？': '当前片源通过你自己的夸克账号取得播放地址。可在设置中的夸克播放账号完成连接。',
  };
  @override
  void dispose() {
    _description.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final images = await openFiles(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: '图片',
          extensions: ['png', 'jpg', 'jpeg'],
          uniformTypeIdentifiers: ['public.image'],
        ),
      ],
    );
    if (!mounted) return;
    setState(() => _screenshots.addAll(images.take(3 - _screenshots.length)));
  }

  @override
  Widget build(BuildContext context) => PosterSurface(
    imageUrl: widget.artworkUrl,
    child: Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          ReferencePageHeader(title: widget.feedback ? '意见反馈' : '帮助与反馈'),
          Expanded(child: widget.feedback ? _feedback() : _help()),
        ],
      ),
    ),
  );

  Widget _help() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      TextField(
        onChanged: (value) => setState(() => _query = value),
        decoration: InputDecoration(
          hintText: '搜索常见问题',
          prefixIcon: const Icon(CupertinoIcons.search),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      const SizedBox(height: 22),
      const Text(
        '常见问题',
        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      CinemaGlass(
        child: Column(
          children: [
            for (final entry in _answers.entries.where(
              (entry) =>
                  entry.key.contains(_query) || entry.value.contains(_query),
            ))
              ExpansionTile(
                title: Text(entry.key, style: const TextStyle(fontSize: 14)),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Text(
                    entry.value,
                    style: const TextStyle(
                      height: 1.6,
                      color: CinemaColors.muted,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      SizedBox(
        height: 46,
        child: FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) =>
                  SupportScreen(artworkUrl: widget.artworkUrl, feedback: true),
            ),
          ),
          icon: const Icon(CupertinoIcons.pencil),
          label: const Text('意见反馈'),
        ),
      ),
    ],
  );

  Widget _feedback() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 6, 20, 30),
    children: [
      const Text(
        '问题类型 *',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      CinemaGlass(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: const InputDecoration(border: InputBorder.none),
          items: [
            for (final type in ['播放异常', '片库资料', '下载问题', '界面建议', '其他'])
              DropdownMenuItem(value: type, child: Text(type)),
          ],
          onChanged: (value) => setState(() => _category = value ?? _category),
        ),
      ),
      const SizedBox(height: 22),
      const Text(
        '问题说明 *',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      CinemaGlass(
        padding: const EdgeInsets.all(14),
        child: TextField(
          controller: _description,
          maxLines: 5,
          maxLength: 500,
          decoration: const InputDecoration(
            hintText: '请描述片名、集数、发生时间以及遇到的问题…',
            border: InputBorder.none,
          ),
        ),
      ),
      const SizedBox(height: 22),
      const Text(
        '上传截图（最多 3 张）',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          for (var index = 0; index < 3; index++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AspectRatio(
                  aspectRatio: 1.2,
                  child: CinemaGlass(
                    radius: 14,
                    onTap: index >= _screenshots.length ? _pick : null,
                    child: index < _screenshots.length
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                File(_screenshots[index].path),
                                fit: BoxFit.cover,
                              ),
                              Align(
                                alignment: Alignment.topRight,
                                child: IconButton(
                                  tooltip: '移除截图',
                                  onPressed: () => setState(
                                    () => _screenshots.removeAt(index),
                                  ),
                                  icon: const Icon(
                                    CupertinoIcons.xmark_circle_fill,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  CupertinoIcons.plus,
                                  size: 25,
                                  color: CinemaColors.accent,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  '添加截图',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: CinemaColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 22),
      const Text(
        '联系方式（选填）',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      CinemaGlass(
        child: TextField(
          controller: _contact,
          decoration: const InputDecoration(
            prefixIcon: Icon(CupertinoIcons.mail),
            hintText: '手机号或邮箱',
            border: InputBorder.none,
          ),
        ),
      ),
      const SizedBox(height: 24),
      SizedBox(
        height: 48,
        child: FilledButton(
          onPressed: () => ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('反馈服务暂未开放，内容尚未提交。'))),
          child: const Text('提交反馈'),
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        '反馈服务暂未开放，截图和内容不会上传。',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: CinemaColors.muted),
      ),
    ],
  );
}
