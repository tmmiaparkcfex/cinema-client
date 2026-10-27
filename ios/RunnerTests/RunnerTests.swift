import Foundation
import Flutter
import UIKit
import WebKit
import XCTest
import flutter_inappwebview_ios

class RunnerTests: XCTestCase {

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
    wait(for: [stored], timeout: 15)

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
