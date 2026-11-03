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
