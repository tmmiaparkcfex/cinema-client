# 各端构建与安装状态

## iPhone（第一优先）

状态：**源码和 CI 工作流完成；本机未构建；无 IPA**。Windows 下实际执行 `flutter build ios` 返回“找不到 ios 子命令”，见 `docs/evidence/ios-build-attempt-20261027.log`。

环境要求：

- macOS + Xcode；
- Ruby/CocoaPods；
- Flutter 3.47.8；
- 个人 Apple ID 仅用于本地签名，不写入仓库。

命令：

```bash
flutter config --no-enable-swift-package-manager
flutter pub get
flutter analyze
flutter test
flutter build ios --release --no-codesign \
  --dart-define=VOD_API_BASE=https://your-api.example.com
```

工作流：`.github/workflows/ios-unsigned.yml`，手动运行并下载 `CinemaClient-unsigned.ipa`。

签名安装：

1. 使用你信任的侧载签名工具导入未签名 IPA；
2. 用你的个人 Apple ID 登录签名工具；
3. 选择目标 iPhone，重签并安装；
4. 在 iPhone 上信任开发者证书、允许本地网络访问；
5. 打开应用，填写/确认影视接口，再连接夸克。

当前尚无可验证的 IPA、签名或安装结果。Bundle ID 是开发用的 `com.example.cinemaClient`，正式签名前改成你自己的唯一标识。

## Android 手机

状态：**平台目录存在，代码可共享；未安装 Android SDK/Java，未构建 APK，未真机验证。**

前置：

- Android SDK、平台工具和构建工具；
- JDK 17；
- 一台 Android 手机；
- 你自己的 release keystore（后续签名）。

命令（未执行）：

```bash
flutter build apk --release \
  --dart-define=VOD_API_BASE=https://your-api.example.com
```

当前 `android/app/build.gradle.kts` 的 release 若未配置正式签名，不应把产物作为正式发布包。请先配置你的 keystore 或使用 Android App Bundle 签名流程。

安装（未执行）：

```bash
adb install -r app-release.apk
```

## Android TV / Android 盒子

状态：**AndroidManifest 已声明 leanback 入口和 touchscreen 非必需；未构建、未真机、未做遥控焦点专项验收。**

构建命令同 Android 手机。安装：

```bash
adb connect <tv-ip>:5555
adb install -r app-release.apk
```

注意事项：

- 电视启动器需要 banner 资源，当前仍是开发壳图标；
- 左右方向键在播放器内用于 seek，可能与焦点导航冲突；
- 返回键、焦点可见性、字号和 10 英尺阅读尚未验证；
- 不同厂商盒子的 WebView、Keychain 等价物和网络策略需逐机测试。

## Windows

状态：**平台目录存在；本机没有 Visual Studio C++ 工具链，未构建、未运行。**

前置：

- Windows 10/11；
- Visual Studio（Desktop development with C++ / MSVC、CMake）；
- 运行 `flutter doctor` 确认 Windows toolchain；
- Flutter 插件符号链接需要 Windows 开发者模式或等效权限（本机未擅自开启）。

命令（未执行）：

```bash
flutter build windows --release \
  --dart-define=VOD_API_BASE=https://your-api.example.com
```

产物预期：`build/windows/x64/runner/Release/`。安装即复制目录运行；当前没有安装程序或代码签名。

## 结论

只有 iOS Actions 工作流和本地 Dart/接口测试具备可执行基础；Android/Windows/TV 的“构建/安装步骤”是待验证命令，不构成已有安装包。
