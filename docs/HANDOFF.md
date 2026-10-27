# 接续事实索引 · 2026-10-27 · 0.2.0+2

本文索引事实和证据，接手者仍需独立检查需求、代码和运行结果。

## 用户目标

真实 Netflix 风格影视客户端；四端为 iPhone、Android 手机、Windows、Android TV/盒子，先跑通 iPhone。真实 vod-web 目录，观看者自己的夸克账号/IP/流量。用户后续完善爬虫资料，客户端现在即接 API。用户已选择 GitHub Actions 编译。

## 位置与版本

| 内容 | 路径 |
| --- | --- |
| 正式源码 | `D:\codex\01_对话项目\Codex手机任务\cinema-client` |
| 本轮英文验证副本 | `D:\Codex\work\cinema-client-20261027-codex` |
| SDK / Pub 缓存 | `D:\Codex\tools\flutter` / `D:\Codex\cache\pub` |
| 本轮工作证据 | 同级 `cinema-client-progress-20261027` |
| 较早审核 | 同级 `cinema-client-audit-20261027`；旧缺陷复现测试不能当成现版结果 |
| 生产服务 | `D:\各软件安装位置\vod-web`；本轮未修改 |

接手时 HEAD 为 `720f05ac12693041e8ffbc3137d5d764380d9fdc`，已有 6 文件草稿。本轮保留并继续修改；原始 6 文件及哈希在工作证据的 `baseline/`。本轮没有提交/推送 Git，也未执行远程 Actions。

## 已有证据

- 分析 0 issue，默认测试 51 通过、3 可选跳过。
- 真实 API home/list/detail/resource/search 读取及资源匹配通过；多季样本当前页未命中而跳过。
- 原生 Windows FFI 软件解码通过指定 4K HEVC 10-bit、双音轨、外挂 SRT、Range/请求头、拖动/续播/倍速测试。
- 实际 Flutter 页面及横屏控件已渲染检查；新增完整资料版型图为虚构作品/原创示意图，仅在外部布局测试注入。
- 无 IPA、Podfile.lock、iPhone 真机和真实夸克账户验收；其他三端应用未构建。

最新结果及日志：[VERIFICATION-20261027-CODEX.md](VERIFICATION-20261027-CODEX.md)。原 `VERIFICATION.md` 留作历史，不代表现版测试数量。

## 代码核查入口

| 文件 | 本轮重点 |
| --- | --- |
| `lib/quark/quark_playback_service.dart` | 串行队列、取消、转存前登记、任务恢复、分页快照、所有权检查、无 20 条截断、租约刷新/释放 |
| `lib/quark/quark_account_store.dart` | Cookie 与随机会话范围同一安全存储值；刷新保留范围，显式登录换范围 |
| `lib/player/native_player.dart` | 原生 libass 与 Android 字体 |
| `lib/player/playback_screen.dart` | 原生播放、首次渲染、超时、换集并发、停止后释放、进度/结束/下一集、外挂字幕、焦点 |
| `lib/data/api_client.dart` | exact workId 补季；当前季可先播放 |
| `lib/core/app_models.dart`、`lib/data/local_store.dart` | 作品身份、元数据、仅驻内存的目录资源、跨季记录与实际 API key |
| `test/*` | 清理/取消/身份/季集/隐私/控件/慢元数据回归 |
| `.github/workflows/ios-unsigned.yml` | 工具链固定、锁依赖、测试/构建、IPA 打包及失败诊断 |

## 尚未消除的边界

- 随机会话范围不是核实过的服务端 UID。显式重登后旧范围残留不由新凭据自动删除。
- 请求已受理但响应在收到 taskId/fid 前丢失时保留未决登记，不按同名文件猜删。
- 只删除同范围、具有所有权证据的新 fid，不清空目录。
- Windows 依赖固定 2023 年内核；实测结果不证明全格式兼容性和维护状态。
- VideoController 首帧 Future 仅证明该控制器首次渲染；后续换源的逐文件画面更新仍需设备验证。
- 四端、HDR、功耗、真实账号、同步/投屏/媒体工具等限制见 `KNOWN_ISSUES.md`。

## 后台与下一项外部结果

接手前只读确认 `127.0.0.1:8790/ctrl/state` 为 `running=true`、PID 12360。本轮只发影视 API GET，没有启动/停止生产服务或爬虫，也没有使用服务端账号转存。最终快照在 `evidence/background-codex-20261027.json`。

下一项外部结果为用户 Actions 构建日志和签名安装后的设备验收，步骤见 [BUILD.md](BUILD.md)。不要将未验证事项直接记作完成。
