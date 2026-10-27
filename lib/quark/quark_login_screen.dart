import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/app_log.dart';
import 'quark_playback_service.dart';

class QuarkLoginScreen extends StatefulWidget {
  const QuarkLoginScreen({super.key, required this.playbackService});

  final QuarkPlaybackService playbackService;

  @override
  State<QuarkLoginScreen> createState() => _QuarkLoginScreenState();
}

class _QuarkLoginScreenState extends State<QuarkLoginScreen> {
  bool _checking = false;
  bool _loading = true;
  String? _message;

  Future<void> _captureSession() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _message = null;
    });
    try {
      final cookies = <String, String>{};
      for (final url in const [
        'https://pan.quark.cn/',
        'https://drive-pc.quark.cn/',
      ]) {
        final values = await CookieManager.instance().getCookies(
          url: WebUri(url),
        );
        for (final cookie in values) {
          if (cookie.name.trim().isNotEmpty && cookie.value != null) {
            cookies[cookie.name.trim()] = cookie.value.toString();
          }
        }
      }
      if (cookies.isEmpty) {
        setState(() => _message = '还没有读取到登录状态。请先在页面中完成夸克登录。');
        return;
      }
      final cookieHeader = cookies.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('; ');
      await widget.playbackService.connectCookie(cookieHeader);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on QuarkException catch (error) {
      AppLog.error('quark-login', error);
      if (!mounted) return;
      setState(() => _message = error.userMessage);
    } catch (error) {
      AppLog.error('quark-login', error);
      if (!mounted) return;
      setState(() => _message = '读取登录状态失败，请重新登录或重启应用后再试。');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07080B),
      appBar: AppBar(
        title: const Text('连接夸克账号'),
        backgroundColor: const Color(0xFF07080B),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: const Color(0xFF12151B),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            child: const Text(
              '登录在你的设备内完成，会话只保存在系统安全存储中。密码和 Cookie 不会发送给影视接口或开发者。',
              style: TextStyle(
                color: Color(0xFFC9CDD6),
                height: 1.45,
                fontSize: 13,
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_message != null)
            Container(
              width: double.infinity,
              color: const Color(0xFF3A1315),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Text(
                _message!,
                style: const TextStyle(color: Color(0xFFFFB4B4), height: 1.4),
              ),
            ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri('https://pan.quark.cn/'),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                thirdPartyCookiesEnabled: true,
                useHybridComposition: true,
                transparentBackground: false,
              ),
              onLoadStart: (_, _) {
                if (mounted) setState(() => _loading = true);
              },
              onLoadStop: (_, _) {
                if (mounted) setState(() => _loading = false);
              },
              onReceivedError: (_, _, error) {
                AppLog.info('quark-login-web', 'page error ${error.type}');
                if (mounted) {
                  setState(() {
                    _loading = false;
                    _message = '夸克登录页加载失败，请检查网络后重试。';
                  });
                }
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _checking ? null : _captureSession,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE50914),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: Text(_checking ? '正在验证登录状态…' : '我已完成登录'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
