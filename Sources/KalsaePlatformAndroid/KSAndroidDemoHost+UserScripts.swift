#if os(Android)
    public import KalsaeCore
    public import Foundation

    extension KSAndroidDemoHost: KSDemoHostWithUserScripts {
        /// 래핑이 끝난 IIFE를 다음 `documentStartScript()` 합성 시 함께 주입되도록 큐잉한다.
        /// `forMainFrameOnly`는 wrapper IIFE의 origin 매칭이 표현하므로 무시된다.
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
