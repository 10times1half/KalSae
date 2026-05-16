#if os(Windows)
    public import KalsaeCore
    public import Foundation

    extension KSWindowsDemoHost: KSDemoHostWithUserScripts {
        /// 래핑이 끝난 IIFE를 `AddScriptToExecuteOnDocumentCreated`로 등록한다.
        /// WebView2는 document-created 훅에서 모든 프레임에 주입하므로
        /// `forMainFrameOnly` 의도는 wrapper IIFE의 origin 매칭으로 표현된다.
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
