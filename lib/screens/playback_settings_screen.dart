import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../widgets/cinema_surface.dart';
import '../widgets/reference_chrome.dart';

class PlaybackSettingsScreen extends StatelessWidget {
  const PlaybackSettingsScreen({super.key, this.artworkUrl});
  final String? artworkUrl;
  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return PosterSurface(
      imageUrl: artworkUrl,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            const ReferencePageHeader(title: '默认播放设置'),
            Expanded(
              child: AnimatedBuilder(
                animation: settings,
                builder: (context, _) => ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
                  children: [
                    CinemaGlass(
                      child: Column(
                        children: [
                          const ListTile(
                            leading: Icon(CupertinoIcons.tv),
                            title: Text('默认清晰度'),
                            subtitle: Text('播放片源原画'),
                            trailing: Text('原画'),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(CupertinoIcons.play_circle),
                            title: const Text('默认倍速'),
                            trailing: DropdownButton<double>(
                              value: settings.playbackRate,
                              underline: const SizedBox.shrink(),
                              items: [
                                for (final rate in [
                                  0.5,
                                  0.75,
                                  1.0,
                                  1.25,
                                  1.5,
                                  2.0,
                                ])
                                  DropdownMenuItem(
                                    value: rate,
                                    child: Text('$rate 倍'),
                                  ),
                              ],
                              onChanged: (rate) {
                                if (rate != null) {
                                  settings.setPlaybackRate(rate);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    CinemaGlass(
                      child: Column(
                        children: [
                          SwitchListTile(
                            secondary: const Icon(CupertinoIcons.forward_end),
                            title: const Text('自动下一集'),
                            subtitle: const Text('当前剧集播完后继续播放下一集'),
                            value: settings.autoNext,
                            onChanged: settings.setAutoNext,
                          ),
                          const Divider(height: 1),
                          const SwitchListTile(
                            secondary: Icon(CupertinoIcons.arrow_right_to_line),
                            title: Text('跳过片头尾'),
                            subtitle: Text('片库暂未提供片头尾时间'),
                            value: false,
                            onChanged: null,
                          ),
                          const Divider(height: 1),
                          const SwitchListTile(
                            secondary: Icon(CupertinoIcons.textformat),
                            title: Text('记住音轨字幕'),
                            subtitle: Text('暂未开放跨影片记忆'),
                            value: false,
                            onChanged: null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
