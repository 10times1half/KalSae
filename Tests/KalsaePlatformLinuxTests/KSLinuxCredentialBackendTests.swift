#if os(Linux)
    import Testing
    import Foundation
    @testable import KalsaePlatformLinux
    import KalsaeCore

    /// KSLinuxCredentialBackend 통합 계약 테스트.
    ///
    /// 헤드리스 CI / D-Bus 없는 환경에서는 Secret Service가 없을 수 있다.
    /// 그 경우 `.unsupportedPlatform`을 받고 skip한다 (test failure 아님).
    /// 실제 keyring이 있는 환경(개발 머신/세션 있는 데스크탑)에서는 라운드트립을
    /// 검증한다.
    @Suite("KSLinuxCredentialBackend — Secret Service contract")
    struct KSLinuxCredentialBackendTests {

        // 테스트 격리: 매 실행 고유 service 사용 → 잔존물 충돌 방지.
        private static func uniqueService() -> String {
            "dev.kalsae.tests.\(UUID().uuidString)"
        }

        @Test("set → get → delete round-trip")
        func roundTrip() async {
            let backend = KSLinuxCredentialBackend()
            let key = KSCredentialKey(service: Self.uniqueService(), account: "user@example.com")
            let secret = Data("p@ssw0rd!".utf8)

            do {
                try await backend.set(key, secret: secret)
            } catch let error {
                if error.code == .unsupportedPlatform {
                    return  // Secret Service unavailable on this host → skip
                }
                Issue.record("Unexpected set error: \(error)")
                return
            }

            do {
                let got = try await backend.get(key)
                #expect(got == secret, "Round-trip value mismatch")
            } catch let error {
                Issue.record("Unexpected get error: \(error)")
            }

            do {
                try await backend.delete(key)
                let afterDelete = try await backend.get(key)
                #expect(afterDelete == nil, "Value should be nil after delete")
            } catch let error {
                Issue.record("Unexpected delete error: \(error)")
            }
        }

        @Test("get returns nil for missing key")
        func getMissing() async {
            let backend = KSLinuxCredentialBackend()
            let key = KSCredentialKey(
                service: Self.uniqueService(), account: "missing")

            do {
                let got = try await backend.get(key)
                #expect(got == nil, "Missing key should return nil")
            } catch let error {
                if error.code == .unsupportedPlatform { return }
                Issue.record("Unexpected error: \(error)")
            }
        }

        @Test("delete on missing key is noop")
        func deleteMissing() async {
            let backend = KSLinuxCredentialBackend()
            let key = KSCredentialKey(
                service: Self.uniqueService(), account: "missing")

            do {
                try await backend.delete(key)  // 매칭 없음 → 조용히 통과
            } catch let error {
                if error.code == .unsupportedPlatform { return }
                Issue.record("Unexpected error on missing delete: \(error)")
            }
        }

        @Test("list returns keys filtered by service")
        func listFiltering() async {
            let backend = KSLinuxCredentialBackend()
            let service = Self.uniqueService()
            let k1 = KSCredentialKey(service: service, account: "a")
            let k2 = KSCredentialKey(service: service, account: "b")
            let secret = Data([0x01, 0x02, 0x03])

            do {
                try await backend.set(k1, secret: secret)
                try await backend.set(k2, secret: secret)
            } catch let error {
                if error.code == .unsupportedPlatform { return }
                Issue.record("Unexpected set error: \(error)")
                return
            }
            defer {
                Task {
                    try? await backend.delete(k1)
                    try? await backend.delete(k2)
                }
            }

            do {
                let listed = try await backend.list(service: service)
                let accounts = Set(listed.map(\.account))
                #expect(accounts.contains("a"))
                #expect(accounts.contains("b"))
                for key in listed {
                    #expect(
                        key.service == service,
                        "list result must match requested service")
                }
            } catch let error {
                Issue.record("Unexpected list error: \(error)")
            }
        }
    }
#endif
