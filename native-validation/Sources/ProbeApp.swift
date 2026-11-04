import AVFoundation
import MediaPlayer
import MPVUI
import Observation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

@main
struct ProbeApp: App {
    var body: some Scene { WindowGroup { ProbeView() } }
}

@MainActor
@Observable
final class ProbeModel {
    let player = MPVPlayer(configuration: .init(autoPlay: false))
    var title = "请选择测试文件"
    var error: String?
    var preview: Double?
    private var scopedURL: URL?

    func open(_ url: URL, scoped: Bool = false) {
        stop()
        if scoped {
            guard url.startAccessingSecurityScopedResource() else {
                error = "无法读取文件，请重新选择。"
                return
            }
            scopedURL = url
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
            error = nil
            title = url.isFileURL ? url.lastPathComponent : "网络媒体（地址不写入报告）"
            player.setDiagnosticsEnabled(true)
            player.load(url, autoPlay: true)
        } catch {
            self.error = error.localizedDescription
            stop()
        }
    }

    func stop() {
        player.stop()
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        preview = nil
    }

    func snapshot() -> String {
        let d = player.playbackDiagnostics
        let b = player.bufferStatus
        return """
        原生播放验证 · MPVUI 0.7.0 · sampleBuffer
        日期：\(Date().ISO8601Format())
        系统：\(UIDevice.current.systemVersion)
        状态：\(player.state)；暂停：\(player.isPaused)
        进度：\(player.position.seconds) / \(player.duration.seconds) 秒
        解码会话：\(d.decoder.session)
        VideoToolbox 实际硬件状态：\(String(describing: d.decoder.videoToolboxSessionUsesHardware))
        编码：\(d.decoder.codec ?? "未知")；像素格式：\(d.decoder.decodedPixelFormat ?? "未知")
        解码掉帧：\(String(describing: d.decoderDroppedFrames))
        输出掉帧：\(String(describing: d.outputDroppedFrames))
        缓冲中：\(b.isBuffering)
        前向缓存秒数：\(String(describing: b.secondsBufferedAhead))
        音画偏移秒数：\(String(describing: d.audioVideoDriftSeconds))
        系统热状态：\(ProcessInfo.processInfo.thermalState)
        低电量模式：\(ProcessInfo.processInfo.isLowPowerModeEnabled)
        这是单次状态记录；nil 为未获取，不能解释为零。
        此记录不测量机身温度、总功耗，也不证明长时间无卡顿。
        """
    }
}

struct ProbeView: View {
    @State private var model = ProbeModel()
    @State private var importFile = false
    @State private var enterURL = false
    @State private var address = ""
    @State private var report = ""
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("影院 · 原生播放验证").font(.headline)
                Text("独立测试包，不替换现有影院 App").font(.caption).foregroundStyle(.secondary)
                ZStack {
                    MPVVideoPlayer(player: model.player)
                    ProbeGestures(player: model.player) { model.preview = $0 }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                Text(model.title).font(.caption).lineLimit(2)
                HStack {
                    Button("导入本地影片") { importFile = true }
                    Button("打开媒体地址") { enterURL = true }
                }.buttonStyle(.bordered)
                HStack {
                    Button("4K HEVC 8-bit") { openFixture("hevc8") }
                    Button("4K HEVC 10-bit") { openFixture("hevc10") }
                }.font(.caption).buttonStyle(.bordered)
                HStack(spacing: 24) {
                    Button { model.player.seek(by: .seconds(-15)) } label: { Image(systemName: "gobackward.15") }
                    Button { model.player.togglePlayback() } label: {
                        Image(systemName: model.player.isPaused ? "play.fill" : "pause.fill")
                    }.accessibilityIdentifier("playPause")
                    Button { model.player.seek(by: .seconds(15)) } label: { Image(systemName: "goforward.15") }
                    Button("停止") { model.stop() }
                }.font(.title2)
                Slider(
                    value: Binding(get: { model.preview ?? model.player.position.seconds }, set: { model.preview = $0 }),
                    in: 0...max(1, model.player.duration.seconds),
                    onEditingChanged: { editing in
                        if !editing, let target = model.preview {
                            model.player.seek(to: .seconds(target))
                            model.preview = nil
                        }
                    }
                ).disabled(!model.player.isSeekable)
                Text(String(format: "%.1f / %.1f 秒", model.preview ?? model.player.position.seconds, model.player.duration.seconds))
                    .font(.caption.monospacedDigit())
                if let failure = model.error ?? model.player.lastError.map({ String(describing: $0) }) {
                    Text(failure).font(.caption).foregroundStyle(.red)
                }
                Text("单指双击暂停/播放；左右拖动进度；左侧上下调亮度，右侧上下调音量。内置短片仅验证格式和操作；发热复测请导入完整影片。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("记录当前状态") { report = model.snapshot() }
                    ShareLink("分享记录", item: report).disabled(report.isEmpty)
                }.buttonStyle(.bordered)
                if !report.isEmpty { Text(report).font(.caption.monospaced()).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                Text("MPVUI：MIT 封装，默认原生库含 GPL。测试源码和依赖信息随包提供。")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding()
        }
        .preferredColorScheme(.dark)
        .fileImporter(isPresented: $importFile, allowedContentTypes: [.movie, .video, .data]) { result in
            switch result {
            case .success(let url): model.open(url, scoped: true)
            case .failure(let error): model.error = error.localizedDescription
            }
        }
        .alert("输入可直接访问的媒体 URL", isPresented: $enterURL) {
            TextField("http://局域网地址/影片.mkv", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("播放") {
                guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
                      ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
                      url.user == nil, url.password == nil else { model.error = "请输入有效的 HTTP 或 HTTPS 媒体地址。"; return }
                model.open(url)
            }
            Button("取消", role: .cancel) {}
        } message: { Text("这是媒体文件地址，不是影片详情页或夸克分享链接。需要账号鉴权的来源尚未接入本测试包。") }
        .onChange(of: scenePhase) { _, phase in
            UIApplication.shared.isIdleTimerDisabled = phase == .active && !model.player.isPaused
            if phase == .background { model.player.pause() }
        }
        .onChange(of: model.player.isPaused) { _, paused in UIApplication.shared.isIdleTimerDisabled = !paused }
        .onDisappear { model.stop(); UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func openFixture(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mkv") else {
            model.error = "未找到内置样片。"
            return
        }
        model.open(url)
    }
}

struct ProbeGestures: UIViewRepresentable {
    let player: MPVPlayer
    let preview: (Double?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(player: player, preview: preview) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap))
        tap.numberOfTapsRequired = 2
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(pan)
        let volume = context.coordinator.volume
        volume.frame = CGRect(x: -100, y: -100, width: 1, height: 1)
        view.addSubview(volume)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject {
        let player: MPVPlayer
        let preview: (Double?) -> Void
        let volume = MPVolumeView()
        private var horizontal = false
        private var left = false
        private var start = 0.0
        private var target: Double?
        init(player: MPVPlayer, preview: @escaping (Double?) -> Void) { self.player = player; self.preview = preview }
        @objc func doubleTap() { player.togglePlayback() }
        @objc func pan(_ sender: UIPanGestureRecognizer) {
            guard let view = sender.view, let screen = view.window?.windowScene?.screen else { return }
            let translation = sender.translation(in: view)
            if sender.state == .began {
                let velocity = sender.velocity(in: view)
                horizontal = abs(velocity.x) >= abs(velocity.y)
                left = sender.location(in: view).x < view.bounds.midX
                start = horizontal ? player.position.seconds : left ? Double(screen.brightness) : Double(AVAudioSession.sharedInstance().outputVolume)
                target = nil
            }
            if sender.state == .cancelled || sender.state == .failed { target = nil; preview(nil); return }
            if sender.state == .ended {
                if horizontal, let target, player.isSeekable { player.seek(to: .seconds(target)) }
                target = nil
                preview(nil)
                return
            }
            if horizontal {
                guard player.isSeekable else { return }
                target = min(player.duration.seconds, max(0, start + Double(translation.x / max(1, view.bounds.width)) * player.duration.seconds))
                preview(target)
            } else {
                let value = min(1, max(0, start - Double(translation.y / 250)))
                if left { screen.brightness = value }
                else if let slider = volume.subviews.first(where: { $0 is UISlider }) as? UISlider {
                    slider.setValue(Float(value), animated: false)
                    slider.sendActions(for: .valueChanged)
                }
            }
        }
    }
}
