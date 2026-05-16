#if os(macOS)
    public import KalsaeCore
    public import Foundation

    extension KSMacDemoHost: KSDemoHostWithUserScripts {
        /// 래핑이 끝난 IIFE를 WKUserScript로 등록한다.
        /// `KSUserScriptWrapper`가 origin 가드와 documentEnd 폴리필을 처리하므로
        /// 백엔드는 단순히 `addDocumentCreatedScript`(documentStart 주입)로 위임한다.
        public func addUserScript(
            id: String,
            wrappedSource: String,
            forMainFrameOnly: Bool
        ) throws(KSError) {
            // `forMainFrameOnly`는 IIFE 내부에서 origin 매칭으로 충분히 표현되므로
            // 현재 macOS 백엔드는 항상 모든 프레임에 주입하고 wrapper가 분기한다.
            _ = forMainFrameOnly
            _ = id
            try addDocumentCreatedScript(wrappedSource)
        }
    }
#endif
