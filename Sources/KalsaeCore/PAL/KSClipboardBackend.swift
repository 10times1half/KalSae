public import Foundation

/// 시스템 클립보드 읽기/쓰기.
///
/// 이 프로토콜은 의도적으로 최소화되어 있다 — 일반 텍스트와 원시
/// 이미지 바이트를 넘는 형식은 이후 단계에서 추가된다. 메서드는
/// async이므로 구현이 UI 스레드로 홉할 수 있다(Win32의 `OpenClipboard`,
/// AppKit의 `NSPasteboard`, GDK의 `gdk_clipboard_*`).
public protocol KSClipboardBackend: Sendable {
    /// UTF-8 일반 텍스트를 읽는다. 클립보드가 비어 있거나 알 수 없는
    /// 비텍스트 형식인 경우 `nil`을 반환한다.
    func readText() async throws(KSError) -> String?

    /// 클립보드 내용을 `text`로 교체한다.
    func writeText(_ text: String) async throws(KSError)

    /// 클립보드를 원시 PNG 바이트로 읽는다. 클립보드가 이미지를 보유하지
    /// 않으면 `nil`을 반환한다.
    func readImage() async throws(KSError) -> Data?

    /// 클립보드 내용을 `image`(PNG 인코딩)로 교체한다.
    func writeImage(_ image: Data) async throws(KSError)

    /// 모든 클립보드 형식을 지운다.
    func clear() async throws(KSError)

    /// 주어진 형식 중 하나 이상이 존재하면 `true`를 반환한다.
    /// 형식 이름은 플랫폼 중립 집합을 따른다: `"text"`, `"image"`,
    /// `"files"`. 알 수 없는 형식은 `false`를 반환한다.
    func hasFormat(_ format: String) async -> Bool
}

extension KSClipboardBackend {
    @inline(__always)
    private func _unsupportedThrow(_ op: String) throws(KSError) -> Never {
        throw KSError(code: .unsupportedPlatform,
                      message: "KSClipboardBackend.\(op) is not implemented on this platform.")
    }

    public func readText() async throws(KSError) -> String? { try _unsupportedThrow("readText") }
    public func writeText(_ text: String) async throws(KSError) { try _unsupportedThrow("writeText") }
    public func readImage() async throws(KSError) -> Data? { try _unsupportedThrow("readImage") }
    public func writeImage(_ image: Data) async throws(KSError) { try _unsupportedThrow("writeImage") }
    public func clear() async throws(KSError) { try _unsupportedThrow("clear") }
    public func hasFormat(_ format: String) async -> Bool { false }
}
