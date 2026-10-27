# 构建与安装 · 0.2.0+2

## iPhone：GitHub Actions

用户已选择 Actions。本机 Windows 无需为此安装 Xcode 或登录 GitHub CLI。

1. 将 `cinema-client` 内的文件放到 GitHub 仓库根目录。根目录应有 `pubspec.yaml`、`lib/`、`ios/`、`assets/` 和 `.github/workflows/ios-unsigned.yml`。不要只上传源码 ZIP，也不要漏掉隐藏的 `.github`。
2. 提交所有本轮源码、测试、字体和锁文件；检查版本为 **0.2.0+2**。
3. 打开 **Actions → Build unsigned iOS IPA → Run workflow**。
4. `api_base` 默认填 `http://172.16.3.70:8790`，这是用户已在 iPhone 验证可用的入口；也可填写手机能访问的其他根地址。不要填分享或详情地址。
5. 流程安装 Flutter、关闭 Swift Package Manager、解析锁定依赖、分析、测试、无签名 iOS 编译及打包。
6. 成功后下载 `cinema-client-ios-unsigned`；失败后下载 `cinema-client-ios-diagnostics`，检查 `ios-build.log`、`analyze.log`、`tests.log` 和 `toolchain.txt`。

工作流固定 macOS 15、Xcode 26.3、Flutter 3.47.8，最低 iOS 15，使用 CocoaPods。**2026-10-28 已实际执行成功并生成未签名 IPA**，51 项云端测试通过，见 [构建记录](IOS_BUILD-20261028.md)。仓库现按用户授权公开。

| 成功产物 | 用途 |
| --- | --- |
| `CinemaClient-unsigned.ipa` | 待个人签名的应用 |
| `CinemaClient-unsigned.ipa.sha256` | 完整性校验 |
| `Podfile.lock` | 首次 macOS 构建的 Pod 版本，审核后补入源码 |
| `pubspec.lock`、`toolchain.txt` | 实际依赖与工具链记录 |

`ios/Podfile.lock` 已从本次实际成功构建补回源码；后续依赖或工具链改变时，仍应依据真实构建结果验证。

## 签名和真机

未签名 IPA 不能直接安装。使用你自己的签名工具和账号重签安装，凭据只在该工具中处理。Bundle ID 当前是开发标识 `com.example.cinemaClient`，按签名环境设置唯一标识。

手机与 API 需网络可达。局域网地址不能直接从外网访问；iPhone 上的 `127.0.0.1` 不是你的电脑。

2026-10-28 实机反馈：首个 IPA 的 `192.168.1.4:8765` 从手机访问超时；手机设置改为 `http://172.16.3.70:8790` 后，用户确认电影/电视剧正常显示。8790 的 `/api/*` 会转发到现有影视服务。源码与后续 Actions 默认值已同步；首个 IPA 本身未重新打包，已有设置可直接修改。172.16.3.70 是私网地址，需要相应网络/组网路由可达。

安装后的首轮验收：

1. 真实首页、电影/电视剧、搜索、详情、季集。
2. 在应用内连接观看者夸克账号，先播放已知正常的小文件。
3. 首启、暂停、拖动、退出清理、续播、同集换线、下一集、快速切集、取消、账号过期重连。
4. 已知规格样片的 4K HEVC 10-bit、音轨、SRT/ASS/图形字幕、HDR；记录机型、iOS、网络和结果。
5. 切后台、锁屏、网络切换、强杀后恢复清理，再测长时播放、发热和耗电。

Windows 原生软件解码证据不能代替这些设备结果。

## 其他三端

| 平台 | 状态 | 构建条件与命令 |
| --- | --- | --- |
| Android 手机 | 平台目录已有；未构建/真机验收 | Android SDK、JDK 17；`flutter build apk --release --dart-define=VOD_API_BASE=https://your-api.example.com` |
| Android TV/盒子 | leanback、基础焦点处理已有；banner 与完整遥控体验未完成 | 同 Android APK；需实际盒子验收遥控/返回/字体/硬解 |
| Windows | DLL 无界面实测通过；Flutter 桌面未构建 | Visual Studio C++、CMake、符号链接支持；`flutter build windows --release --dart-define=VOD_API_BASE=https://your-api.example.com` |

Android release 需配置正式签名。本轮没有修改系统设置或安装上述缺失工具链。

## 已核对来源

- [Flutter 官方版本](https://github.com/flutter/flutter/releases/tag/3.47.8)
- [GitHub macOS 15 工具清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)
- [Flutter iOS 构建文档](https://docs.flutter.dev/deployment/ios)
