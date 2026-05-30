#if os(Android)
    import Testing
    import Foundation
    @testable import KalsaePlatformAndroid
    import KalsaeCore

    @Suite("KSAndroidCredentialBackend")
    struct KSAndroidCredentialBackendTests {

        @Test("missing hooks -> unsupportedPlatform")
        func missingHooksUnsupported() async {
            _hooksLock.withLock {
                _jniCredentialSet = nil
                _jniCredentialGet = nil
                _jniCredentialDelete = nil
                _jniCredentialList = nil
            }

            let backend = KSAndroidCredentialBackend()
            let key = KSCredentialKey(service: "svc", account: "acct")

            do {
                try await backend.set(key, secret: Data("x".utf8))
                Issue.record("Expected unsupportedPlatform")
            } catch let error {
                #expect(error.code == .unsupportedPlatform)
            }
        }

        @Test("set/get/delete/list round-trip through JNI callbacks")
        func roundTripWithHooks() async throws {
            _hooksLock.withLock {
                _jniCredentialSet = testCredentialSet
                _jniCredentialGet = testCredentialGet
                _jniCredentialDelete = testCredentialDelete
                _jniCredentialList = testCredentialList
            }
            defer {
                _hooksLock.withLock {
                    _jniCredentialSet = nil
                    _jniCredentialGet = nil
                    _jniCredentialDelete = nil
                    _jniCredentialList = nil
                }
            }

            let backend = KSAndroidCredentialBackend()
            let key = KSCredentialKey(service: "svc", account: "john")

            try await backend.set(key, secret: Data("hello".utf8))

            let got = try await backend.get(key)
            #expect(got == Data("hello".utf8))

            let keys = try await backend.list(service: "svc")
            #expect(keys.map(\.account) == ["alice", "bob"])

            try await backend.delete(key)
        }
    }

    private func sendCredentialResult(_ requestId: Int32, _ json: String) {
        json.withCString { cstr in
            KS_android_on_credential_result(requestId, cstr)
        }
    }

    private func testCredentialSet(_ requestId: Int32, _ requestJSON: UnsafePointer<CChar>) {
        _ = String(cString: requestJSON)
        sendCredentialResult(requestId, "{\"ok\":true}")
    }

    private func testCredentialGet(_ requestId: Int32, _ requestJSON: UnsafePointer<CChar>) {
        let request = String(cString: requestJSON)
        if request.contains("\"account\":\"missing\"") {
            sendCredentialResult(
                requestId,
                "{\"ok\":true,\"payload\":{\"secretBase64\":null}}")
            return
        }

        sendCredentialResult(
            requestId,
            "{\"ok\":true,\"payload\":{\"secretBase64\":\"aGVsbG8=\"}}")
    }

    private func testCredentialDelete(_ requestId: Int32, _ requestJSON: UnsafePointer<CChar>) {
        _ = String(cString: requestJSON)
        sendCredentialResult(requestId, "{\"ok\":true}")
    }

    private func testCredentialList(_ requestId: Int32, _ requestJSON: UnsafePointer<CChar>) {
        _ = String(cString: requestJSON)
        sendCredentialResult(
            requestId,
            "{\"ok\":true,\"payload\":{\"accounts\":[\"alice\",\"bob\"]}}")
    }
#endif
