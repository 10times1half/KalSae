/// PE 리소스(RCDATA `KSAS_CONFIG_JSON`)에 임베드된 `Kalsae.json` 데이터를 로드한다.
///
/// `kalsae build --standalone` 의 후처리가 `Kalsae.json` 을 EXE 안에 RCDATA 로
/// 함께 주입하면, 외부 `Kalsae.json` 이 없어도 단일 EXE 만으로 부팅이 가능하다.
/// `KSApp.boot(configURL:)` 가 외부 파일 로드 실패 시 이 헬퍼로 폴백한다.
///
/// Windows 외 호스트에서는 항상 `nil`.
#if os(Windows)
    public import Foundation
    internal import WinSDK

    /// 일반화된 PE RCDATA 로더. `KSAS_CONFIG_JSON`, `KSAS_RUNTIME_JSON`,
    /// `KSAS_ASSETS_ZIP` 같이 standalone 후처리가 EXE 에 임베드한 임의의
    /// RCDATA 엔트리를 이름으로 조회한다.
    public enum KSEmbeddedResourceLoader {
        /// PE RCDATA `<resourceName>` 의 바이트를 반환. 없으면 nil.
        public static func loadEmbeddedResource(named resourceName: String) -> Data? {
            let resourceType = UnsafePointer<WCHAR>(bitPattern: 10)
            guard let resourceType else { return nil }

            return resourceName.withCString(encodedAs: UTF16.self) { resourceNamePtr in
                guard let resource = FindResourceW(nil, resourceNamePtr, resourceType) else {
                    return nil
                }
                let size = SizeofResource(nil, resource)
                guard size > 0,
                    let handle = LoadResource(nil, resource),
                    let bytes = LockResource(handle)
                else {
                    return nil
                }
                return Data(bytes: bytes, count: Int(size))
            }
        }
    }

    /// 호환성 래퍼. `KSEmbeddedResourceLoader` 가 도입되기 전 코드 (KSApp.boot)
    /// 가 사용하는 진입점을 그대로 유지한다.
    public enum KSEmbeddedConfigLoader {
        /// PE RCDATA `KSAS_CONFIG_JSON` 의 바이트를 반환. 없으면 nil.
        public static func loadEmbeddedConfigData() -> Data? {
            KSEmbeddedResourceLoader.loadEmbeddedResource(named: "KSAS_CONFIG_JSON")
        }
    }
#endif
