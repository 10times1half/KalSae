#if os(Windows)
    package import Foundation
    package import KalsaeCore

    package enum KSEmbeddedAssetResolverFactory {
        package static func makeResolver(defaultRoot: URL, cache: KSAssetCache) -> KSAssetResolver {
            let executableDir = WebView2Callbacks.executableDirectory()
            let identifier = WebView2Callbacks.appIdentifier()

            if let embeddedRoot = KSWebView2Runtime.resolveEmbeddedAssetsDirectory(
                executableDir: executableDir,
                identifier: identifier)
            {
                return KSAssetResolver(root: embeddedRoot, cache: cache)
            }

            return KSAssetResolver(root: defaultRoot, cache: cache)
        }

        package static func shouldPreferEmbeddedAssets() -> Bool {
            let executableDir = WebView2Callbacks.executableDirectory()
            return KSWebView2Runtime.hasEmbeddedAssetsResource(executableDir: executableDir)
        }
    }
#endif
