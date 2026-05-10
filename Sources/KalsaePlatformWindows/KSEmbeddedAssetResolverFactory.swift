#if os(Windows)
    package import Foundation
    package import KalsaeCore

    package enum KSEmbeddedAssetResolverFactory {
        package static func makeResolver(defaultRoot: URL, cache: KSAssetCache) -> KSAssetResolver {
            let executableDir = WebView2Callbacks.executableDirectory()

            if let assetMap = KSWebView2Runtime.loadEmbeddedAssetsMap(
                executableDir: executableDir)
            {
                let source = KSEmbeddedAssetSource(assets: assetMap)
                // `root` 는 캐시 키 / 진단용 기준 URL. 메모리 서빙이라 디스크
                // 경로는 존재하지 않지만 임의의 안정적인 URL 을 제공한다.
                let virtualRoot = executableDir.appendingPathComponent("__embedded__")
                return KSAssetResolver(root: virtualRoot, source: source, cache: cache)
            }

            return KSAssetResolver(root: defaultRoot, cache: cache)
        }

        package static func shouldPreferEmbeddedAssets() -> Bool {
            let executableDir = WebView2Callbacks.executableDirectory()
            return KSWebView2Runtime.hasEmbeddedAssetsResource(executableDir: executableDir)
        }
    }
#endif
