# 影院客户端 · 0.2.0+2

面向 iPhone、Android 手机、Windows、Android TV 的原生影视客户端，当前先验收 iPhone。影视目录读取现有 vod-web；观看者使用自己的夸克账号，在设备内转存、取链并播放。视频使用 media_kit/libmpv，WebView 仅用于夸克登录。

## 当前状态

本轮修复播放、取消、转存登记、会话切换、清理和季集归并，接入真实目录并完善 Netflix 风格界面。**2026-10-28 已通过 GitHub Actions 编译并生成未签名 iPhone IPA，下载和哈希校验完成；尚未签名安装或真机验收。** 详见 [实际构建记录](docs/IOS_BUILD-20261028.md)。

| 内容 | 已有证据 |
| --- | --- |
| 真实首页、电影/电视剧、搜索、详情、资源描述 | 本机真实 API 只读测试通过 |
| 作品归并、分季、同集换线、本地片单/续播 | 自动化测试；本轮真实多季样本未命中 |
| 账号校验、会话隔离、转存与重试清理 | 模拟 HTTP 测试；真实观看者账号未验收 |
| 原生播放内核 | Windows 原生 FFI 实测 4K HEVC 10-bit、双音轨、外挂 SRT、Range、拖动、续播、倍速；无界面软件解码 |
| ASS/图形字幕 | 已启用原生 libass，随包提供中文字体；实际设备渲染待验收 |
| 静态分析 / 默认测试 | 0 issue / 51 通过、3 个可选跳过 |
| 界面版型 | 实际 Flutter 页面与控件已测试渲染；不是设备截图 |
| iOS 安装包 | Actions Release 成功；未签名 IPA 已下载并校验，原生 Mpv/FFmpeg/Ass 已入包 |
| Android / Windows / TV 应用产物 | 尚未构建；共享代码不能证明四端完成 |

详见 [本轮验证](docs/VERIFICATION-20261027-CODEX.md) 和 [支持范围](docs/KNOWN_ISSUES.md)。

## 用 GitHub Actions 编译 iPhone

把本目录内容放在 GitHub 仓库根目录，保留 `.github`、`assets`、`pubspec.lock`。Actions → **Build unsigned iOS IPA** → **Run workflow**，输入手机能访问的影视接口根地址。

成功后下载 `cinema-client-ios-unsigned`，其中的 `CinemaClient-unsigned.ipa` 仍需自行签名安装；失败则下载 `cinema-client-ios-diagnostics`。操作见 [构建与安装](docs/BUILD.md)。

不要在 iPhone 填 `127.0.0.1`；它代表手机本身。当前源码及后续 Actions 的默认地址为 `http://172.16.3.70:8790`，用户已在 iPhone 确认此入口可显示电影与电视剧。已安装的首个 IPA 默认是 `http://192.168.1.4:8765`，可直接在“我的 → 影视接口”修改并保存；不需要重装。已有手动配置优先于构建默认值。

## 本地验证

固定 Flutter 3.47.8 / Dart 3.13.7，依赖已锁定：

```bash
flutter config --no-enable-swift-package-manager
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run -d <device-id> --dart-define=VOD_API_BASE=http://172.16.3.70:8790
```

本机中文路径会触发分析器 URI 错误，因此使用逐文件哈希一致的英文验证副本 `D:\Codex\work\cinema-client-20261027-codex`；正式源码仍是本目录。SDK、Pub 缓存和本轮产物均在 D 盘。

真实接口只读测试：

```bash
flutter test test/live_api_test.dart --dart-define=LIVE_VOD_API=http://127.0.0.1:8765
```

## 数据与目录

海报、横图、剧情、评分、演员、导演、类型、时长使用接口字段；缺失时如实显示空态，不把虚构海报套到真实作品上。爬虫补齐资料后即可呈现完整版型，不需要手机重新刮削全库。

- `lib/data`：真实 API、本地片单/进度、首页缓存。
- `lib/quark`：设备内登录、转存登记、取链与清理。
- `lib/player`：原生内核配置、生命周期、自定义控件、外挂字幕。
- `lib/screens`、`lib/widgets`：目录、详情、搜索、片单与设置。
- `assets/fonts`：原生字幕中文字体及许可。
- `test`、`docs`：回归测试、构建说明、证据与限制。

真实 API 本轮抽样约 7.6–10.4 秒；缓存、当前季先显示及后台补季可减少客户端等待，不能代替后台提速。iPhone 的真实账号链路、4K/HDR、发热和功耗仍需实测。
