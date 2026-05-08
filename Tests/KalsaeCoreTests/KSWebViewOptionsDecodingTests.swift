import Foundation
import Testing

@testable import KalsaeCore

@Suite("KSWebViewOptions decoding")
struct KSWebViewOptionsDecodingTests {

    private func decode(_ json: String) throws -> KSWebViewOptions {
        try JSONDecoder().decode(KSWebViewOptions.self, from: Data(json.utf8))
    }

    @Test("legacy flat fields still decode (backward compat)")
    func legacyFlat() throws {
        let opts = try decode(#"""
            {
              "transparent": true,
              "backdropType": "mica",
              "disablePinchZoom": true,
              "zoomFactor": 1.25,
              "userDataPath": "C:\\\\Users\\\\me\\\\WebView2"
            }
            """#)
        #expect(opts.transparent == true)
        #expect(opts.backdropType == .mica)
        #expect(opts.disablePinchZoom == true)
        #expect(opts.zoomFactor == 1.25)
        #expect(opts.userDataPath?.contains("WebView2") == true)
        #expect(opts.preferences == nil)
        #expect(opts.platform == nil)
    }

    @Test("missing webview block: all defaults")
    func defaults() throws {
        let opts = try decode("{}")
        #expect(opts.transparent == false)
        #expect(opts.disablePinchZoom == false)
        #expect(opts.zoomFactor == nil)
        #expect(opts.preferences == nil)
        #expect(opts.platform == nil)
    }

    @Test("preferences block decodes")
    func preferences() throws {
        let opts = try decode(#"""
            {
              "preferences": {
                "javaScriptEnabled": true,
                "developerExtrasEnabled": false,
                "hardwareAcceleration": "always",
                "smoothScrolling": true,
                "swipeNavigation": false,
                "autofill": false,
                "fraudulentWebsiteWarning": true,
                "language": "ko-KR",
                "mediaAutoplay": "userGesture",
                "allowsInlineMediaPlayback": true
              }
            }
            """#)
        let p = try #require(opts.preferences)
        #expect(p.javaScriptEnabled == true)
        #expect(p.developerExtrasEnabled == false)
        #expect(p.hardwareAcceleration == .always)
        #expect(p.smoothScrolling == true)
        #expect(p.swipeNavigation == false)
        #expect(p.autofill == false)
        #expect(p.fraudulentWebsiteWarning == true)
        #expect(p.language == "ko-KR")
        #expect(p.mediaAutoplay == .userGesture)
        #expect(p.allowsInlineMediaPlayback == true)
    }

    @Test("platform.windows decodes")
    func platformWindows() throws {
        let opts = try decode(#"""
            {
              "platform": {
                "windows": {
                  "additionalBrowserArguments": "--js-flags=--max-old-space-size=128",
                  "language": "en-US",
                  "targetCompatibleBrowserVersion": "120.0.0.0",
                  "allowSingleSignOn": true,
                  "exclusiveUserDataFolderAccess": false,
                  "trackingPrevention": "balanced"
                }
              }
            }
            """#)
        let w = try #require(opts.platform?.windows)
        #expect(w.additionalBrowserArguments?.contains("max-old-space-size") == true)
        #expect(w.language == "en-US")
        #expect(w.targetCompatibleBrowserVersion == "120.0.0.0")
        #expect(w.allowSingleSignOn == true)
        #expect(w.exclusiveUserDataFolderAccess == false)
        #expect(w.trackingPrevention == .balanced)
    }

    @Test("platform.mac decodes")
    func platformMac() throws {
        let opts = try decode(#"""
            {
              "platform": {
                "mac": {
                  "limitNavigationsToAppBoundDomains": true,
                  "suppressIncrementalRendering": true,
                  "preferredContentMode": "desktop",
                  "shareProcessPool": true
                }
              }
            }
            """#)
        let m = try #require(opts.platform?.mac)
        #expect(m.limitNavigationsToAppBoundDomains == true)
        #expect(m.suppressIncrementalRendering == true)
        #expect(m.preferredContentMode == .desktop)
        #expect(m.shareProcessPool == true)
    }

    @Test("platform.linux decodes")
    func platformLinux() throws {
        let opts = try decode(#"""
            {
              "platform": {
                "linux": {
                  "enableWebgl": true,
                  "enableWebaudio": false,
                  "defaultFontFamily": "Inter",
                  "defaultFontSize": 14
                }
              }
            }
            """#)
        let l = try #require(opts.platform?.linux)
        #expect(l.enableWebgl == true)
        #expect(l.enableWebaudio == false)
        #expect(l.defaultFontFamily == "Inter")
        #expect(l.defaultFontSize == 14)
    }

    @Test("invalid enum value fails")
    func invalidEnum() {
        do {
            _ = try decode(#"{ "preferences": { "mediaAutoplay": "rocket" } }"#)
            Issue.record("expected decoding failure")
        } catch {
            // 디코딩 실패 자체가 검증.
        }
    }
}
