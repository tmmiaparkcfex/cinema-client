# 播放内核与跨端框架选型

日期：2026-10-27。结论针对当前“iPhone 优先、四端统一、不得用 WebView 播放演示”的目标。

## 结论

- UI 与业务：**Flutter 3.47.8 stable / Dart 3.13.7**。
- 播放：**media_kit 1.2.6 + media_kit_video 2.0.1 + media_kit_libs_video 1.0.7**。
- iOS 原生库：`media_kit_libs_ios_video 1.1.4`，vendored libmpv/FFmpeg XCFramework，经 CocoaPods 集成。
- iOS 部署目标：15.0。
- 理由：一套 Dart 代码生成 iOS/Android/Windows 原生应用；libmpv 能处理目标片源的 MKV/HEVC/多音轨/内嵌字幕，并通过 `httpHeaders` 传递取流所需请求头；UI 和播放均不是 WebView。
- **尚未证明的部分**：iPhone 真机 4K HEVC 持续播放、硬解、HDR/杜比视界、功耗、长时间内存。选型成立不等于这些指标已通过。

## 候选比较

| 方案 | 形态与平台 | 事实性版本/维护证据 | 许可证与分发注意 | 是否采用 |
| --- | --- | --- | --- | --- |
| **Flutter + media_kit/libmpv** | Flutter 原生应用；Android/iOS/macOS/Windows/Linux 等 | media_kit 1.2.6 于 2025-12-13 发布；仓库 main 在 2026-08 仍有提交；Flutter 3.47.8 于 2026-10-23 发布 | media_kit 为 MIT；iOS 原生库包为 MIT 包装；libmpv/FFmpeg 的 `default`/`full` 播放构建为 LGPL-2.1，`encodersgpl` 为 GPL-2.1，不可混用 | **是** |
| VLCKit (`videolan/vlckit`) | Apple：macOS/iOS/tvOS | 官方镜像；2026-10-01 仍有提交；2026-09-30 发布 4.0.0a25 到 CocoaPods/SPM | LGPL-2.1；需要动态链接/可替换等 LGPL 合规；不能覆盖 Android/Windows | 否（Apple 单端候选） |
| VLC for Android (`videolan/vlc-android`) | Android/Android TV/ChromeOS | 官方仓库；2026-10 仍活跃；NEWS 记录 3.7.2 | 应用 GPLv2+，实际依赖使其成为 GPLv3；LibVLC 为 LGPLv2 | 否（不能作为四端单一方案） |
| KSPlayer | Apple：iOS/macOS/tvOS/visionOS | 2026-10 仍活跃；README 声称 HDR/杜比视界/字幕能力 | 默认 GPL；LGPL 及部分高级功能是付费授权。不能直接当免费商用库 | 否 |
| AetherEngine | Apple：iOS/tvOS/macOS/visionOS | 2026-10 存在且活跃；仓库 README 面向 Apple 平台 | LGPL-3.0 + Apple Store/DRM 例外；只解决 Apple，不覆盖 Android/Windows/TV | 否（Apple 单端候选） |
| HTML/WebView 播放 | 浏览器/Dart WebView | 不适用 | 依赖系统 WebView 编解码，无法满足正式原生播放要求 | 明确排除 |

## 固定版本

来自 `pubspec.lock`：

| 包 | 版本 | 用途 | 许可证 |
| --- | --- | --- | --- |
| Flutter | 3.47.8 (`737ba8f885`) | SDK | BSD-3-Clause |
| Dart | 3.13.7 | 语言/SDK | BSD-3-Clause |
| media_kit | 1.2.6 | 播放 API | MIT |
| media_kit_video | 2.0.1 | 原生视频输出 | MIT |
| media_kit_libs_video | 1.0.7 | 原生库聚合 | MIT |
| media_kit_libs_ios_video | 1.1.4 | iOS libmpv XCFramework | MIT 包装；libmpv/FFmpeg 见下 |
| media_kit_libs_android_video | 1.3.8 | Android 原生库 | MIT 包装；底层见依赖声明 |
| media_kit_libs_windows_video | 1.0.11 | Windows 原生库 | MIT 包装；底层见依赖声明 |
| flutter_inappwebview | 6.1.5 | 仅用于账号网页登录 | Apache-2.0 |
| flutter_secure_storage | 11.2.0 | Keychain/Keystore | BSD-3-Clause |
| http | 1.6.0 | 影视 API | BSD-3-Clause |
| path_provider | 2.1.6 | 应用支持目录 | BSD-3-Clause |
| shared_preferences | 2.5.6 | 本地片单/进度/接口地址 | BSD-3-Clause |

`pubspec.lock` 是完整固定清单；`Podfile.lock` 需要在 macOS 首次构建后生成。GitHub 工作流会把两者一起上传。

## libmpv/FFmpeg 许可说明

`media-kit/libmpv-darwin-build` 的 README 明确列出：

- mpv：LGPL-2.1，`-Dgpl=false`；
- FFmpeg `default`/`full`：LGPL-2.1，省略 `--enable-gpl` 和 `--enable-nonfree`；
- FFmpeg `encodersgpl`：GPL-2.1，含 GPL 编码器，不能作为闭源商业分发；
- libass：ISC；FreeType、HarfBuzz、FriBidi 等各有独立许可。

因此“可播放”不等于“任何构建都能闭源分发”。正式分发前必须核对实际 vendored 二进制属于哪个 flavor，保留版权/许可文本，并满足 LGPL 的源码与可替换链接义务。该结论不是法律意见；商业上架前应由熟悉开源合规的律师复核。

## 为什么不用 AVPlayer/KSPlayer 作为 iPhone 唯一实现

- AVPlayer 对 MKV 容器支持不足，目标片源大量为 MKV；本地重封装增加复杂度。
- KSPlayer 默认 GPL，LGPL 与高级功能另收费。
- AetherEngine 与 VLCKit 只覆盖 Apple，无法自然形成四端同一 UI/数据层。
- 统一 Flutter + libmpv 是当前代码量最小、四端覆盖最直接的方案。若后续真机发现 libmpv 在目标 iPhone 上功耗/硬解不达标，可把播放层替换为 Apple 原生（AVPlayer/AetherEngine）而保留 Flutter 业务层，但这需要新的验证和许可决策。

## 未验证项

- iPhone 机型、iOS 版本与 libmpv 硬解路径；
- 4K HEVC 10-bit、Dolby Vision、HDR10/HLG 的实际显示和色准；
- 连续播放内存、发热、耗电、后台/前后台切换；
- HTTP Range、临时直链过期、Cookie 请求头的实际 CDN 行为；
- 字幕字体/ASS 渲染、图像字幕和多音轨；
- Android TV 遥控焦点、Windows 高 DPI/全屏；
- CocoaPods 构建和 `Podfile.lock` 的可复现结果。
