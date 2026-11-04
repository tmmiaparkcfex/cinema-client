import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../widgets/cinema_surface.dart';
import '../widgets/poster_artwork.dart';
import '../widgets/reference_chrome.dart';
import '../core/app_models.dart';

enum AccountPage { phone, code, password, reset, profile, security }

/// Account service integration is deferred. Forms never simulate authentication.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, this.page = AccountPage.phone, this.artwork});
  final AccountPage page;
  final VodItem? artwork;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _agreed = false;
  bool _obscured = true;
  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  void _open(AccountPage page) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => AccountScreen(page: page, artwork: widget.artwork),
    ),
  );

  void _unavailable() =>
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('账号服务暂未开放，请先以游客身份使用。')));

  Widget _field(
    TextEditingController controller,
    String hint, {
    bool password = false,
    bool code = false,
  }) => CinemaGlass(
    radius: 26,
    child: TextField(
      controller: controller,
      keyboardType: password
          ? TextInputType.visiblePassword
          : TextInputType.number,
      obscureText: password && _obscured,
      onChanged: (_) => setState(() {}),
      maxLength: code ? 6 : null,
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        filled: false,
        prefixIcon: password ? const Icon(CupertinoIcons.lock, size: 20) : null,
        prefixText: !password && !code ? '+86  |  ' : null,
        suffixIcon: password
            ? IconButton(
                tooltip: '显示或隐藏密码',
                onPressed: () => setState(() => _obscured = !_obscured),
                icon: Icon(
                  _obscured ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                  size: 20,
                ),
              )
            : null,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 22,
          vertical: 16,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final title = switch (page) {
      AccountPage.phone => '手机号登录/注册',
      AccountPage.code => '输入验证码',
      AccountPage.password => '密码登录',
      AccountPage.reset => '重置密码',
      AccountPage.profile => '编辑资料',
      AccountPage.security => '账号与安全',
    };
    final form = page != AccountPage.security && page != AccountPage.profile;
    return PosterSurface(
      imageUrl: widget.artwork?.poster,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: form
            ? SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(
                      height: MediaQuery.sizeOf(context).width * 0.88,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (widget.artwork != null)
                            FeaturePoster(item: widget.artwork!, faded: true),
                          SafeArea(
                            bottom: false,
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: CinemaGlass(
                                  radius: 24,
                                  child: IconButton(
                                    tooltip: '返回',
                                    onPressed: () => Navigator.pop(context),
                                    icon: const Icon(CupertinoIcons.back),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (widget.artwork != null)
                            Positioned(
                              left: 70,
                              right: 70,
                              bottom: 8,
                              child: FeatureTitle(item: widget.artwork!),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
                      child: Column(
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            page == AccountPage.code
                                ? '请输入短信中的六位验证码'
                                : '登录后同步收藏与观看记录',
                            style: const TextStyle(
                              fontSize: 13,
                              color: CinemaColors.muted,
                            ),
                          ),
                          const SizedBox(height: 24),
                          _field(
                            _phone,
                            page == AccountPage.code ? '六位验证码' : '请输入手机号',
                            code: page == AccountPage.code,
                          ),
                          if (page == AccountPage.password ||
                              page == AccountPage.reset) ...[
                            const SizedBox(height: 14),
                            _field(
                              _password,
                              page == AccountPage.reset ? '请输入新密码' : '请输入密码',
                              password: true,
                            ),
                          ],
                          const SizedBox(height: 14),
                          if (page == AccountPage.phone)
                            Row(
                              children: [
                                Checkbox(
                                  value: _agreed,
                                  shape: const CircleBorder(),
                                  onChanged: (v) =>
                                      setState(() => _agreed = v ?? false),
                                ),
                                const Expanded(
                                  child: Text(
                                    '我已阅读并同意用户协议和隐私政策',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: CinemaColors.muted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: CinemaColors.accent,
                              ),
                              onPressed:
                                  page == AccountPage.phone &&
                                      (!_agreed ||
                                          !RegExp(r'^1[0-9]{10}$')
                                              .hasMatch(_phone.text))
                                  ? null
                                  : _unavailable,
                              child: Text(
                                page == AccountPage.phone
                                    ? '获取验证码'
                                    : page == AccountPage.reset
                                    ? '重置密码'
                                    : '登录',
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '账号服务暂未开放',
                            style: TextStyle(
                              fontSize: 12,
                              color: CinemaColors.muted,
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (page == AccountPage.phone)
                            TextButton(
                              onPressed: () => _open(AccountPage.password),
                              child: const Text('密码登录  ›'),
                            ),
                          if (page == AccountPage.password)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                TextButton(
                                  onPressed: () => _open(AccountPage.code),
                                  child: const Text('验证码登录'),
                                ),
                                TextButton(
                                  onPressed: () => _open(AccountPage.reset),
                                  child: const Text('忘记密码？'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  ReferencePageHeader(title: title),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        if (page == AccountPage.profile) ...[
                          const Center(
                            child: CircleAvatar(
                              radius: 42,
                              backgroundColor: Color(0x77FFFFFF),
                              child: Icon(
                                CupertinoIcons.person_fill,
                                size: 46,
                                color: CinemaColors.accent,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          CinemaGlass(
                            child: Column(
                              children: [
                                ListTile(
                                  title: const Text('昵称'),
                                  trailing: const Text('游客'),
                                  onTap: _unavailable,
                                ),
                                ListTile(
                                  title: const Text('头像'),
                                  trailing: const Icon(
                                    CupertinoIcons.chevron_right,
                                    size: 16,
                                  ),
                                  onTap: _unavailable,
                                ),
                              ],
                            ),
                          ),
                        ] else
                          CinemaGlass(
                            child: Column(
                              children: [
                                ListTile(
                                  title: const Text('绑定手机号'),
                                  trailing: const Text('未登录'),
                                  onTap: () => _open(AccountPage.phone),
                                ),
                                ListTile(
                                  title: const Text('修改密码'),
                                  trailing: const Icon(
                                    CupertinoIcons.chevron_right,
                                    size: 16,
                                  ),
                                  onTap: () => _open(AccountPage.reset),
                                ),
                                ListTile(
                                  title: const Text('登录设备'),
                                  trailing: const Text('暂不可用'),
                                  onTap: _unavailable,
                                ),
                                ListTile(
                                  title: const Text('注销账号'),
                                  trailing: const Icon(
                                    CupertinoIcons.chevron_right,
                                    size: 16,
                                  ),
                                  onTap: _unavailable,
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 22),
                        const Text(
                          '账号服务暂未开放，当前为游客身份。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: CinemaColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
