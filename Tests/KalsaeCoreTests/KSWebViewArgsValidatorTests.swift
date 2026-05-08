import Foundation
import Testing

@testable import KalsaeCore

@Suite("KSWebViewArgsValidator")
struct KSWebViewArgsValidatorTests {

    @Test("benign arguments pass through")
    func benignAccepted() throws {
        let tokens = try KSWebViewArgsValidator.validate(
            "--js-flags=--max-old-space-size=128 --enable-features=WebUI")
        #expect(tokens.count == 2)
        #expect(tokens[0] == "--js-flags=--max-old-space-size=128")
        #expect(tokens[1] == "--enable-features=WebUI")
    }

    @Test("empty input returns empty tokens")
    func emptyInput() throws {
        let tokens = try KSWebViewArgsValidator.validate("")
        #expect(tokens.isEmpty)
    }

    @Test("quotes preserve spaces")
    func quotedTokens() throws {
        let tokens = try KSWebViewArgsValidator.validate(
            #"--user-agent="Kalsae 1.0 demo""#)
        #expect(tokens.count == 1)
        #expect(tokens[0] == "--user-agent=Kalsae 1.0 demo")
    }

    @Test(
        "blocked prefixes reject",
        arguments: [
            "--remote-debugging-port=9222",
            "--remote-debugging-pipe",
            "--remote-allow-origins=*",
            "--disable-web-security",
            "--no-sandbox",
            "--disable-site-isolation-trials",
            "--allow-running-insecure-content",
            "--user-data-dir=C:\\evil",
            "--unsafely-treat-insecure-origin-as-secure=http://evil",
        ])
    func blockedTokens(arg: String) {
        do {
            _ = try KSWebViewArgsValidator.validate(arg)
            Issue.record("expected validation failure for \(arg)")
        } catch {
            #expect(!error.matchedPrefix.isEmpty)
        }
    }

    @Test("case-insensitive matching")
    func caseInsensitive() {
        do {
            _ = try KSWebViewArgsValidator.validate("--NO-SANDBOX")
            Issue.record("expected rejection")
        } catch {
            #expect(error.matchedPrefix == "--no-sandbox")
        }
    }

    @Test("autoplay synth: never policy maps to required user-activation")
    func autoplayNever() {
        let arg = KSWebViewArgsValidator.autoplayPolicyArgument(for: .never)
        #expect(arg == "--autoplay-policy=document-user-activation-required")
    }

    @Test("compose: empty user args + media autoplay yields synth only")
    func composeAutoplayOnly() throws {
        let composed = try KSWebViewArgsValidator.compose(
            userArguments: nil, mediaAutoplay: .always)
        #expect(composed == "--autoplay-policy=no-user-gesture-required")
    }

    @Test("compose: user-supplied autoplay-policy wins (no synth duplication)")
    func composeUserOverridesSynth() throws {
        let composed = try KSWebViewArgsValidator.compose(
            userArguments: "--autoplay-policy=user-gesture-required --foo=bar",
            mediaAutoplay: .always)
        // 사용자 인자가 그대로 유지되어야 한다.
        #expect(composed.contains("--autoplay-policy=user-gesture-required"))
        #expect(!composed.contains("no-user-gesture-required"))
    }

    @Test("compose: blocked user args rejected even with synth")
    func composeBlockedRejected() {
        do {
            _ = try KSWebViewArgsValidator.compose(
                userArguments: "--no-sandbox", mediaAutoplay: .never)
            Issue.record("expected rejection")
        } catch {
            #expect(error.matchedPrefix == "--no-sandbox")
        }
    }
}
