# 修改清单

基线：2026-10-27 新建独立 Flutter 客户端工程，未修改 `vod-web` 生产代码或数据库。

## 功能源码

| 文件 | 内容 |
| --- | --- |
| `lib/main.dart` | 依赖初始化、Keychain、缓存、日志、应用入口 |
| `lib/core/app_models.dart` | 作品、季集、线路、资源、首页、目录模型；空字段兼容 |
| `lib/core/app_settings.dart` | 接口根地址校验与持久化 |
| `lib/core/episode_choice.dart` | 选集排序、下一集、同集换线路 |
| `lib/core/app_log.dart` | 本机脱敏日志、大小轮换 |
| `lib/core/app_theme.dart` | 黑/白/红的影院主题 |
| `lib/core/app_scope.dart` | 服务注入 |
| `lib/data/api_client.dart` | `/api/home`、`/api/list`、`/api/search`、`/api/detail`、`/api/resource` |
| `lib/data/home_cache.dart` | 最小首页缓存，剔除分享与播放信息 |
| `lib/data/local_store.dart` | 片单、观看历史、断点续播（本机） |
| `lib/quark/quark_account_store.dart` | 设备安全存储 |
| `lib/quark/quark_playback_service.dart` | 分享定位、专用目录、转存、直链、fid 登记与清理 |
| `lib/quark/quark_login_screen.dart` | 设备内网页登录；仅登录，不承载播放 |
| `lib/player/playback_screen.dart` | media_kit 原生播放、自定义控件、超时/错误/下一集/进度 |
| `lib/screens/*.dart` | 首页/详情/搜索/目录/片单/我的/导航 |
| `lib/widgets/*.dart` | 真实海报/空态、海报卡、继续观看卡 |

## 平台与构建

| 文件 | 内容 |
| --- | --- |
| `ios/Podfile` | iOS 15，CocoaPods 插件集成 |
| `ios/Runner/Info.plist` | 中文显示名、黑暗模式、局域网说明、开发期 HTTP 放宽 |
| `android/app/src/main/AndroidManifest.xml` | INTERNET、leanback/TV 入口、开发期 cleartext |
| `.github/workflows/ios-unsigned.yml` | macOS Actions，分析/测试/无签名构建/IPA 打包 |
| `pubspec.yaml` / `pubspec.lock` | 固定依赖版本 |

## 测试

| 文件 | 覆盖 |
| --- | --- |
| `test/api_client_test.dart` | 首页、列表、搜索、详情、服务错误 |
| `test/episode_choice_test.dart` | 下一集、同集换线、缓存脱敏 |
| `test/local_store_test.dart` | 片单与进度重载 |
| `test/widget_test.dart` | 首页真实数据渲染、分类切换、空值展示 |
| `test/live_api_test.dart` | 可选真实接口只读冒烟 |
| `test/fixtures/vod_fixtures.dart` | 合成数据，分享地址和 ID 均为假值 |

## 文档和证据

- `README.md`
- `docs/API_CONTRACT.md`
- `docs/ARCHITECTURE.md`
- `docs/TECHNICAL_SELECTION.md`
- `docs/SECURITY.md`
- `docs/VERIFICATION.md`
- `docs/BLOCKERS.md`
- `docs/KNOWN_ISSUES.md`
- `docs/HANDOFF.md`
- `docs/evidence/*`

## 未修改

- 生产 `server.mjs`、`lib/*`、配置、账号池、数据库；
- 生产进程、端口、采集队列；
- 旧部署脚本、旧演示页面；
- 远程仓库。

## 生成方式

- Flutter 3.47.8 `flutter create` 生成 iOS/Android/Windows 平台壳；
- iOS 首次误用 Swift Package Manager，因三个插件仅提供 CocoaPods，重建为 CocoaPods（旧空壳备份：`D:\Codex\work\cinema-client-ios-spm-backup-20261027`）；
- SDK 从含中文路径移到 `D:\Codex\tools\flutter`，避免 Flutter 3.47.8 分析器/着色器编译路径故障。
