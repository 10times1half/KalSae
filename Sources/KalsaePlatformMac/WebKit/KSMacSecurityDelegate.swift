#if os(macOS)
    internal import AppKit
    internal import WebKit
    public import KalsaeCore
    public import Foundation

    /// RFC-008 §2.1~2.3 — WKWebView 보안 핸들러.
    ///
    /// Windows의 `installSecurityHandlers(allowPopups:openExternal:)` 와 동등한
    /// 역할을 macOS에서 수행한다. WKUIDelegate / WKNavigationDelegate을 통해:
    ///
    /// - `window.open` / `target=_blank` 팝업을 차단하고 (allowPopups=false 시),
    ///   필요하면 `openExternal` 클로저로 OS 기본 브라우저로 라우팅한다.
    /// - 마이크/카메라/지오로케이션 권한 요청을 모두 거부한다(Windows 패턴 동일).
    ///
    /// 인스턴스는 `WKWebViewHost`가 강하게 보유한다.
    @MainActor
    internal final class KSMacSecurityDelegate: NSObject, WKUIDelegate {
        var allowPopups: Bool = true
        var openExternal: (@MainActor (String) -> Void)?

        // MARK: - WKUIDelegate (popup blocking)

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // window.open / target="_blank" — 새 WKWebView를 만들지 않는다.
            // allowPopups=false: 외부 핸들러(있으면)로 라우팅 후 차단.
            // allowPopups=true: 같은 webView에서 로드(WKWebView 기본 동작).
            if !allowPopups {
                if let url = navigationAction.request.url?.absoluteString {
                    openExternal?(url)
                }
                return nil
            }
            // 같은 webView에서 탐색을 진행시켜 새 윈도우 없이 페이지가 이동하도록 한다.
            if navigationAction.targetFrame == nil,
                let url = navigationAction.request.url
            {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        // MARK: - 권한 요청 거부 (mic/camera)

        @available(macOS 12.0, *)
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            // Windows: PermissionRequested → Deny. 동일하게 거부.
            decisionHandler(.deny)
        }
    }

    /// WKNavigationDelegate — 내비게이션 정책 (외부 URL 라우팅).
    ///
    /// `mailto:`, `tel:`, `sms:`, `http(s):`(외부 도메인) 등을 가로채
    /// `openExternal`로 라우팅한다. 같은 가상 호스트(`ks://app/`,
    /// `https://app.kalsae/`) 내부 탐색은 그대로 진행시킨다.
    @MainActor
    internal final class KSMacNavigationDelegate: NSObject, WKNavigationDelegate {
        var openExternal: (@MainActor (String) -> Void)?
        var virtualHosts: Set<String> = ["app.kalsae", "app"]  // ks://app, https://app.kalsae

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let scheme = url.scheme?.lowercased() ?? ""
            // 내부 스킴: 통과.
            if scheme == "ks" || scheme == "about" || scheme == "blob" || scheme == "data" {
                decisionHandler(.allow)
                return
            }
            // 가상 호스트 도메인: 통과.
            if let host = url.host?.lowercased(), virtualHosts.contains(host) {
                decisionHandler(.allow)
                return
            }
            // 사용자 클릭에 의한 외부 링크는 OS로 라우팅.
            if navigationAction.navigationType == .linkActivated
                || scheme == "mailto" || scheme == "tel" || scheme == "sms"
            {
                openExternal?(url.absoluteString)
                decisionHandler(.cancel)
                return
            }
            // 그 외(스크립트/리다이렉트/메인 프레임 첫 로드): 기본 허용.
            decisionHandler(.allow)
        }
    }

    /// RFC-008 §2.1 — JS 주입 기반 컨텍스트 메뉴/드롭 비활성화.
    ///
    /// macOS에는 WebKit2 라이브에서 컨텍스트 메뉴를 비활성화하는 깔끔한 API가
    /// 없으므로(WKWebView 내부 메뉴는 제어 가능하지만 모든 페이지를 한 번에
    /// 끄는 가장 간단한 방법은 JS 레벨), `document` 레벨 이벤트를
    /// preventDefault한다. Tauri/Electron의 production-mode 패턴과 동일.
    internal enum KSMacSecurityScripts {
        /// `oncontextmenu` 차단 스크립트.
        internal static let disableContextMenu: String = """
            (function(){
              const block = (e) => { e.preventDefault(); return false; };
              if (document.body) {
                document.addEventListener('contextmenu', block, { capture: true });
              } else {
                document.addEventListener('DOMContentLoaded', () => {
                  document.addEventListener('contextmenu', block, { capture: true });
                });
              }
            })();
            """

        /// `dragover` / `drop` 차단 스크립트 — 외부 파일이 페이지로 떨어지는
        /// 것을 방지한다. 페이지 내부 드래그(`draggable=true` 요소)는 영향 없음.
        internal static let disableExternalDrop: String = """
            (function(){
              const dropTypes = ['Files'];
              const isExternal = (e) => {
                if (!e.dataTransfer) return false;
                for (const t of e.dataTransfer.types) {
                  if (dropTypes.indexOf(t) >= 0) return true;
                }
                return false;
              };
              const block = (e) => {
                if (isExternal(e)) { e.preventDefault(); }
              };
              const install = () => {
                document.addEventListener('dragover', block, { capture: true });
                document.addEventListener('drop', block, { capture: true });
              };
              if (document.body) install();
              else document.addEventListener('DOMContentLoaded', install);
            })();
            """
    }
#endif
