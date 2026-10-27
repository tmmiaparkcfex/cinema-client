# 本轮验证 · 2026-10-27 · 0.2.0+2

本记录是本轮状态依据；原 `VERIFICATION.md` 及旧日志保留为历史。测试通过、真实接口读取、设备播放分别记载，不能互相替代。

2026-10-28 后续：iOS Actions 已编译成功并生成 IPA，实际结果见 [IOS_BUILD-20261028.md](IOS_BUILD-20261028.md)。以下本地测试与原生 Windows 证据保留原采样时间。

## 源码一致性与环境

正式源码：`D:\codex\01_对话项目\Codex手机任务\cinema-client`。英文验证副本：`D:\Codex\work\cinema-client-20261027-codex`。验证前逐文件比对 SHA-256，依赖由锁文件解析，以避开本机分析器的中文路径 URI 故障。Flutter 3.47.8 / Dart 3.13.7，SDK/缓存/本轮产物均在 D 盘。未提交/推送远程，也未执行 Actions。

## 实际结果

| 检查 | 结果 | 原始证据 |
| --- | --- | --- |
| 静态分析 | 0 issue | `evidence/codex-analyze-20261027.log` |
| 默认全量测试 | 51 passed、3 optional skipped | `evidence/codex-tests-20261027.log` |
| 真实 API 只读 | 1 passed、1 skipped | `evidence/codex-live-api-20261027.log` |
| 完整资料布局与横屏控件 | 1 passed，5 张图，无布局异常 | `evidence/codex-visual-20261027.log`、`screenshots/codex/` |
| 原生 libmpv | Windows FFI 指定路径通过 | `evidence/codex-native-engine-20261027.log` |

默认跳过：真实接口入口 1、可选截图 2。真实接口额外多季测试因当前 TV 第一页没有重复 workId 而跳过，不能记为通过。

回归重点：首次空登记、取消不堵队列、转存任务恢复、不删已有文件、21 项登记不截断、释放失败重试、重复释放合并、切账号隔离、旧请求不覆盖新 Cookie、登录失败保留旧会话、同文件刷新直链、目录有效分页、跨季归并/续播/下一集、缓存剔除分享入口、字幕副本清理、日志脱敏、慢元数据不阻塞账号连接。

## 真实影视接口

22:46–22:47 本机 GET 采样：

```text
home=20 moviePage=20 tvPage=20 search=1
detailLines=2 detailEntries=17 resourceMatched=true
```

home/list/detail/search/resource 均 200；资源描述 id/fileId/shareId 与详情对应。单请求 7,644–10,373 ms，受生产负载影响，不能推导手机起播速度。本轮没有向生产调用转存、删除或代播。

多季合并有模拟测试和生产响应源码依据，但真实样本本轮未命中，仍需现场验收。

## 原生内核实测

实际加载当前 Windows 插件锁定的 `libmpv-2.dll`，通过生产 `createNativePlayer()` 工厂运行。测试用 FFmpeg 生成自己的 8 秒 MKV：3840×2160、HEVC 10-bit、12 fps、两条 AAC 音轨及 SRT。

环境为 Windows、无界面、软件解码，关闭 GPU 和音频输出。实测 mpv `v0.36.0-403-g652a1dd907`、解码格式 `yuv420p10`；第二音轨、外挂 SRT、1.5 倍、拖动约 5.417 秒、重开续播 3 秒、本地鉴权 HTTP 头及 6 次 Range 请求均通过。

**未验证** iPhone、GPU 显示、硬解、HDR、杜比视界、ASS/PGS 实际画面、扬声器输出、功耗和真实夸克 CDN。原生字幕配置已实现不等于上述设备验收完成。

原始测试源：`evidence/codex-native-engine-smoke.dart.txt`。测试 DLL、合成样片和临时 HTTP 服务器在本轮工作证据目录中，不进入产品资源；测试结束关闭服务器。

| 来源 | 固定信息 |
| --- | --- |
| [Windows 上游发布](https://github.com/media-kit/libmpv-win32-video-build/releases/tag/2023-09-24) | `mpv-dev-x86_64-20230924-git-652a1dd.7z` |
| 插件固定 MD5 | `a832ef24b3a6ff97cd2560b5b9d04cd8`，已核对 |
| 下载归档 SHA-256 | `dce982222d7a23e4a1c6f0fb6cc39f6e899a6714624b95ea49cff6558ee97572` |
| iOS 插件 Makefile | Darwin build v0.6.0、`universal-video-default.tar.gz`；尚未由 Xcode 下载/链接验证 |

该 Windows 上游仓库已归档；指定功能通过不构成维护状态或全格式兼容性保证。本轮没有未经验证就替换平台二进制。

## 版型检查

渲染当前 Home、Detail、选集和生产 PlaybackControls，尺寸为手机 390×844、桌面 1440×900、横屏 844×390。完整资料用虚构片名和此前原创示意图，**仅在外部布局测试注入**，产品始终接真实 API。

这些不是设备截图或视频播放证据；横屏背景是测试图片。`screenshots/` 根目录早期 4 张图仍是旧版公开目录快照，不能当作本轮设备验收。

## 仍待完成

- Actions、CocoaPods、iOS 链接和 IPA 已于次日验证；仍待个人签名安装和真实观看者账户全链路。
- iPhone/GPU/硬解/HDR、生命周期、网络切换、长期稳定性、发热和耗电。
- Android/Windows/TV 应用构建与设备操作。
- 真实账号上的风控/空间/转存/清理恢复。
- 在线字幕、投屏、跨设备同步等功能，见 `KNOWN_ISSUES.md`。

后续已完成 iOS 编译，当前可签名安装并进行真机联调，不能表述为完整四端产品已交付。
