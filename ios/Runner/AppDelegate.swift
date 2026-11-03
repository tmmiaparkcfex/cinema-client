import Flutter
import UIKit
import VideoToolbox
import CoreMedia

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CinemaDeviceVitals") {
      CinemaDeviceVitals.register(with: registrar)
    }
  }
}

final class CinemaDeviceVitals: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "cinema/device_vitals", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(CinemaDeviceVitals(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "excludeDownloadsFromBackup" {
      // Large offline media belongs to this app but must not fill iCloud backups.
      do {
        var folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
          .appendingPathComponent("downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        result(nil)
      } catch {
        result(FlutterError(code: "download_storage", message: "Unable to configure offline media storage", details: nil))
      }
      return
    }
    guard call.method == "read" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let state: String
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: state = "nominal"
    case .fair: state = "fair"
    case .serious: state = "serious"
    case .critical: state = "critical"
    @unknown default: state = "unknown"
    }
    result([
      "thermalState": state,
      "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
      "hevcHardwareDecode": VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
    ])
  }
}
