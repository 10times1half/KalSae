#if os(Linux)
    public import KalsaeCore
    public import Foundation

    extension KSLinuxDemoHost: KSDemoHostWithUserScripts {
        /// 래핑이 끝난 IIFE를 WebKitGTK `webkit_user_content_manager_add_script`로
        /// 등록한다. wrapper IIFE의 origin 매칭이 `forMainFrameOnly` 의도를 표현한다.
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
