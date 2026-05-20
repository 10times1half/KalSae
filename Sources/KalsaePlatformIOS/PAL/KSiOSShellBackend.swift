#if os(iOS)
    internal import UIKit
    public import KalsaeCore
    public import Foundation

    /// iOS 셸(Shell) 작업을 처리하는 `KSShellBackend` 구현체입니다.
    ///
    /// iOS는 샌드박스 환경이므로 데스크톱 OS와 같은 수준의 셸 접근이
    /// 불가능합니다. 제공하는 기능은 다음과 같습니다:
    ///
    /// - `openExternal`: `UIApplication.shared.open(_:options:)`을 사용하여
    ///   URL을 시스템 기본 앱으로 엽니다 (Safari, Mail, 전화 등).
    /// - `showItemInFolder`: iOS에는 Finder 같은 파일 관리자가 없으므로
    ///   동일하게 `openExternal`로 폴백합니다.
    /// - `moveToTrash`: iOS 샌드박스에서는 지원되지 않으며 항상 오류를
    ///   던집니다.
    ///
    /// iOS 9부터 `canOpenURL`은 `LSApplicationQueriesSchemes` 화이트리스트가
    /// 필요하고 false-negative가 흔하므로, 사전 체크 대신
    /// `open(_:options:completionHandler:)`의 결과로 직접 성공 여부를 판정합니다.
    public struct KSiOSShellBackend: KSShellBackend, Sendable {
        public init() {}

        /// URL을 시스템 기본 앱으로 엽니다.
        /// `UIApplication.shared.open`을 메인 스레드에서 호출합니다.
        /// - Parameter url: 열 URL (예: `https://example.com`, `tel:010...`)
        /// - Throws: `KSError` — URL을 열 수 없으면 `code: .shellInvocationFailed`
        public func openExternal(_ url: URL) async throws(KSError) {
            // `canOpenURL`은 LSApplicationQueriesSchemes 화이트리스트가 필요하고
            // false-negative가 흔하므로 사전 체크 대신 `open(_:options:completionHandler:)`
            // 결과로 직접 판정합니다.
            let opened: Bool = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                Task { @MainActor in
                    UIApplication.shared.open(url, options: [:]) { ok in
                        cont.resume(returning: ok)
                    }
                }
            }
            if !opened {
                throw KSError(
                    code: .shellInvocationFailed,
                    message: "Cannot open URL on iOS: \(url.absoluteString)")
            }
        }

        /// 파일을 Finder에 표시합니다.
        /// iOS에는 Finder 개념이 없으므로 `openExternal`로 폴백하여 파일 URL을
        /// 엽니다. 적절한 앱이 등록되어 있으면 그 앱이 파일을 처리합니다.
        /// - Parameter url: 표시할 파일 URL
        /// - Throws: `KSError` — URL을 열 수 없으면 `code: .shellInvocationFailed`
        public func showItemInFolder(_ url: URL) async throws(KSError) {
            try await openExternal(url)
        }

        /// 파일을 휴지통으로 이동합니다.
        /// iOS 샌드박스에서는 이 기능이 지원되지 않습니다. 파일을 삭제하려면
        /// `FileManager`를 직접 사용해야 합니다.
        /// - Parameter url: 삭제할 파일 URL
        /// - Throws: `KSError` — 항상 `code: .unsupportedPlatform`
        public func moveToTrash(_ url: URL) async throws(KSError) {
            _ = url
            throw KSError.unsupportedPlatform("moveToTrash is not supported on iOS sandbox")
        }
    }
#endif
