#if os(iOS)
    public import KalsaeCore
    public import Foundation

    extension KSiOSDemoHost: KSDemoHostWithUserScripts {
        /// 래핑이 끝난 IIFE를 WKUserScript로 등록한다.
        /// 모든 프레임에 주입되고, `forMainFrameOnly` 의도는 wrapper IIFE의
        /// origin 매칭으로 표현된다.
        public func addUserScript(
            id: String,
            wrappedSource: String,
            forMainFrameOnly: Bool
        ) throws(KSError) {
            _ = forMainFrameOnly
            _ = id
            try addDocumentCreatedScript(wrappedSource)
        }
    }
#endif
