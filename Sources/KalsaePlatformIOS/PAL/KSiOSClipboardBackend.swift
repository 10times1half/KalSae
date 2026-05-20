#if os(iOS)
    internal import UIKit
    public import KalsaeCore
    public import Foundation

    /// iOS 시스템 클립보드(`UIPasteboard`)를 사용하는 `KSClipboardBackend` 구현체입니다.
    ///
    /// iOS에서 `UIPasteboard.general`은 시스템 전역 클립보드로, 모든 앱이
    /// 접근할 수 있습니다. 다만 iOS 14부터는 클립보드 읽기 시 사용자에게
    /// 접근 알림(햅틱 + 배너)이 표시되며, iOS 16부터는 사용자 동의 없이
    /// 자동으로 붙여넣기를 허용하지 않도록 개선되는 등 보안이 강화되고
    /// 있습니다.
    ///
    /// 모든 메서드는 UIKit의 특성상 `MainActor`에서 실행되어야 하므로
    /// `MainActor.run`으로 감싸서 호출합니다.
    public struct KSiOSClipboardBackend: KSClipboardBackend, Sendable {
        public init() {}

        /// 시스템 클립보드에서 텍스트를 읽어 반환합니다.
        /// - Returns: 클립보드의 텍스트 문자열 (비어 있거나 텍스트가 없으면 `nil`)
        /// - Throws: `KSError` — UIKit 접근 오류 시
        public func readText() async throws(KSError) -> String? {
            await MainActor.run {
                UIPasteboard.general.string
            }
        }

        /// 텍스트를 시스템 클립보드에 씁니다.
        /// - Parameter text: 클립보드에 저장할 문자열
        /// - Throws: `KSError` — UIKit 접근 오류 시
        public func writeText(_ text: String) async throws(KSError) {
            await MainActor.run {
                UIPasteboard.general.string = text
            }
        }

        /// 시스템 클립보드에서 이미지를 PNG 데이터로 읽어 반환합니다.
        /// - Returns: PNG 바이너리 데이터 (이미지가 없으면 `nil`)
        /// - Throws: `KSError` — UIKit 접근 오류 시
        public func readImage() async throws(KSError) -> Data? {
            await MainActor.run {
                guard let image = UIPasteboard.general.image else { return nil }
                return image.pngData()
            }
        }

        /// PNG 이미지 데이터를 시스템 클립보드에 씁니다.
        /// 유효한 `UIImage`로 변환할 수 없는 데이터는 조용히 무시됩니다.
        /// - Parameter image: PNG 형식의 이미지 바이너리 데이터
        /// - Throws: `KSError` — UIKit 접근 오류 시
        public func writeImage(_ image: Data) async throws(KSError) {
            await MainActor.run {
                guard let uiImage = UIImage(data: image) else { return }
                UIPasteboard.general.image = uiImage
            }
        }

        /// 시스템 클립보드의 모든 내용을 비웁니다.
        /// - Throws: `KSError` — UIKit 접근 오류 시
        public func clear() async throws(KSError) {
            await MainActor.run {
                UIPasteboard.general.items = []
            }
        }

        /// 클립보드에 특정 형식의 데이터가 있는지 확인합니다.
        /// 지원하는 형식: `"text"`, `"image"`, `"image/png"`
        /// - Parameter format: 확인할 형식 문자열 (대소문자 구분 없음)
        /// - Returns: 해당 형식의 데이터가 있으면 `true`
        public func hasFormat(_ format: String) async -> Bool {
            await MainActor.run {
                switch format.lowercased() {
                case "text":
                    return UIPasteboard.general.hasStrings
                case "image", "image/png":
                    return UIPasteboard.general.hasImages
                default:
                    return false
                }
            }
        }
    }
#endif
