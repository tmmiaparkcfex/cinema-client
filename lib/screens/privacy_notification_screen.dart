import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../widgets/cinema_surface.dart';
import '../widgets/reference_chrome.dart';

class PrivacyNotificationScreen extends StatelessWidget {
  const PrivacyNotificationScreen({super.key, this.artworkUrl, this.notifications = false});
  final String? artworkUrl;
  final bool notifications;
  @override
  Widget build(BuildContext context) => PosterSurface(imageUrl: artworkUrl,
    child: Scaffold(backgroundColor: Colors.transparent, body: Column(children: [
      ReferencePageHeader(title: notifications ? '通知设置' : '隐私与权限'),
      Expanded(child: ListView(padding: const EdgeInsets.all(20), children: notifications ? [
        const CinemaGlass(child: Column(children: [
          SwitchListTile(secondary: Icon(CupertinoIcons.bell), title: Text('系统通知'),
            subtitle: Text('通知服务暂未开放'), value: false, onChanged: null),
          Divider(height: 1),
          SwitchListTile(title: Text('追剧更新提醒'), value: false, onChanged: null),
          Divider(height: 1),
          SwitchListTile(title: Text('下载完成提醒'), value: false, onChanged: null),
          Divider(height: 1),
          SwitchListTile(title: Text('消息通知'), value: false, onChanged: null),
        ])),
      ] : [
        const CinemaGlass(padding: EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('本机数据', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          SizedBox(height: 12), Text('收藏、搜索记录与观看进度保存在本机。账号与云同步服务暂未开放。', style: TextStyle(height: 1.7)),
          SizedBox(height: 18), Text('播放账号', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          SizedBox(height: 12), Text('夸克登录会话保存在设备安全存储中，用于取得你所选择资源的播放地址。可在设置中断开连接。', style: TextStyle(height: 1.7)),
          SizedBox(height: 18), Text('文件权限', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          SizedBox(height: 12), Text('导入字幕和选择反馈截图时，通过系统文件选择器读取你指定的文件。反馈服务未开放时不会上传截图。', style: TextStyle(height: 1.7)),
        ])),
      ])),
    ])));
}
