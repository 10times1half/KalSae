#if os(iOS)
    public import KalsaeCore
    public import Foundation

    /// iOS용 딥 링크(Deep Link) 백엔드 구현체입니다.
    ///
    /// iOS에서 URL 스킴 등록은 Info.plist의 `CFBundleURLTypes` 항목으로만
    /// 가능하며, 런타임에 스킴을 등록/해제할 수 없습니다. 이 백엔드는
    /// Info.plist 기반의 정적 구성을 읽어 현재 등록된 스킴을 확인하고,
    /// 런타임 등록/해제 요청이 들어오면 `.unsupportedPlatform` 오류를 던집니다.
    ///
    /// 딥 링크 URL은 iOS에서 `UISceneDelegate.scene(_:openURLContexts:)`를
    /// 통해 전달됩니다. Kalsae는 이 URL을 `CommandLine.arguments` 형태로
    /// 변환하여 `currentLaunchURLs(forSchemes:)`로 접근할 수 있게 합니다.
    public struct KSiOSDeepLinkBackend: KSDeepLinkBackend, Sendable {
        /// 백엔드의 고유 식별자입니다.
        public let identifier: String

        public init(identifier: String) {
            self.identifier = identifier
        }

        /// URL 스킴을 런타임에 등록합니다.
        /// iOS에서는 Info.plist 기반으로만 등록 가능하므로 항상 실패합니다.
        /// - Parameter scheme: 등록하려는 URL 스킴 (예: `"kalsae-demo"`)
        /// - Throws: `KSError` — 항상 `code: .unsupportedPlatform`
        public func register(scheme: String) throws(KSError) {
            _ = scheme
            throw KSError.unsupportedPlatform(
                "iOS URL scheme registration is Info.plist-driven and cannot be changed at runtime")
        }

        /// URL 스킴을 런타임에 해제합니다.
        /// iOS에서는 Info.plist 기반으로만 등록 해제 가능하므로 항상 실패합니다.
        /// - Parameter scheme: 해제하려는 URL 스킴
        /// - Throws: `KSError` — 항상 `code: .unsupportedPlatform`
        public func unregister(scheme: String) throws(KSError) {
            _ = scheme
            throw KSError.unsupportedPlatform(
                "iOS URL scheme unregistration is not available at runtime")
        }

        /// 특정 URL 스킴이 Info.plist에 등록되어 있는지 확인합니다.
        /// `CFBundleURLTypes` 배열을 직접 조회하며, 대소문자를 구분하지 않습니다.
        /// - Parameter scheme: 확인할 URL 스킴
        /// - Returns: 등록되어 있으면 `true`
        public func isRegistered(scheme: String) -> Bool {
            guard let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
                return false
            }
            let lower = scheme.lowercased()
            for entry in urlTypes {
                guard let schemes = entry["CFBundleURLSchemes"] as? [String] else { continue }
                if schemes.contains(where: { $0.lowercased() == lower }) {
                    return true
                }
            }
            return false
        }

        /// 현재 앱 실행 시 전달된 딥 링크 URL 중 주어진 스킴과 일치하는 것들을
        /// 반환합니다. iOS에서 딥 링크는 `UISceneDelegate`를 통해 전달되며,
        /// Kalsae 부팅 시 `CommandLine.arguments`에 URL 문자열로 추가됩니다.
        ///
        /// - Parameter schemes: 찾을 URL 스킴 목록
        /// - Returns: 일치하는 딥 링크 URL 문자열 배열
        public func currentLaunchURLs(forSchemes schemes: [String]) -> [String] {
            let lowerSchemes = Set(schemes.map { $0.lowercased() })
            return CommandLine.arguments.filter { arg in
                guard let idx = arg.firstIndex(of: ":") else { return false }
                return lowerSchemes.contains(arg[..<idx].lowercased())
            }
        }

        /// 주어진 인자 배열에서 특정 스킴과 일치하는 딥 링크 URL을 추출합니다.
        /// `currentLaunchURLs(forSchemes:)`의 일반화 버전으로, 커스텀 인자
        /// 배열에서도 동일한 필터링을 수행할 수 있습니다.
        ///
        /// - Parameters:
        ///   - args: 검사할 인자 문자열 배열
        ///   - schemes: 찾을 URL 스킴 목록
        /// - Returns: 유효한 URL 형식이며 스킴이 일치하는 문자열 배열
        public func extractURLs(fromArgs args: [String], forSchemes schemes: [String]) -> [String] {
            let lowerSchemes = Set(schemes.map { $0.lowercased() })
            return args.filter { arg in
                guard let idx = arg.firstIndex(of: ":") else { return false }
                let scheme = arg[..<idx].lowercased()
                return lowerSchemes.contains(scheme) && URL(string: arg) != nil
            }
        }
    }
#endif
