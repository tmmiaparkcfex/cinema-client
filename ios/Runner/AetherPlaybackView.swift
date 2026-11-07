import AetherEngine
import AVKit
import Flutter
import UIKit

final class AetherPlaybackFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let view: AetherPlaybackView = MainActor.assumeIsolated {
      AetherPlaybackView(frame: frame, id: viewId, messenger: messenger)
    }
    return view
  }
}

@MainActor
private final class AetherPlaybackView: NSObject, @preconcurrency FlutterPlatformView,
  @preconcurrency AVPictureInPictureControllerDelegate {
  private let surface: AetherPlayerView
  private let channel: FlutterMethodChannel
  private let caption = UILabel()
  private var images: [UIImageView] = []
  private var engine: AetherEngine?
  private var timer: Timer?
  private var task: Task<Void, Never>?
  private var pip: AVPictureInPictureController?
  private var pending: FlutterResult?
  private var ready = false

  init(frame: CGRect, id: Int64, messenger: FlutterBinaryMessenger) {
    surface = AetherPlayerView(frame: frame)
    channel = FlutterMethodChannel(name: "cinema/apple-player/\(id)", binaryMessenger: messenger)
    super.init()
    surface.backgroundColor = .black
    surface.isUserInteractionEnabled = false
    caption.textColor = .white
    caption.font = .systemFont(ofSize: 17, weight: .semibold)
    caption.textAlignment = .center
    caption.numberOfLines = 4
    caption.layer.shadowColor = UIColor.black.cgColor
    caption.layer.shadowOpacity = 1
    caption.layer.shadowRadius = 2
    caption.layer.shadowOffset = .zero
    surface.addSubview(caption)
    channel.setMethodCallHandler { [weak self] call, result in
      MainActor.assumeIsolated {
        guard let self else { result(nil); return }
        self.handle(call, result: result)
      }
    }
  }

  func view() -> UIView { surface }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let number = call.arguments as? NSNumber
    let text = call.arguments as? String
    switch call.method {
    case "open":
      guard let data = call.arguments as? [String: Any],
            let url = (data["url"] as? String).flatMap(URL.init(string:)),
            url.host == "127.0.0.1" else {
        result(FlutterError(code: "PLAYER_URL", message: nil, details: nil))
        return
      }
      open(url, offset: ((data["position"] as? NSNumber)?.doubleValue ?? 0) / 1000, result: result)
      return
    case "close":
      reset()
    case "play": engine?.play()
    case "pause": engine?.pause()
    case "seek":
      let seconds = (number?.doubleValue ?? 0) / 1000
      Task { await engine?.seek(to: seconds) }
    case "rate": engine?.setRate(number?.floatValue ?? 1)
    case "volume": engine?.volume = (number?.floatValue ?? 100) / 100
    case "fit":
      engine?.videoGravity = text == "cover" ? .resizeAspectFill : text == "fill" ? .resize : .resizeAspect
    case "audio":
      if let id = text.flatMap(Int.init) { engine?.selectAudioTrack(index: id) }
    case "audio-delay": engine?.setAudioDelay(number?.doubleValue ?? 0)
    case "subtitle":
      if let id = text.flatMap(Int.init) { engine?.selectSubtitleTrack(index: id) }
      else { engine?.clearSubtitle() }
    case "secondary":
      if let id = text.flatMap(Int.init) { engine?.selectSecondarySubtitleTrack(index: id) }
      else { engine?.clearSecondarySubtitle() }
    case "external-subtitle":
      if let path = text, let engine {
        let file = URL(fileURLWithPath: path)
        let track = engine.addExternalSubtitleTrack(ExternalSubtitleTrack(url: file, name: file.lastPathComponent))
        engine.selectSubtitleTrack(index: track.id)
      }
    case "pip":
      if !startPiP() {
        result(FlutterError(code: "PIP_UNAVAILABLE", message: nil, details: nil))
        return
      }
    default:
      result(FlutterMethodNotImplemented)
      return
    }
    result(nil)
  }

  private func open(_ url: URL, offset: Double, result: @escaping FlutterResult) {
    reset()
    do {
      let player = try AetherEngine()
      player.backgroundPlaybackEnabled = false
      player.bind(view: surface)
      engine = player
      pending = result
      timer = Timer.scheduledTimer(withTimeInterval: 0.20, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.emit() }
      }
      task = Task { [weak self, weak player] in
        guard let self, let player else { return }
        do {
          var options = LoadOptions()
          options.confirmAtmos = true
          try await player.load(url: url, startPosition: offset, options: options)
          guard !Task.isCancelled, self.engine === player else { return }
          player.play()
          self.emit()
        } catch {
          guard !Task.isCancelled, self.engine === player else { return }
          self.fail()
        }
      }
    } catch {
      result(FlutterError(code: "AETHER_INIT_FAILED", message: nil, details: nil))
    }
  }

  private func fail() {
    if let done = pending {
      pending = nil
      done(FlutterError(code: "AETHER_PLAYBACK_FAILED", message: nil, details: nil))
    } else if ready {
      ready = false
      channel.invokeMethod("state", arguments: ["failed": true])
    }
  }

  private func emit() {
    guard let engine else { return }
    if case .error = engine.state { fail(); return }
    if engine.isSessionReady, engine.state == .playing, let done = pending {
      pending = nil
      ready = true
      done(nil)
    }
    func millis(_ seconds: Double) -> Int64 {
      seconds.isFinite && seconds >= 0 && seconds < 1e9 ? Int64(seconds * 1000) : 0
    }
    func mapTrack(_ track: TrackInfo) -> [String: String] {
      ["id": String(track.id), "name": track.name, "language": track.language ?? "",
       "codec": track.isAtmos == true ? track.codec + " · Atmos" : track.codec]
    }
    channel.invokeMethod("state", arguments: [
      "position": millis(engine.clock.currentTime), "duration": millis(engine.duration),
      "buffer": millis(engine.clock.bufferedPosition), "playing": engine.state == .playing,
      "buffering": engine.isBuffering, "complete": engine.state == .ended,
      "pip": pip?.isPictureInPictureActive ?? false, "audio": engine.audioTracks.map(mapTrack),
      "audioId": engine.activeAudioTrackIndex.map { String($0) } ?? "",
      "subtitles": engine.subtitleTracks.map(mapTrack),
      "subtitleId": engine.activeSubtitleTrackIndex.map { String($0) } ?? "",
      "chapters": engine.mediaChapters.map { ["position": millis($0.startSeconds), "title": $0.name] }
    ])
    renderSubtitles(engine)
  }

  private func renderSubtitles(_ engine: AetherEngine) {
    let cues = engine.subtitleCues + engine.secondarySubtitleCues
    let rect = engine.nativePlayerLayer?.videoRect ?? surface.bounds
    caption.frame = CGRect(x: rect.minX + 16, y: max(rect.minY, rect.maxY - 88),
                           width: max(0, rect.width - 32), height: 62)
    caption.text = cues.compactMap(\.text).joined(separator: "\n")
    surface.bringSubviewToFront(caption)
    let bitmaps = cues.compactMap { cue -> SubtitleImage? in
      if case .image(let image) = cue.body { return image }
      return nil
    }
    while images.count > bitmaps.count { images.removeLast().removeFromSuperview() }
    while images.count < bitmaps.count {
      let image = UIImageView()
      image.contentMode = .scaleToFill
      surface.addSubview(image)
      images.append(image)
    }
    for (view, image) in zip(images, bitmaps) {
      view.image = UIImage(cgImage: image.cgImage)
      let p = image.position
      view.frame = CGRect(x: rect.minX + p.minX * rect.width, y: rect.minY + p.minY * rect.height,
                          width: p.width * rect.width, height: p.height * rect.height)
    }
  }

  private func startPiP() -> Bool {
    guard AVPictureInPictureController.isPictureInPictureSupported(), let engine else { return false }
    if let layer = engine.nativePlayerLayer {
      pip = AVPictureInPictureController(playerLayer: layer)
    } else {
      pip = engine.softwarePiPSource?.makePictureInPictureController()
    }
    guard let pip, pip.isPictureInPicturePossible else { self.pip = nil; return false }
    pip.delegate = self
    engine.pictureInPictureActive = true
    pip.startPictureInPicture()
    return true
  }

  func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) { emit() }
  func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
    engine?.pictureInPictureActive = false
    emit()
  }
  func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
    engine?.pictureInPictureActive = false
    emit()
  }

  private func reset() {
    task?.cancel()
    task = nil
    timer?.invalidate()
    timer = nil
    if let done = pending {
      pending = nil
      done(FlutterError(code: "PLAYER_CLOSED", message: nil, details: nil))
    }
    pip?.stopPictureInPicture()
    pip = nil
    engine?.stop()
    engine = nil
    ready = false
    caption.text = nil
    images.forEach { $0.removeFromSuperview() }
    images.removeAll()
  }

  deinit {
    timer?.invalidate()
    task?.cancel()
    channel.setMethodCallHandler(nil)
  }
}
