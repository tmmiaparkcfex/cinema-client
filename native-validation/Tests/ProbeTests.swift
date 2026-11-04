import MPVUI
import SwiftUI
import UIKit
import XCTest

@MainActor
final class ProbeTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "mkv"))
    }

    private func eventually(_ message: @autoclosure () -> String, seconds: Double = 30, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > deadline {
                XCTFail(message())
                throw NSError(domain: "ProbeTestTimeout", code: 1, userInfo: [NSLocalizedDescriptionKey: message()])
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func withPlayer(_ body: (MPVPlayer) async throws -> Void) async throws {
        let player = MPVPlayer(configuration: .init(autoPlay: false))
        player.setDiagnosticsEnabled(true)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first {
            $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
        })
        let previous = scene.windows.first { $0.isKeyWindow }
        let surface = MPVPlatformVideoPlayer(player: player)
        let controller = UIViewController()
        controller.view = surface
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 220)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        surface.setNeedsLayout()
        surface.layoutIfNeeded()
        surface.activateRenderingSurface()
        defer {
            player.stop()
            surface.detach()
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
        try await body(player)
    }

    private func load(_ name: String, player: MPVPlayer) async throws {
        player.load(try fixture(name), autoPlay: false, startTime: .seconds(1))
        try await eventually("\(name): state=\(player.state), frame=\(player.hasVideoFrame), seekable=\(player.isSeekable), duration=\(player.duration.probeSeconds), error=\(String(describing: player.lastError))") {
            player.hasVideoFrame && player.isSeekable && player.duration.probeSeconds > 10
        }
        XCTAssertNil(player.lastError)
        XCTAssertEqual(player.mediaInformation.dimensions?.effectiveWidth, 3840)
        XCTAssertEqual(player.mediaInformation.dimensions?.effectiveHeight, 1632)
        XCTAssertEqual(player.videoOutput, .sampleBuffer)
    }

    func test4KHEVCMain8BitMKVFirstFrameAndSeek() async throws {
        try await withPlayer { player in
            try await load("hevc8", player: player)
            player.seek(to: .seconds(6))
            try await eventually("8-bit seek did not complete") { abs(player.position.probeSeconds - 6) < 0.3 && player.isPaused }
        }
    }

    func test4KHEVCMain10BitMKVFirstFrameAndSeek() async throws {
        try await withPlayer { player in
            try await load("hevc10", player: player)
            player.seek(to: .seconds(6))
            try await eventually("10-bit seek did not complete") { abs(player.position.probeSeconds - 6) < 0.3 && player.isPaused }
        }
    }

    func testPauseAndResumeAdvanceNativePlayback() async throws {
        try await withPlayer { player in
            try await load("hevc8", player: player)
            let initial = player.position.probeSeconds
            player.play()
            try await eventually("play did not advance") { player.position.probeSeconds > initial + 0.5 && !player.isPaused }
            player.pause()
            try await eventually("pause did not take effect") { player.isPaused }
            let paused = player.position.probeSeconds
            try await Task.sleep(for: .milliseconds(500))
            XCTAssertLessThan(abs(player.position.probeSeconds - paused), 0.2)
            player.play()
            try await eventually("resume did not advance") { player.position.probeSeconds > paused + 0.4 }
        }
    }

    func testRepeatedForwardBackwardSeekKeepsPausedState() async throws {
        try await withPlayer { player in
            try await load("hevc10", player: player)
            for target in [6.0, 2.0, 9.0, 1.0, 7.0, 3.0] {
                player.seek(to: .seconds(target))
                try await eventually("repeated seek failed at \(target)") { abs(player.position.probeSeconds - target) < 0.3 && player.isPaused }
                XCTAssertNil(player.lastError)
            }
        }
    }

    func testSwitchSourceResetsTimelineAndCanResume() async throws {
        try await withPlayer { player in
            try await load("hevc8", player: player)
            player.seek(to: .seconds(8))
            try await eventually("initial seek failed") { abs(player.position.probeSeconds - 8) < 0.3 }
            player.stop()
            try await load("hevc10", player: player)
            try await eventually("source switch retained old position") { abs(player.position.probeSeconds - 1) < 0.2 && player.isPaused }
            player.play()
            try await eventually("new source did not advance") { player.position.probeSeconds > 1.4 }
        }
    }

    func testMissingFileReportsError() async throws {
        try await withPlayer { player in
            player.load(URL(fileURLWithPath: "/missing-probe-file.mkv"), autoPlay: false)
            try await eventually("missing media remained stuck without an error", seconds: 15) { player.lastError != nil }
        }
    }
}
