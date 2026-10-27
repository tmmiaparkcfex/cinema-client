# 阻塞与所需条件

按影响排序。未满足条件的工作没有被标成已完成。

## 1. iOS 真实构建和 IPA 尚未产生

**事实**：当前是 Windows 10；无 Xcode、无 macOS、无 Apple 签名环境；本机没有 GitHub CLI，也没有可用的 GitHub 仓库/凭据。

**已完成**：完整 Flutter iOS 工程、Podfile、Pods xcconfig 接入、iOS 接口权限、GitHub Actions 工作流。

**实际尝试记录**：在 Windows 验证环境执行 `flutter build ios` 得到 `Could not find a subcommand named "ios" for "flutter build"`，退出码 64。原始日志见 `docs/evidence/ios-build-attempt-20261027.log`。这不是代码编译错误，而是 Windows Flutter 没有 iOS 构建命令。

**需要你选择一种方式解除阻塞**：

1. 提供/创建一个 GitHub 仓库，并让工作流在其上运行。出于“不擅自推远程”的约束，本次没有创建或推送远程仓库。
2. 在一台 Mac 上执行 `docs/HANDOFF.md` 中构建命令。
3. 如希望我在本机通过 `gh` 创建私有仓库，需要你本人完成 GitHub 登录授权，令牌不进入聊天或源码。

**产物位置（预期）**：GitHub Actions artifact `cinema-client-ios-unsigned`，内含 `CinemaClient-unsigned.ipa`。目前没有伪造或空壳 IPA。

## 2. 个人 Apple ID 签名需要你本人完成

**事实**：仓库没有 Apple 账号凭据、证书、描述文件或设备信息。

**需要**：在你自己的签名工具中登录个人 Apple ID，对未签名 IPA 重签并安装。不要把密码、双重验证验证码或 Apple 会话发到聊天。

**限制**：免费个人签名受 Apple 的期限、设备数量和应用数量规则约束；以 Apple 当前提示为准。项目 Bundle ID 目前是开发用 `com.example.cinemaClient`，正式签名时可能需要换成你的唯一 ID。

## 3. 没有 iPhone 真机和真实夸克账号，播放闭环无法验收

**事实**：未检测到 iPhone、Android 或电视设备；没有使用观看者夸克账号。

**需要**：

- 一台可侧载的 iPhone，告知型号和 iOS 版本；
- 在应用中由你登录自己的夸克账号；
- 一个已知可播的分享资源，以及它的容器/编码/码率/音频/字幕信息；
- 测试网络与服务地址（同一局域网 IP 或公网 HTTPS）。

**不允许**：在聊天里发 Cookie、密码、验证码或私有直链。登录应在应用内完成，日志不会记录。

没有这些条件时，任何“iPhone 起播 xx 秒、4K 流畅、HDR 正常”的数字都不可信，本项目没有编造。

## 4. Android、Android TV、Windows 产物未构建

**事实**：

- 没有 Android SDK、ADB、Java；
- 没有 Visual Studio C++ 工具链；
- Flutter 的 Windows 插件符号链接支持尚未启用（需要 Windows 开发者模式；本次没有擅自改系统设置）。

平台目录已生成，代码共享，但“能编译”与“能在设备上运行”没有被证实。下一步可在工具链就绪后分别构建和验收。

## 5. 后台资料仍不完整

**事实**：抽样第一页 20 部电影和 20 部剧集均没有海报；剧集第一页有 10/20 缺年份；详情样片演员、导演、简介为空；第一版计划由你后续完善接口。

**客户端处理**：真实空态、隐藏空演职员、不伪造评分/明星/海报，不把手机端全库文件名刮削当作补救。没有修改生产接口。

**需要**：后台逐步补海报、简介、演员、季集标题等；这些属于后台职责。

## 6. 跨设备同步和未实现功能

**事实**：目前片单和进度只在本机；没有统一应用身份与同步服务。夸克登录不等于观看记录同步。

**需要**：独立的应用身份、同步 API、冲突策略、隐私与删除策略。不能把夸克 Cookie 当作应用账号。

其余未实现：在线字幕、外挂字幕文件、截图/GIF/OCR、调色、均衡器、DLNA/Chromecast/AirPlay、Windows 真全屏、电视遥控焦点专项适配、全部 4K/HDR 兼容矩阵。

## 7. 构建环境细节

- CocoaPods 集成尚未实际执行。`media_kit_libs_ios_video` 的 podspec 会在 pod 安装阶段执行 `make` 并嵌入 libmpv XCFramework；这需要在第一次 macOS 构建时验证网络、版本和签名。
- 工作流固定 Flutter 3.47.8，但 `actions/*` 和 `subosito/flutter-action` 使用主版本标签，不是 commit SHA；如要求完全可复现，应在首次成功构建后固定 Action commit 与 `Podfile.lock`。
- `macos-15` runner 的 Xcode 版本在本机无法核实，首次运行可能需调整 runner/Xcode 版本。

## 8. 安全收紧

为支持局域网 HTTP，当前 iOS ATS 和 Android cleartext 均放宽。正式对外分发前应使用 HTTPS、收紧 ATS/network security config，并补充隐私说明。详见 `docs/SECURITY.md`。
