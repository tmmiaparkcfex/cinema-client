# 影院客户端（cinema-client）

面向观看者的原生影视客户端。资源索引由现有 `vod-web` 提供；观看者使用自己的夸克账号、IP 和流量，在设备内完成授权、必要转存、取流和原生播放。

当前第一目标是 iPhone。工程同时生成 Android 手机、Android TV 和 Windows 平台目录，但不把未构建、未真机验证的端算作完成。

## 当前状态（2026-10-27）

| 项目 | 状态 | 证据或限制 |
| --- | --- | --- |
| Flutter 工程与首页/详情/搜索/片单/续播 | 已实现 | `lib/` |
| 真实接口读取 | 已验证 | 单元测试 + 本机真实 API 测试通过 |
| 设备内夸克登录与 Cookie 安全存储 | 代码已实现 | 未用真实账号验证 |
| 定位分享文件、专用目录转存、取直链、清理 | 代码已实现 | 未用真实账号验证 |
| 原生 libmpv 播放与 HTTP 头 | 代码已实现 | **未真机验证** |
| 音轨/内嵌字幕、倍速、画面比例、线路切换 | 代码已实现 | 未真机验证 |
| 静态分析 | 通过，0 issue | 见 `docs/VERIFICATION.md` |
| 自动化测试 | 11 通过、3 可选跳过 | 见 `docs/VERIFICATION.md` |
| 界面测试渲染 | 4 张 | `docs/screenshots/`，**不是 iPhone 真机截图** |
| iOS 编译 / IPA | **阻塞** | 当前 Windows 无 Xcode；本机也无 GitHub CLI 登录 |
| iPhone 真机播放 / 4K / HDR / 功耗 | **未验证** | 缺 Mac/Xcode、真机、观看者夸克账号 |
| Android / Android TV / Windows 产物 | **未构建** | 无 Android SDK、无 Visual Studio 工具链 |
| 跨设备观看记录同步 | 未实现 | 需独立应用身份和同步服务，不能复用夸克登录代替 |
| 在线字幕、截图/GIF/OCR、调色、均衡器、投屏 | 未实现 | 界面会明确说明，不伪造能力 |

版本、许可证、选型依据见 `docs/TECHNICAL_SELECTION.md`。

## 快速运行

前置：Flutter 3.47.8、Dart 3.13.7。工程固定依赖在 `pubspec.lock`。

```bash
flutter config --no-enable-swift-package-manager
flutter pub get
flutter analyze
flutter test
```

运行到可用设备：

```bash
flutter run -d <device-id> \
  --dart-define=VOD_API_BASE=http://192.168.1.4:8765
```

不传 `--dart-define` 时，开发默认值为 `http://192.168.1.4:8765`。正式构建应显式传入接口根地址。接口地址也可在应用“我的 → 影视接口”中修改；只填根地址，不填分享链接。

本机 Windows 没有 Visual Studio/C++ 工具链，也没有 Android SDK，所以本次没有生成 Windows 或 Android 产物。

### 本机验证注意

本机 Flutter SDK 已放在纯英文路径 `D:\Codex\tools\flutter`，Pub 缓存位于 `D:\Codex\cache\pub`。源码目录含中文；Flutter 的分析服务器对中文路径存在 URI 解析崩溃，验证副本放在：

```text
D:\Codex\work\cinema-client-validate-20261027-2
```

这不是另一份正式源码。修改后需同步到验证副本执行分析和测试；GitHub Actions 的检出路径不含中文，不受此问题影响。

真实接口只读验证：

```bash
flutter test test/live_api_test.dart \
  --dart-define=LIVE_VOD_API=http://127.0.0.1:8765
```

## iPhone 未签名 IPA

仓库包含 `.github/workflows/ios-unsigned.yml`。在 GitHub Actions 页面手动运行，输入接口根地址，流程会：

1. 固定 Flutter 3.47.8；
2. 关闭 Swift Package Manager，使用 CocoaPods；
3. 执行 `flutter analyze` 与 `flutter test`；
4. 以 `--no-codesign` 构建 iOS；
5. 输出未签名 `CinemaClient-unsigned.ipa`、SHA-256、`Podfile.lock`、`pubspec.lock` 和工具链记录。

构建步骤：

```bash
flutter config --no-enable-swift-package-manager
flutter pub get
flutter build ios --release --no-codesign \
  --dart-define=VOD_API_BASE=https://your-api.example.com
```

签名为个人 Apple ID 的本地步骤，不在仓库中保存任何 Apple 凭据。Windows 上可用兼容的侧载签名工具将未签名 IPA 重签并安装；工具会要求你本人登录 Apple ID。免费个人签名会受 Apple 的有效期和设备数量规则约束，具体以签名工具和 Apple 当前提示为准。

> 未签名 IPA 目前**尚未生成**：需要可运行 Actions 的 GitHub 仓库，或在 macOS/Xcode 上构建。当前环境没有这两项条件，详见 `docs/BLOCKERS.md`。

## 观看者账号流程

1. 应用打开夸克登录页，登录在你的设备内完成。
2. 会话 Cookie 存入 iOS Keychain / Android Keystore，不写入日志，不发往影视接口。
3. 选中片源后，客户端向夸克确认分享 → 定位目标文件 → 转存到 `.cinema-client` 专用目录 → 获取直链。
4. libmpv 使用临时直链和必要请求头播放，支持 Range。
5. 退出播放器时删除本应用刚创建的文件；启动时重试清理中断留下的本应用登记文件。
6. 不删除用户原有文件，不使用开发者账号代播，不把播放地址提交给服务端。

详见 `docs/ARCHITECTURE.md` 和 `docs/SECURITY.md`。

## 目录

```text
lib/core/       配置、主题、数据模型、选集与进度结构
lib/data/       影视接口、本地片单/进度、首页缓存
lib/quark/      设备内夸克登录、转存、取流、临时文件登记与清理
lib/player/     media_kit/libmpv 播放页面和自定义控件
lib/screens/    首页、详情、搜索、片单、我的、导航
test/           接口解析、模型、本地存储、首页组件、可选真实接口测试
docs/           接口契约、选型、安全、验证、阻塞与交接
.github/        iOS 未签名构建工作流
```

## 已知缺口

- 接口样片普遍缺海报、简介、演员；客户端显示真实空态，不用演示素材填充。
- 首页只展示接口当前返回的前 20 条精选与最新；分类页支持分页。
- 当前接口只提供已核验 4K 分享索引，不是普通清晰度全集。
- 夸克接口不是稳定公开 SDK；分享失效、风控、空间不足会按明确错误处理，但需真实账号继续验证。
- 大文件转存会占用观看者网盘空间；退出播放后清理。异常中断的清理只能在下一次启动或手动清理时重试。
- 没有 DRM，HDR/杜比视界识别、解码和正确显示未验证。
- 没有跨设备同步、投屏、在线字幕和媒体工具。

完整清单见 `docs/KNOWN_ISSUES.md`。
