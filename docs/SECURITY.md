# 安全与隐私边界

## 凭据

- 夸克账号登录在设备内 WebView 完成；应用不让用户把密码/Cookie 发到聊天或影视接口。
- 登录后的 Cookie 使用 `flutter_secure_storage` 存入 iOS Keychain / Android Keystore。
- Cookie 只在以下位置使用：
  - `drive-pc.quark.cn` 的夸克 API 请求；
  - 交给 libmpv 的直链请求头。
- Cookie 不进入影视接口、同步服务、Git、日志、测试夹具或错误消息。
- 应用没有开发者夸克公共账号。

## 日志

`AppLog` 写入应用支持目录：

- 只记录路径、状态码、耗时、字节数、错误种类；
- 对 URL、Cookie、token/password 做替换；
- 不记录分享 URL、直链、文件 ID、Cookie 或账号；
- 最大 1 MiB，超限轮换一份 previous 文件。

## 网络

- iOS 为支持用户填写的局域网 HTTP 接口，当前 `Info.plist` 使用 `NSAllowsArbitraryLoads=true`。这扩大了明文网络能力，正式上架前必须改成 HTTPS 并收紧 ATS。
- Android 当前 `usesCleartextTraffic=true`，原因同上；正式生产应使用 HTTPS 并移除全局明文许可。
- iOS 会请求本地网络权限，文案明确只连接用户填写的接口，不扫描其他设备。
- 夸克 API 和直链均为 HTTPS。
- 影视接口如果是 HTTP，观看记录/目录可能被同一网络窃听；应用界面会显示风险提示。

## 临时文件

- 只保存到 `.cinema-client` 应用专用目录。
- 只记录本应用 `sharepage/save` 返回的 fid。
- 删除接口只接受登记过的 fid；不按目录清空，不触碰用户已有文件。
- 退出播放器立即尝试删除；启动和手动清理重试残留。
- 转存会把大文件放入观看者自己的网盘配额；不会向服务器集中下载。

## 应用数据

- 观看历史、片单、接口地址在 SharedPreferences。卸载时会随应用数据删除（iOS Keychain 可能保留安全存储项，取决于系统行为）。
- 首页缓存只保存片名、年份、类型、海报 URL、简介、覆盖度和提示文本；不保存分享/播放地址。
- 暂无跨设备同步，因此没有把本机目标写入远程账户。

## 分发与签名

- 仓库不含 Apple 证书、描述文件、App Store 密钥或公证凭据。
- 当前只产出未签名 IPA；个人 Apple ID 签名在设备/签名工具侧完成，凭据不经过本仓库。
- 不允许把生产令牌、Cookie 或私有播放地址提交到 Git。

## 仍需改进

- 将 HTTP 接口升级为 HTTPS，并移除 iOS/Android 全局明文放宽。
- 对用户填写的接口地址增加更强的来源提示；若未来支持公网多租户，增加证书固定/域名白名单。
- 若被要求对外分发，补齐 LGPL 源码/替换说明和第三方通知。
- 清理策略需要真实账号下的失败注入测试（断网、退出进程、删除失败、账号过期）。
