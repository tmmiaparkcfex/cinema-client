# 验证记录

验证时间：2026-10-27（北京时间）。原则：区分静态检查、自动化测试、真实接口读取、iOS 构建、真机播放。前者不能替代后者。

## 环境

| 项目 | 实际值 |
| --- | --- |
| 主机 | Windows 10 专业版 10.0.19045，64 位 |
| 构建/Xcode | 无 macOS、无 Xcode、无 `xcodebuild` |
| Flutter | 3.47.8 stable，revision `737ba8f885`，2026-10-23 |
| Dart | 3.13.7 |
| Flutter SDK 路径 | `D:\Codex\tools\flutter` |
| Pub 缓存 | `D:\Codex\cache\pub` |
| Android | 无 Android SDK、无 `adb`、无已连接设备 |
| Windows 构建工具 | 未安装 Visual Studio/C++ 工具链 |
| iPhone/Android/TV | 无已连接设备 |
| GitHub CLI | 未安装，未登录 GitHub |
| 影视接口 | 本机 `127.0.0.1:8765`，只读 GET |
| 真实夸克账号 | 测试会话没有使用或索取 |

关于 C 盘：Flutter 初次初始化在 `%LOCALAPPDATA%\Pub\Cache` 留下了一个 0 字节 README 占位文件，之后 SDK、Pub、构建缓存和验证副本均重定向至 `D:\Codex`。没有在 C 盘安装软件。

## 静态分析

在 ASCII 路径验证副本执行：

```text
Analyzing cinema-client-validate-20261027-2...
No issues found! (ran in 17.2s)
```

原始日志：`docs/evidence/flutter-analyze-20261027.log`。

说明：源码目录及最初的 Flutter SDK 路径含中文，Flutter 3.47.8 分析服务器曾因 URI 解码异常崩溃；这属于工具链路径问题，不是源码错误。SDK 移到 `D:\Codex\tools\flutter`、工程验证副本移到 ASCII 路径后通过。GitHub Actions 路径为 ASCII，不受影响。

## 自动化测试

```text
00:03 +11 ~3: All tests passed!
```

- 11 个测试通过。
- 3 个可选测试在默认全量测试中按设计跳过：真实接口 1 个、截图捕获 2 个。
- 覆盖：接口 JSON 解析、真实资源字段、未知类型不误判为电影、季集顺序、切线路同集映射、缓存不含分享/播放入口、本地片单与进度持久化、首页组件渲染和分类切换、iPhone 尺寸详情视口不被裁切。
- 原始日志：`docs/evidence/flutter-test-20261027.log`。

没有宣称播放器、夸克 API 或 iOS 平台已由这些测试覆盖。

## 真实接口只读验证

命令：

```bash
flutter test test/live_api_test.dart \
  --dart-define=LIVE_VOD_API=http://127.0.0.1:8765
```

2026-10-27 17:14 结果：

```text
LIVE_API_OK home=20 moviePage=20 tvPage=20 search=1 detailLines=1 detailEntries=16
```

| 请求 | 状态 | 字节 | 客户端测得耗时 |
| --- | ---: | ---: | ---: |
| `/api/home` | 200 | 408,897 | 7,923 ms |
| `/api/list?type=movie` | 200 | 34,475 | 4,271 ms |
| `/api/list?type=tv` | 200 | 357,419 | 3,652 ms |
| `/api/detail` | 200 | 14,298 | 4,048 ms |
| `/api/search` | 200 | 15,080 | 5,380 ms |

这只是 GET 读取和客户端解析。未触发转存、播放、清理或写生产。原始日志：`docs/evidence/live-api-20261027.log`。

## 界面渲染截图

`docs/screenshots/` 下有 4 张 Flutter 组件测试渲染图（首页首屏/片单、详情首屏/剧集）。它们使用真实目录的脱敏快照和本机中文字体，仅用于核对版式实现：

- **不是 iPhone 真机或模拟器截图**；
- 不能证明播放、字幕、线路切换或任何性能；
- 缺海报和简介是当前接口真实数据状态。

生成命令（仅在安装相应本机字体的 Windows 验证环境）：

```bash
flutter test test/screenshot_capture_test.dart \
  --dart-define=CAPTURE_SCREENSHOTS=true \
  --dart-define=SCREENSHOT_FONT=C:/Windows/Fonts/Deng.ttf \
  --dart-define=SCREENSHOT_ICON_FONT=D:/Codex/tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf \
  --dart-define=SCREENSHOT_OUTPUT=D:/Codex/01_对话项目/Codex手机任务/cinema-client/docs/screenshots
```

截图过程还发现并修复了一个真实布局问题：详情页根 `Stack` 未撑满，导致 `SingleChildScrollView` 视口只有 129 px，内容被裁切。修复为 `StackFit.expand` 后重新渲染，并增加了 iPhone 尺寸的详情视口回归测试。

截图测试日志中的 `MissingPluginException` 来自组件测试环境没有 Keychain 原生实现，截图页面栈包含“我的”页所致；它不是产品运行错误，真机 Keychain 未在此环境验证。

## 未验证

以下项目**没有通过**，不能从静态检查或接口测试推断：

- iOS 编译、CocoaPods 安装、未签名 IPA 生成；
- iPhone 安装、首次启动、相册/网络权限、登录页；
- 使用真实观看者夸克账号的分享定位、转存、取链、播放；
- 首次起播、续播、远距离拖动、Range、地址过期重取；
- 4K HEVC 10-bit、HDR10/HLG/Dolby Vision 的正确解码与显示；
- 多音轨、内嵌图形字幕/ASS、音画同步；
- 前后台、锁屏、拔耳机、网络切换、进程强杀；
- 长时间播放的内存、发热、耗电、泄露；
- Android 手机、Android TV、Windows 实际产物与操作；
- 跨设备同步、投屏、在线字幕、截图/GIF/OCR 等未实现功能。

## 原始日志与可复现性

| 内容 | 路径 |
| --- | --- |
| 静态分析原始输出 | `docs/evidence/flutter-analyze-20261027.log` |
| 全量测试原始输出 | `docs/evidence/flutter-test-20261027.log` |
| 真实接口测试原始输出 | `docs/evidence/live-api-20261027.log` |
| 截图捕获原始输出 | `docs/evidence/screenshots-20261027.log` |
| 固定依赖 | `pubspec.lock` |
| iOS Pod 依赖 | 需首次 macOS 构建后生成 `ios/Podfile.lock`，尚未生成 |
| 设备/系统/进程环境 | `docs/evidence/environment-20261027.json` |

验证副本：`D:\Codex\work\cinema-client-validate-20261027-2`。它是测试镜像，不是第二份源码。原始工作流源在 `D:\Codex\01_对话项目\Codex手机任务\cinema-client`。
