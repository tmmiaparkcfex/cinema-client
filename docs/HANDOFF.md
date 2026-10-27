# 接续与审核交接

## 当前结论

源码已完成第一版 iPhone 优先闭环，真实接口读取和自动化测试通过；**iOS 未编译、无 IPA、未真机播放**。不要把本目录中的 UI 代码、测试通过或工作流文件当作 iPhone 验证结果。

## 路径

| 内容 | 路径 |
| --- | --- |
| 正式客户端源码/本 Git 仓库 | `D:\Codex\01_对话项目\Codex手机任务\cinema-client` |
| ASCII 验证镜像（非正式源码） | `D:\Codex\work\cinema-client-validate-20261027-2` |
| Flutter SDK 3.47.8 | `D:\Codex\tools\flutter` |
| Flutter 下载归档 | `D:\Codex\05_缓存临时\flutter_windows_3.47.8-stable.zip` |
| Pub 缓存 | `D:\Codex\cache\pub` |
| 生产影视项目（未改） | `D:\各软件安装位置\vod-web` |
| 生产数据库（未读私有账号，未改） | `D:\各软件安装位置\vod-web\data\vodweb.db` |

## 已观察的后台服务（只读快照）

采样 2026-10-27 16:59:05：

- `8765`、`8788`：PID 12360，命令 `server.mjs`，是本次只读接口测试使用的服务；
- `8790`：PID 16656，`supervisor.mjs`；
- `8793`：PID 13668，`live-server.mjs`（不是影视接口本身）；
- `8789`：PID 9420，`shared-background.mjs`（随行控制台）；
- 更早 16:04 快照中 8765/8788 的 PID 为 11664，说明进程在采样之间由外部 watchdog 重启过。该变化不是本客户端操作造成。

本次没有启动、停止、重启生产服务，没有执行部署脚本，没有修改生产文件，也没有调用转存、删除或播放接口。最近一次接口只读测试在 16:57–16:58 完成。

## 启动客户端（有可用设备时）

```bash
cd D:\Codex\01_对话项目\Codex手机任务\cinema-client
flutter config --no-enable-swift-package-manager
flutter pub get
flutter analyze
flutter test
flutter run -d <device-id> --dart-define=VOD_API_BASE=http://192.168.1.4:8765
```

- iPhone 需与 8765 端口服务器同一网络，或改用可访问的 HTTPS 根地址；
- 接口地址也可在“我的 → 影视接口”修改；
- 首次播放会要求连接观者自己的夸克账号；
- 无法用当前 Windows 主机直接产生 iOS 构建。

## iPhone 构建

```bash
flutter config --no-enable-swift-package-manager
flutter pub get
flutter build ios --release --no-codesign \
  --dart-define=VOD_API_BASE=https://your-api.example.com
```

CI：

1. 将本目录作为一个 GitHub 仓库（远程推送未由本次执行）；
2. Actions → `Build unsigned iOS IPA` → Run workflow；
3. 输入接口根地址；
4. 下载 `cinema-client-ios-unsigned` artifact；
5. 在个人签名工具中用个人 Apple ID 签名 `CinemaClient-unsigned.ipa`。

目前无 GitHub 远程、无 `gh` 登录、无 Mac，故没有 `.ipa` 与 `Podfile.lock`。详见 `docs/BLOCKERS.md`。

## 已完成/已验证

- 代码：首页、详情、季集、搜索、片单、本地续播、夸克设备内桥接、播放控件、错误恢复。
- `flutter analyze`：0 issue。
- 测试：11 passed, 3 optional tests skipped in default suite（真实接口 1、截图捕获 2）。
- 真实接口：home/list/search/detail 全链路解析通过。
- 界面测试截图：`docs/screenshots/`（非真机，见该目录 README）。
- 原始日志：`docs/evidence/*.log`。
- 环境快照：`docs/evidence/environment-20261027.json`。

## 未完成/阻塞

- iOS 编译、未签名 IPA、个人签名和安装；
- iPhone 真机播放、4K/HDR、功耗/发热、长时稳定性；
- 真实观看者夸克账号授权、转存、取链、清理；
- Android/Windows/Android TV 构建和真机；
- 跨设备同步、在线字幕、投屏和媒体工具；
- 后台缺失海报/简介/演员数据的补齐。

逐项见 `docs/KNOWN_ISSUES.md`、`docs/BLOCKERS.md`、`docs/VERIFICATION.md`。

## 审核重点

1. `lib/quark/quark_playback_service.dart`：真实夸克 API 参数、错误分流、专用目录、清理边界、Cookie 更新；未真机验证。
2. `lib/player/playback_screen.dart`：media_kit 生命周期、直链请求头、超时/缓冲/下一集/进度保存；未真机验证。
3. `lib/data/api_client.dart`：接口字段解析和错误类型。
4. `lib/core/app_models.dart`：空字段、季集、资源描述映射。
5. `ios/Podfile`、`Info.plist`：CocoaPods 与 ATS；无 Podfile.lock，尚未在 macOS 执行。
6. `.github/workflows/ios-unsigned.yml`：未运行过，首次构建可能需要调整 runner/Xcode/action 标签。
7. 版权/许可：libmpv 是 LGPL 播放构建；分发前需遵守 LGPL，不代表“MIT 就全部免费”。

## 安全

- 无账号 Cookie、密码、证书、私有播放地址进入 Git。
- 夸克会话只存设备安全存储。
- 日志已脱敏。
- 当前 HTTP 开发配置放宽了 ATS/cleartext，正式部署需收紧（`docs/SECURITY.md`）。

## Git

初始化后在本文件补充 commit。所有提交仅在本地，不推送。
