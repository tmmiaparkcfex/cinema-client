# iPhone 0.2.1 (3) 实际构建与 Cookie 验证

[Actions 40627746575](https://github.com/tmmiaparkcfex/cinema-client/actions/runs/40627746575) 已全部成功。实际编译源码为 `4e248d30ecf59d9681cd857206ffe51a5ed2b8ef`；后续文档提交不改变此包的来源。

| 项目 | 实际结果 |
| --- | --- |
| 静态分析 | 0 issue |
| Dart / 组件测试 | 51 通过、3 个可选跳过 |
| iOS 原生 Cookie 测试 | iPhone 17 Pro / iOS 26.2 模拟器，1 项通过、0 失败，断言执行约 10 秒 |
| 原生测试内容 | App 宿主内调用实际 iOS 插件，读取 `.quark.cn` 合成 HttpOnly Cookie；pan、drive-pc 两域均能读取，结束删除此测试 Cookie |
| 正式编译 | Release / 无签名；Xcode 编译 222.9 秒，Runner.app 61.4 MB |
| 工具链 | Flutter 3.47.8、Dart 3.13.7、Xcode 26.3、CocoaPods 1.17.0 |
| IPA | 0.2.1 (3)，26,748,761 bytes |
| 应用标识 / 设备 | `com.example.cinemaClient`，iPhone arm64，最低 iOS 15.0 |
| 正式接口 | AOT 二进制含 `http://172.16.3.70:8790`，不含测试用 `http://127.0.0.1:9` |
| 播放库 / 字体 | 实际 Mpv arm64 iOS 动态库、FFmpeg/Ass 等框架、与源码哈希一致的 Noto Sans SC |
| 依赖锁文件 | 下载产物的 `pubspec.lock`、`ios/Podfile.lock` 与源码哈希一致 |

IPA SHA-256：`ce8644bea7656bb32093dcc8d9b4204212f81b110a3c8d1d7107b38f7d657e1e`。下载 ZIP 与 IPA 的 CRC 检查通过；IPA 与工作流生成的校验值一致，交付副本再次哈希一致。

安装文件：`D:\codex\01_对话项目\Codex手机任务\cinema-client-build-20261028\0.2.1\CinemaClient-0.2.1-unsigned.ipa`。同目录保留校验文件、安装说明、完整原始产物和诊断记录。

`docs/evidence/ios-021-*` 保存本次结果、原生测试摘要及日志摘录、分析、Dart 测试、正式编译、工具链和包内容核验。完整 Xcode 日志与 xcresult 在上述构建目录的 diagnostics 中；两次先前未通过的原生验证见 [登录修复记录](QUARK_LOGIN-20261028.md)。

## 手机验收边界

本次原生测试使用合成 Cookie，不使用用户账号；它证明插件读取能力，不能证明用户账号已登录或可播放。正式 IPA 仍需用户个人签名并覆盖安装。应保持此前签名账号与应用标识，以保留现有接口设置。

打开“我的 → 夸克账号 → 连接”，在官方手机号验证码表单完成登录，再点击“验证登录并连接”。代码只有在 Cookie 通过夸克文件接口验证后才保存并显示成功。随后用已知正常的小视频检查真实转存、取链、播放和退出清理。验证码和 Cookie 不需要交给聊天或影视接口。

首个 0.2.0 的安装与目录展示已由用户确认。0.2.1 在用户 iPhone 上的登录、真实播放及 4K/HDR/发热功耗尚未验收；模拟器名称不代表用户手机型号。
