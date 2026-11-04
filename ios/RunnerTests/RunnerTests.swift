import Foundation
import Darwin
import Flutter
import UIKit
import WebKit
import XCTest
import flutter_inappwebview_ios

class RunnerTests: XCTestCase {

  // Exercise the bundled iOS libmpv, not a mocked Dart property map. This
  // checks native option compatibility; it does not measure device heat/4K.
  @MainActor func testNativePlaybackCacheProperties() throws {
    let framework = try XCTUnwrap(Bundle.main.privateFrameworksPath)
    let library = try XCTUnwrap(dlopen("\(framework)/Mpv.framework/Mpv", RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    func symbol<T>(_ name: String, _ type: T.Type) throws -> T {
      let address = try XCTUnwrap(dlsym(library, name), "Missing libmpv symbol: \(name)")
      return unsafeBitCast(address, to: type)
    }
    typealias Create = @convention(c) () -> OpaquePointer?
    typealias SetString = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32
    typealias Initialize = @convention(c) (OpaquePointer?) -> Int32
    typealias GetString = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    typealias Destroy = @convention(c) (OpaquePointer?) -> Void
    typealias Free = @convention(c) (UnsafeMutableRawPointer?) -> Void
    let create = try symbol("mpv_create", Create.self)
    let setOption = try symbol("mpv_set_option_string", SetString.self)
    let initialize = try symbol("mpv_initialize", Initialize.self)
    let setProperty = try symbol("mpv_set_property_string", SetString.self)
    let getProperty = try symbol("mpv_get_property_string", GetString.self)
    let destroy = try symbol("mpv_terminate_destroy", Destroy.self)
    let free = try symbol("mpv_free", Free.self)
    let player = try XCTUnwrap(create())
    defer { destroy(player) }
    for (name, value) in ["vo": "null", "ao": "null", "config": "no", "terminal": "no"] {
      XCTAssertEqual(setOption(player, name, value), 0, "Option: \(name)")
    }
    XCTAssertEqual(initialize(player), 0)
    let properties = [
      "cache": "yes", "cache-on-disk": "no", "demuxer-max-bytes": "67108864",
      "demuxer-max-back-bytes": "16777216", "cache-secs": "30",
      "cache-pause": "yes", "cache-pause-initial": "yes", "cache-pause-wait": "3",
      "network-timeout": "40"
    ]
    for (name, expected) in properties {
      XCTAssertEqual(setProperty(player, name, expected), 0, "Property: \(name)")
      let raw = try XCTUnwrap(getProperty(player, name), "Read property: \(name)")
      let actual = String(cString: raw)
      free(UnsafeMutableRawPointer(raw))
      if let number = Double(expected) {
        XCTAssertEqual(try XCTUnwrap(Double(actual)), number, accuracy: 0.001, "Property: \(name)")
      } else {
        XCTAssertEqual(actual, expected, "Property: \(name)")
      }
    }
  }

  @MainActor func testHttpOnlyCookieBridgeAcrossQuarkHosts() throws {
    let url = try XCTUnwrap(URL(string: "https://pan.quark.cn/"))
    let name = "cinema_cookie_bridge_fixture"
    let cookies = HTTPCookie.cookies(
      withResponseHeaderFields: [
        "Set-Cookie": "\(name)=synthetic-session; Domain=.quark.cn; Path=/; Secure; HttpOnly; SameSite=Lax"
      ], for: url)
    let cookie = try XCTUnwrap(cookies.first)
    XCTAssertTrue(cookie.isHTTPOnly)
    let store = WKWebsiteDataStore.default().httpCookieStore
    let stored = expectation(description: "Fixture stored in WK cookie store")
    store.setCookie(cookie) { stored.fulfill() }
    // A cold hosted simulator can take >15s just to launch WebKit's network
    // process. Keep the fixture and plugin assertions, allow that startup time.
    wait(for: [stored], timeout: 60)

    let captured = expectation(description: "Plugin reads HttpOnly cookie on both hosts")
    captured.expectedFulfillmentCount = 2
    for host in ["https://pan.quark.cn/", "https://drive-pc.quark.cn/"] {
      MyCookieManager.getCookies(url: host) { result in
        let rows = result as? [[String: Any?]]
        let found = rows?.first { (($0["name"] ?? nil) as? String) == name }
        XCTAssertEqual((found?["value"] ?? nil) as? String, "synthetic-session")
        XCTAssertEqual((found?["isHttpOnly"] ?? nil) as? Bool, true)
        captured.fulfill()
      }
    }
    wait(for: [captured], timeout: 15)
    let removed = expectation(description: "Only the fixture cookie is removed")
    store.delete(cookie) { removed.fulfill() }
    wait(for: [removed], timeout: 15)
  }

}

