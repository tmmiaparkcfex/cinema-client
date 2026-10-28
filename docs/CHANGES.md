# 修改清单

## 0.2.1 (3) 夸克登录修复

- 复现并修复手机默认网页模式跳下载页、桌面表单在窄屏越界的问题。
- 使用夸克官方手机号验证码表单，保留原生 Cookie 读取和账号接口验证后保存。
- 增加原生 iOS HttpOnly Cookie 测试与 Actions 验证步骤；结果见 `QUARK_LOGIN-20261028.md`。
- 0.2.1 正式 IPA 已实际编译、下载和哈希校验；原生 HttpOnly Cookie 测试 1 项通过，实际账号尚待手机验收。见 `IOS_BUILD-0.2.1-20261028.md`。

## 2026-10-28 手机目录连接

- 原接口地址从手机访问超时；用户在 App 将根地址改为 `http://172.16.3.70:8790` 后，确认电影和电视剧已显示。
- 已核实 8790 转发 `/api/*`，首页返回 200、20 条数据；不依赖观看者夸克登录。
- 源码、设置示例及后续 Actions 的默认地址同步为此入口；保留已有手动配置，不重新打包当前 IPA。

## 2026-10-28 实际 iOS 构建

- 按用户授权上传并公开项目仓库，完成 Actions 云端分析、51 项测试、iOS Release 编译与 IPA 打包。
- 下载并验证 IPA SHA-256、iPhone arm64、原生 Mpv/FFmpeg/Ass 框架和字幕字体。
- 将实际 `Podfile.lock` 补回源码，保存成功构建记录；详见 `IOS_BUILD-20261028.md`。

## 0.2.0+2 本轮接续

- 保留接手时六文件草稿并修复取消队列、转存登记、所有权检查、账号切换和清理恢复。
- 原生 libass、中文字幕字体、外挂导入；首次渲染等待、租约刷新、退出次序和快速切集保护。
- 海报/横图/完整资料版型、电影/电视剧补齐、workId 归并、多季选集与实际季入口续播。
- 当前季先可播放、后台补其他季；目录资源只驻内存，不进入首页缓存。
- 固定 Actions 工具链及锁文件、修正 IPA 打包路径、保存失败诊断。
- 本轮为 51 测试通过、0 分析问题，证据见 `VERIFICATION-20261027-CODEX.md`。

以下为初始工程历史记录。

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
| `test/fixtures/live_home_snapshot.json` | 真实目录的公开字段快照，已去掉线路/分享/播放信息，用于版式渲染 |
| `test/fixtures/live_detail_snapshot.json` | 真实详情的公开字段与实测规格快照，资源 ID/分享/文件/播放地址已去除 |
| `test/screenshot_capture_test.dart` | 可选 390×844 测试渲染截图，默认跳过 |

## 修复记录

- 详情页根 `Stack` 改为 `StackFit.expand`，修复 iPhone 尺寸下滚动视口仅 129 px、正文被裁切的问题；
- `/api/home` 中出现 `mediaType=null` 时不猜测为电影：标记“类型待补齐”并在精选排除；首页可用条目不足时用 typed list 第 1 页补足；
- 电影/电视剧分区独立，不再把剧集放在“精选电影”标题下；
- iOS 启动屏改为深色，Android 启动背景改为黑色；
- 移除 Android release 使用 debug 签名的模板行为。


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
