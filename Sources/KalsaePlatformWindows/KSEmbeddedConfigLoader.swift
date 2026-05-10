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

    public enum KSEmbeddedConfigLoader {
        /// PE RCDATA `KSAS_CONFIG_JSON` 의 바이트를 반환. 없으면 nil.
        public static func loadEmbeddedConfigData() -> Data? {
            return loadEmbeddedResource(named: "KSAS_CONFIG_JSON")
        }

        private static func loadEmbeddedResource(named resourceName: String) -> Data? {
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
#endif
