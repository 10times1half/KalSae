#if os(iOS)
    internal import UIKit
    internal import WebKit
    public import KalsaeCore
    public import Foundation

    /// RFC-008 §4.2 — iOS WKWebView 보안 핸들러. macOS 패턴과 동일하나
    /// AppKit → UIKit 차이를 반영한다.
    @MainActor
    internal final class KSiOSSecurityDelegate: NSObject, WKUIDelegate {
        var allowPopups: Bool = true
        var openExternal: (@MainActor (String) -> Void)?

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if !allowPopups {
                if let url = navigationAction.request.url?.absoluteString {
                    openExternal?(url)
                }
                return nil
            }
            if navigationAction.targetFrame == nil,
                let url = navigationAction.request.url
            {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        @available(iOS 15.0, *)
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            decisionHandler(.deny)
        }
    }

    @MainActor
    internal final class KSiOSNavigationDelegate: NSObject, WKNavigationDelegate {
        var openExternal: (@MainActor (String) -> Void)?
        var virtualHosts: Set<String> = ["app.kalsae", "app"]

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
            if scheme == "ks" || scheme == "about" || scheme == "blob" || scheme == "data" {
                decisionHandler(.allow)
                return
            }
            if let host = url.host?.lowercased(), virtualHosts.contains(host) {
                decisionHandler(.allow)
                return
            }
            if navigationAction.navigationType == .linkActivated
                || scheme == "mailto" || scheme == "tel" || scheme == "sms"
            {
                openExternal?(url.absoluteString)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }

    internal enum KSiOSSecurityScripts {
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
              // iOS Safari: 텍스트 선택/롱프레스 스타일도 함께 비활성화.
              const css = document.createElement('style');
              css.textContent = '*{-webkit-touch-callout:none;-webkit-user-select:none;}';
              if (document.head) document.head.appendChild(css);
              else document.addEventListener('DOMContentLoaded', () => document.head.appendChild(css));
            })();
            """

        internal static let disableExternalDrop: String = """
            (function(){
              const isExternal = (e) => {
                if (!e.dataTransfer) return false;
                for (const t of e.dataTransfer.types) { if (t === 'Files') return true; }
                return false;
              };
              const block = (e) => { if (isExternal(e)) e.preventDefault(); };
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
