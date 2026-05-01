#if os(iOS)
internal import UIKit
internal import WebKit

/// `KSiOSWebViewHost`의 `WKWebView`를 호스팅하는 전체 화면 `UIViewController`.
/// 웹 콘텐츠가 크롬을 채우는 표준 Kalsae 데스크톱 윈도우 동작과
/// 일치하도록 안전 영역을 무시한 바운드에 관계없이 전체 화면을
/// 채우도록 웹뷰를 다 네 가장자리에 고정시킨다.
@MainActor
internal final class KSiOSWebViewController: UIViewController {
    let webViewHost: KSiOSWebViewHost

    init(webViewHost: KSiOSWebViewHost) {
        self.webViewHost = webViewHost
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let wv = webViewHost.webView
        wv.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(wv)
        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: view.topAnchor),
            wv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            wv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}
#endif
