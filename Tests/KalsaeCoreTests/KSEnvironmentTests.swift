import Foundation
import Testing

@testable import KalsaeCore

@Suite("KSEnvironment")
struct KSEnvironmentTests {

    // MARK: - 1. JSON 인코딩 시 새 필드 모두 존재

    @Test("Environment JSON에 os, arch, platform, kalsaeVersion 필드가 존재한다")
    func jsonContainsCoreFields() throws {
        let env = KSBuiltinCommands.Environment(
            os: "windows",
            arch: "x86_64",
            platform: "Windows (Win32 + WebView2)",
            osVersion: "10.0.22631",
            locale: "ko-KR",
            appVersion: "1.0.0",
            kalsaeVersion: KSVersion.current)

        let data = try JSONEncoder().encode(env)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["os"] as? String == "windows")
        #expect(json?["arch"] as? String == "x86_64")
        #expect(json?["platform"] as? String == "Windows (Win32 + WebView2)")
        #expect(json?["kalsaeVersion"] as? String == KSVersion.current)
    }

    @Test("Environment JSON에 osVersion, locale 필드가 존재한다")
    func jsonContainsNewFields() throws {
        let env = KSBuiltinCommands.Environment(
            os: "windows",
            arch: "x86_64",
            platform: "Windows (Win32 + WebView2)",
            osVersion: "10.0.22631",
            locale: "ko-KR",
            appVersion: nil,
            kalsaeVersion: KSVersion.current)

        let data = try JSONEncoder().encode(env)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["osVersion"] as? String == "10.0.22631")
        #expect(json?["locale"] as? String == "ko-KR")
    }

    // MARK: - 2. Codable round-trip

    @Test("Environment Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = KSBuiltinCommands.Environment(
            os: "macos",
            arch: "arm64",
            platform: "macOS (AppKit + WKWebView)",
            osVersion: "14.4.1",
            locale: "en-US",
            appVersion: "2.1.0",
            kalsaeVersion: "0.3.1")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KSBuiltinCommands.Environment.self, from: data)

        #expect(decoded.os == original.os)
        #expect(decoded.arch == original.arch)
        #expect(decoded.platform == original.platform)
        #expect(decoded.osVersion == original.osVersion)
        #expect(decoded.locale == original.locale)
        #expect(decoded.appVersion == original.appVersion)
        #expect(decoded.kalsaeVersion == original.kalsaeVersion)
    }

    // MARK: - 3. 런타임 헬퍼 검증

    @Test("kalsaeOSVersionString은 nil이 아닌 버전 문자열을 반환한다")
    func osVersionStringNotNil() {
        let v = kalsaeOSVersionString()
        #expect(v != nil)
        // "Major.Minor.Patch" 형식 — 최소한 하나의 점(.)이 있어야 한다
        #expect(v?.contains(".") == true)
    }

    @Test("kalsaeSystemLocale은 nil이 아닌 비어있지 않은 문자열을 반환한다")
    func localeNotEmpty() {
        let locale = kalsaeSystemLocale()
        #expect(locale != nil)
        #expect(locale?.isEmpty == false)
        // BCP-47 변환: 언더스코어 없이 하이픈 사용
        #expect(locale?.contains("_") == false)
    }

    @Test("kalsaeVersion은 KSVersion.current와 일치한다")
    func kalsaeVersionMatchesCurrent() throws {
        let env = KSBuiltinCommands.Environment(
            os: "test",
            arch: "test",
            platform: "test",
            osVersion: nil,
            locale: nil,
            appVersion: nil,
            kalsaeVersion: KSVersion.current)
        #expect(env.kalsaeVersion == KSVersion.current)
    }

    // MARK: - 4. Windows 한정 (os 필드 값)

    #if os(Windows)
        @Test("Windows에서 kalsaeOSVersionString은 '10.' 또는 '11.' prefix를 포함한다")
        func windowsOSVersionPrefix() {
            let v = kalsaeOSVersionString()
            #expect(v != nil)
            // Windows 10 빌드 = "10.0.x", Windows 11 빌드도 "10.0.x" (내부 버전 동일)
            // 최소 "10." 으로 시작한다
            #expect(v?.hasPrefix("10.") == true)
        }
    #endif
}
