import Flutter
import UIKit
import AVFoundation
import AVKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var rexSoundChannel: FlutterMethodChannel?
  private var rexSoundPlayer: AVAudioPlayer?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.applicationRegistrar
    registrar.register(ApplePlaybackFactory(messenger: registrar.messenger()), withId: "cinema/apple-player")
    registrar.register(AppleRouteFactory(), withId: "cinema/apple-route")
    let device = FlutterMethodChannel(name: "cinema/player-device", binaryMessenger: registrar.messenger())
    device.setMethodCallHandler { call, result in
      if call.method == "brightness" {
        if let value = call.arguments as? NSNumber {
          UIScreen.main.brightness = CGFloat(max(0, min(1, value.doubleValue)))
        }
        result(Double(UIScreen.main.brightness))
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    let channel = FlutterMethodChannel(name: "cinema/rex-sound", binaryMessenger: registrar.messenger())
    rexSoundChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      if call.method == "stop" {
        self.rexSoundPlayer?.stop()
        self.rexSoundPlayer = nil
        result(nil)
        return
      }
      guard call.method == "play", let name = call.arguments as? String,
            ["welcome", "page", "complete"].contains(name) else {
        result(FlutterMethodNotImplemented)
        return
      }
      let asset = FlutterDartProject.lookupKey(forAsset: "assets/rex/sounds/\(name).wav")
      guard let path = Bundle.main.path(forResource: asset, ofType: nil) else {
        result(FlutterError(code: "MISSING_SOUND", message: "Sound asset missing", details: nil))
        return
      }
      do {
        self.rexSoundPlayer?.stop()
        try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try AVAudioSession.sharedInstance().setActive(true)
        let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
        self.rexSoundPlayer = player
        player.volume = name == "page" ? 0.32 : 0.55
        player.prepareToPlay()
        player.play()
        result(nil)
      } catch {
        result(FlutterError(code: "AUDIO_UNAVAILABLE", message: error.localizedDescription, details: nil))
      }
    }
  }
}

private final class ApplePlaybackFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    ApplePlaybackView(frame: frame, id: viewId, messenger: messenger)
  }
}

private final class AppleRouteFactory: NSObject, FlutterPlatformViewFactory {
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    AppleRouteView(frame: frame)
  }
}

private final class AppleRouteView: NSObject, FlutterPlatformView {
  private let picker: AVRoutePickerView
  init(frame: CGRect) {
    picker = AVRoutePickerView(frame: frame)
    picker.tintColor = .white
    picker.activeTintColor = .systemBlue
    picker.prioritizesVideoDevices = true
  }
  func view() -> UIView { picker }
}

private final class AppleVideoSurface: UIView {
  override class var layerClass: AnyClass { AVPlayerLayer.self }
  var videoLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private final class ApplePlaybackView: NSObject, FlutterPlatformView, AVPictureInPictureControllerDelegate {
  private let surface: AppleVideoSurface
  private let channel: FlutterMethodChannel
  private let player = AVPlayer()
  private var ready: NSKeyValueObservation?
  private var status: NSKeyValueObservation?
  private var period: Any?
  private var ended: NSObjectProtocol?
  private var failed: NSObjectProtocol?
  private var pip: AVPictureInPictureController?
  private var pending: FlutterResult?
  private var complete = false
  private var speed: Float = 1

  init(frame: CGRect, id: Int64, messenger: FlutterBinaryMessenger) {
    surface = AppleVideoSurface(frame: frame)
    channel = FlutterMethodChannel(name: "cinema/apple-player/\(id)", binaryMessenger: messenger)
    super.init()
    surface.backgroundColor = .black
    surface.isUserInteractionEnabled = false
    surface.videoLayer.player = player
    surface.videoLayer.videoGravity = .resizeAspect
    player.allowsExternalPlayback = true
    if AVPictureInPictureController.isPictureInPictureSupported() {
      pip = AVPictureInPictureController(playerLayer: surface.videoLayer)
      pip?.delegate = self
    }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      self.handle(call, result: result)
    }
    period = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] _ in
      self?.emit()
    }
  }

  func view() -> UIView { surface }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let number = call.arguments as? NSNumber
    switch call.method {
    case "open":
      guard let data = call.arguments as? [String: Any],
            let value = data["url"] as? String, let url = URL(string: value),
            url.host == "127.0.0.1" else {
        result(FlutterError(code: "PLAYER_URL", message: nil, details: nil))
        return
      }
      open(url: url, offset: (data["position"] as? NSNumber)?.int64Value ?? 0, result: result)
      return
    case "play": complete = false; player.playImmediately(atRate: speed)
    case "pause": player.pause()
    case "seek":
      complete = false
      player.seek(to: CMTime(value: number?.int64Value ?? 0, timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero)
    case "rate":
      speed = number?.floatValue ?? 1
      if player.rate != 0 { player.rate = speed }
    case "volume": player.volume = (number?.floatValue ?? 100) / 100
    case "fit":
      let value = call.arguments as? String
      surface.videoLayer.videoGravity = value == "cover" ? .resizeAspectFill : value == "fill" ? .resize : .resizeAspect
    case "audio": select(.audible, id: call.arguments as? String)
    case "subtitle": select(.legible, id: call.arguments as? String)
    case "pip":
      guard let pip = pip, pip.isPictureInPicturePossible else {
        result(FlutterError(code: "PIP_UNAVAILABLE", message: nil, details: nil))
        return
      }
      pip.startPictureInPicture()
    case "close": reset(); result(nil); return
    default: result(FlutterMethodNotImplemented); return
    }
    emit()
    result(nil)
  }

  private func open(url: URL, offset: Int64, result: @escaping FlutterResult) {
    reset()
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      result(FlutterError(code: "AUDIO_SESSION", message: nil, details: nil))
      return
    }
    complete = false
    pending = result
    let item = AVPlayerItem(url: url)
    status = item.observe(\.status, options: [.new]) { [weak self] item, _ in
      DispatchQueue.main.async {
        guard let self = self, self.player.currentItem === item else { return }
        if item.status == .failed { self.fail(); return }
        guard item.status == .readyToPlay else { return }
        if offset > 0 {
          self.player.seek(to: CMTime(value: offset, timescale: 1000)) { [weak self, weak item] _ in
            DispatchQueue.main.async {
              guard let self = self, let item = item, self.player.currentItem === item else { return }
              self.player.playImmediately(atRate: self.speed)
            }
          }
        } else {
          self.player.playImmediately(atRate: self.speed)
        }
      }
    }
    ready = surface.videoLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
      DispatchQueue.main.async {
        guard let self = self, self.player.currentItem === item, layer.isReadyForDisplay,
              let done = self.pending else { return }
        self.pending = nil
        done(nil)
        self.emit()
      }
    }
    ended = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
      self?.complete = true
      self?.emit()
    }
    failed = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
      self?.fail()
    }
    player.replaceCurrentItem(with: item)
  }

  private func fail() {
    if let done = pending {
      pending = nil
      done(FlutterError(code: "APPLE_PLAYBACK_FAILED", message: nil, details: nil))
    } else {
      channel.invokeMethod("state", arguments: ["failed": true])
    }
  }

  private func group(_ characteristic: AVMediaCharacteristic) -> AVMediaSelectionGroup? {
    player.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: characteristic)
  }

  private func select(_ characteristic: AVMediaCharacteristic, id: String?) {
    guard let item = player.currentItem, let group = group(characteristic) else { return }
    if let id = id, let index = Int(id), group.options.indices.contains(index) {
      item.select(group.options[index], in: group)
    } else if group.allowsEmptySelection {
      item.select(nil, in: group)
    }
  }

  private func emit() {
    guard let item = player.currentItem else { return }
    func ms(_ time: CMTime) -> Int64 {
      let seconds = time.seconds
      return seconds.isFinite && seconds >= 0 && seconds < 1e9 ? Int64(seconds * 1000) : 0
    }
    func choices(_ characteristic: AVMediaCharacteristic) -> ([[String: String]], String) {
      guard item.status == .readyToPlay, let group = group(characteristic) else { return ([], "") }
      let selected = item.currentMediaSelection.selectedMediaOption(in: group)
      return (group.options.enumerated().map { index, value in
        ["id": String(index), "name": value.displayName, "language": value.extendedLanguageTag ?? ""]
      }, group.options.firstIndex { $0 == selected }.map { String($0) } ?? "")
    }
    let audio = choices(.audible)
    let subtitles = choices(.legible)
    let loaded = item.loadedTimeRanges.map { ms(CMTimeRangeGetEnd($0.timeRangeValue)) }.max() ?? 0
    channel.invokeMethod("state", arguments: [
      "position": ms(player.currentTime()), "duration": ms(item.duration), "buffer": loaded,
      "playing": player.rate > 0, "buffering": player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
      "complete": complete, "pip": pip?.isPictureInPictureActive ?? false,
      "audio": audio.0, "audioId": audio.1, "subtitles": subtitles.0, "subtitleId": subtitles.1
    ])
  }

  func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) { emit() }
  func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) { emit() }
  func pictureInPictureController(_ controller: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) { completionHandler(true) }

  private func reset() {
    if let done = pending {
      pending = nil
      done(FlutterError(code: "PLAYER_CLOSED", message: nil, details: nil))
    }
    pip?.stopPictureInPicture()
    ready = nil
    status = nil
    if let ended = ended { NotificationCenter.default.removeObserver(ended) }
    if let failed = failed { NotificationCenter.default.removeObserver(failed) }
    ended = nil
    failed = nil
    player.pause()
    player.replaceCurrentItem(with: nil)
  }

  deinit {
    reset()
    if let period = period { player.removeTimeObserver(period) }
    channel.setMethodCallHandler(nil)
  }
}
