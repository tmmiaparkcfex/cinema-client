# 第三方组件与许可证说明

本文件是工程审核记录，不是法律意见。仓库本身未声明对外分发许可；以下第三方组件仍分别适用其许可证。

## 核心

| 组件 | 版本 | 许可证 | 来源 |
| --- | --- | --- | --- |
| Flutter / Dart | 3.47.8 / 3.13.7 | BSD-3-Clause | https://github.com/flutter/flutter |
| media_kit | 1.2.6 | MIT | https://github.com/media-kit/media-kit |
| media_kit_video | 2.0.1 | MIT | 同上 |
| media_kit_libs_video | 1.0.7 | MIT 包装 | 同上 |
| media_kit_libs_ios_video | 1.1.4 | MIT 包装 | https://github.com/media-kit/libmpv-darwin-build |
| libmpv Darwin build | 随 1.1.4 | mpv LGPL-2.1；FFmpeg `default/full` LGPL-2.1；`encodersgpl` GPL-2.1 | 同上 |
| FFmpeg / libass / Freetype 等 | 随 libmpv | 各自许可证，见上游 README | 同上 |

`libmpv-darwin-build` README 说明：用于播放的商业构建应使用 `default`/`full`（不含 GPL 编码器）；`encodersgpl` 含 GPL 组件，不用于闭源商业分发。必须核对实际打包 flavor，履行 LGPL 的版权通知、源码提供与可替换链接义务。

## Flutter 依赖

| 组件 | 版本 | 许可证 |
| --- | --- | --- |
| flutter_inappwebview | 6.1.5 | Apache-2.0 |
| flutter_secure_storage | 11.2.0 | BSD-3-Clause |
| http | 1.6.0 | BSD-3-Clause |
| path_provider | 2.1.6 | BSD-3-Clause |
| shared_preferences | 2.5.6 | BSD-3-Clause |
| cupertino_icons | 1.0.8 | MIT |
| package_info_plus / wakelock_plus 等传递依赖 | 见 `pubspec.lock` | 各自许可证 |

Flutter 的 `LicenseRegistry` 在打包时会收集依赖许可证文本；本应用尚未提供独立“开源许可”页面，正式分发前应补上，并随包附带 libmpv/FFmpeg 的许可证与源码获取方式。

## 未采用候选

- VLCKit：LGPL-2.1，Apple 单端。
- VLC for Android：应用 GPLv3，LibVLC LGPLv2，Android 单端。
- KSPlayer：默认 GPL；LGPL 与高级能力为付费授权。
- AetherEngine：LGPL-3.0 + Apple Store/DRM 例外，Apple 单端。

## 分发提醒

- “开源”不等于所有构建都可免费闭源分发。
- 若未来对外发布，需要：
  1. 固定实际 libmpv/FFmpeg flavor 与版本；
  2. 附第三方许可证、版权和源码链接；
  3. 满足 LGPL 对动态/可替换链接与修改源码的要求；
  4. 由合格律师复核 App Store 条款与 LGPL 的冲突处理。
