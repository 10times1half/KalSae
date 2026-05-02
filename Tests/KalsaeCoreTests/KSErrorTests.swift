import Foundation
import Testing

@testable import KalsaeCore

@Suite("KSError")
struct KSErrorTests {
    @Test("Round-trips through JSON")
    func roundTrip() throws {
        let original = KSError(
            code: .commandNotAllowed,
            message: "nope",
            data: .dict(["name": .string("fs.read"), "attempts": .int(3)]))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KSError.self, from: data)
        #expect(decoded == original)
    }

    @Test("Payload encodes as raw JSON values")
    func payloadShape() throws {
        let err = KSError(
            code: .ioFailed, message: "oops",
            data: .array([.int(1), .string("x")]))
        let data = try JSONEncoder().encode(err)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = obj?["data"] as? [Any]
        #expect(payload?.count == 2)
        #expect(payload?[0] as? Int == 1)
        #expect(payload?[1] as? String == "x")
    }

    @Test("sourceLocation captured by convenience constructors")
    func sourceLocationCaptured() {
        let err = KSError.internal("boom")
        #expect(err.sourceLocation != nil)
        #expect(err.sourceLocation?.line ?? 0 > 0)
        #expect(err.sourceLocation?.function.contains("sourceLocationCaptured") == true)
    }

    @Test("sourceLocation is excluded from wire JSON")
    func sourceLocationStrippedOnEncode() throws {
        let err = KSError.internal("trace-me")
        let data = try JSONEncoder().encode(err)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["sourceLocation"] == nil)
        #expect(obj?["file"] == nil)
        // 원래대로 직렬화/역직렬화해도 sourceLocation은 돈다, code/message/data는 보존된다.
        let decoded = try JSONDecoder().decode(KSError.self, from: data)
        #expect(decoded.code == err.code)
        #expect(decoded.message == err.message)
        #expect(decoded.sourceLocation == nil)
    }

    @Test("clipboardDecodeFailed has correct code and payload")
    func clipboardDecodeFailedShape() {
        let err = KSError.clipboardDecodeFailed("invalid PNG")
        #expect(err.code == .clipboardDecodeFailed)
        #expect(err.message.contains("invalid PNG"))
        #expect(err.sourceLocation != nil)
    }

    @Test("shellInvocationFailed encodes structured payload")
    func shellInvocationFailedShape() throws {
        let err = KSError.shellInvocationFailed(
            command: "compress", exitCode: 7, stderr: "oh no")
        #expect(err.code == .shellInvocationFailed)
        if case .dict(let d) = err.data {
            #expect(d["command"] == .string("compress"))
            #expect(d["exitCode"] == .int(7))
            #expect(d["stderr"] == .string("oh no"))
        } else {
            Issue.record("expected dict payload")
        }
    }

    @Test("Payload decode rejects unsupported types with diagnostic")
    func payloadUnknownInputRejected() {
        // Boolean is not a supported Payload variant.
        let bogus = #"{"code":"internal","message":"x","data":true}"#
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                KSError.self, from: Data(bogus.utf8))
        }
    }
}
