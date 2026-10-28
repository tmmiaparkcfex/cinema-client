# 0.2.1 登录修复与验证

## 问题与变更

用户在 iPhone 中打开登录页，只看到夸克“立即下载”引导。隔离空白浏览器复现了手机 UA 跳往移动下载页；桌面 UA 可进入官方登录页面，但 390 像素宽度下登录表单位于屏幕右侧。

当前改为桌面网页 UA、桌面内容模式和网盘登录入口，并通过页面布局脚本选择夸克自己的“手机登录”、滚动至官方表单。脚本不读取或填写手机号、验证码、密码和 Cookie；认证仍由夸克网页完成。新增重新加载按钮，子资源错误不再误报整个登录页失败。

版本为 **0.2.1 (3)**，Bundle ID 保持不变。默认影视接口为手机已验证可用的 `http://172.16.3.70:8790`；已保存的手动配置优先。

## Cookie 链路

1. 登录在设备内 WebView 完成，使用持久 WK 数据存储。
2. `CookieManager.getCookies` 从 pan.quark.cn、drive-pc.quark.cn 读取会话；iOS 插件使用 `WKWebsiteDataStore.default().httpCookieStore.getAllCookies`，包含 HttpOnly Cookie。
3. `connectCookie` 使用读取到的 Cookie 调用夸克 `file/sort` 验证。
4. 验证通过才将会话写入系统安全存储；失败保留原会话，不显示连接成功。

本机真实无 Cookie 请求得到 HTTP 401 / code 31001。已有回归测试验证 Cookie 实际进入 HTTP 头、旋转后的会话被保存、失败不覆盖原账号。没有使用或索取用户 Cookie。

## 验证状态

- 实际公开网页：手机号和短信验证码输入框均出现；同一生产布局脚本将表单从屏幕右侧移至 390 像素视口内部。未输入账号、未发送验证码。
- 本地分析：0 issue；全量 Dart/组件回归：51 通过，3 可选跳过。
- 新增 iOS 原生 XCTest：使用独立合成 Cookie，验证实际插件可读取 pan/drive 两个域名下的 HttpOnly Cookie，结束只删除测试 Cookie。测试由 App 宿主加载；此项不等于真实账号登录验收。
- 运行 40557882470 在宿主启动阶段中止；40626497036 的独立宿主明确记录 iOS 18.5 模拟器缺少 `libswiftWebKit.dylib`，未运行 Cookie 断言。与 [WebKit 已知缺陷](https://bugs.webkit.org/show_bug.cgi?id=293831) 相符。后续固定选择 Xcode 26.3 SDK 对应的 iOS 26.2 模拟器，恢复 App 宿主测试，并保存 xcresult 和诊断记录。不能把前两次运行算作通过。
- [运行 40627746575](https://github.com/tmmiaparkcfex/cinema-client/actions/runs/40627746575) 全部成功：iOS 26.2 App 宿主中的 HttpOnly Cookie 测试 1 项通过、0 失败；正式 0.2.1 (3) IPA 已下载并校验。详见 [本次构建](IOS_BUILD-0.2.1-20261028.md)。
- 用户手机上的正向登录、实际转存和播放尚未验收；不能把公开网页或合成 Cookie 测试当成用户账号已验证。

安装新版后，在官方表单输入手机号和验证码，登录完成后点“验证登录并连接”。应用返回“我的”并显示已在本机连接后，继续验证真实播放、转存与清理。Cookie 和验证码不应发到聊天或影视接口。
