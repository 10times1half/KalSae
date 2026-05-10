/// `BeginUpdateResourceW` / `UpdateResourceW` / `EndUpdateResourceW` 를 사용해
/// PE 실행 파일에 RCDATA / RT_MANIFEST 리소스를 in-process 로 주입한다.
///
/// `KSStandalonePostProcessor` 가 ResourceHacker 가 PATH 또는 사용자 캐시에
/// 없을 때 폴백으로 사용한다 — 외부 도구 없이 standalone 패키징이 작동하도록
/// 보장하는 1차 경로다. ResourceHacker 가 있다면 그 경로를 우선 시도하고,
/// 실패 시 이 in-process 경로로 재시도한다 (제어 흐름은 호출자 책임).
///
/// 한계:
/// - icon (RT_GROUP_ICON + RT_ICON 다중 엔트리)과 RT_VERSION (VS_FIXEDFILEINFO
///   + 가변 길이 StringFileInfo/VarFileInfo 트리) 은 형식이 복잡해 별도 구현이
///   필요하다. 그 두 가지는 여전히 `rcedit` 에 의존한다.
/// - 디지털 서명된 EXE 에 적용하면 서명이 무효화된다 (Windows의 서명 정책상
///   그게 정상이며, standalone 후처리는 서명 *전* 단계에서 실행한다).
internal import Foundation

#if os(Windows)
    internal import WinSDK

    internal struct KSPEResourcePatchError: Error, CustomStringConvertible {
        internal let stage: String
        internal let lastError: DWORD
        internal var description: String {
            "PE resource patch failed at \(stage) (GetLastError=\(lastError))"
        }
    }

    internal enum KSPEResourcePatcher {
        /// 단일 BeginUpdateResource → 여러 UpdateResource → EndUpdateResource 트랜잭션.
        ///
        /// - Parameters:
        ///   - executable: 패치할 EXE 경로.
        ///   - rcdata: `name → data` RCDATA 엔트리 목록.
        ///   - manifest: nil 이 아니면 RT_MANIFEST(id=1) 로 주입.
        ///   - language: 0 = `LANG_NEUTRAL` (기본).
        /// - Throws: `KSPEResourcePatchError` 한 단계라도 실패하면 트랜잭션을
        ///   discard 한 뒤 던진다.
        internal static func update(
            executable: URL,
            rcdata: [(name: String, data: Data)],
            manifest: Data?,
            language: WORD = 0
        ) throws {
            let exePath = executable.path
            let hUpdate: HANDLE? = exePath.withCString(encodedAs: UTF16.self) { ptr in
                BeginUpdateResourceW(ptr, false)
            }
            // BeginUpdateResourceW 는 실패 시 NULL 을 돌려준다 (INVALID_HANDLE_VALUE 가 아니라).
            // Swift 의 옵셔널 변환이 NULL → nil 로 처리하므로 guard let 만으로 충분하다.
            guard let hUpdate else {
                throw KSPEResourcePatchError(
                    stage: "BeginUpdateResource", lastError: GetLastError())
            }

            // 실패 시 discard, 성공 시 commit.
            var commit = false
            defer {
                _ = EndUpdateResourceW(hUpdate, commit ? false : true)
            }

            // RT_RCDATA = 10, RT_MANIFEST = 24
            guard let rcdataType = UnsafeMutablePointer<WCHAR>(bitPattern: 10),
                let manifestType = UnsafeMutablePointer<WCHAR>(bitPattern: 24),
                let manifestName = UnsafeMutablePointer<WCHAR>(bitPattern: 1)
            else {
                throw KSPEResourcePatchError(stage: "MAKEINTRESOURCE", lastError: 0)
            }

            for entry in rcdata {
                try entry.data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
                    guard let base = buf.baseAddress, !buf.isEmpty else {
                        throw KSPEResourcePatchError(
                            stage: "UpdateResource(RCDATA \(entry.name)) — empty data",
                            lastError: 0)
                    }
                    let mutablePtr = UnsafeMutableRawPointer(mutating: base)
                    let ok = entry.name.withCString(encodedAs: UTF16.self) { (namePtr) -> Bool in
                        UpdateResourceW(
                            hUpdate,
                            rcdataType,
                            namePtr,
                            language,
                            mutablePtr,
                            DWORD(buf.count))
                    }
                    if !ok {
                        throw KSPEResourcePatchError(
                            stage: "UpdateResource(RCDATA \(entry.name))",
                            lastError: GetLastError())
                    }
                }
            }

            if let manifest {
                try manifest.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
                    guard let base = buf.baseAddress, !buf.isEmpty else {
                        throw KSPEResourcePatchError(
                            stage: "UpdateResource(RT_MANIFEST) — empty data", lastError: 0)
                    }
                    let mutablePtr = UnsafeMutableRawPointer(mutating: base)
                    let ok = UpdateResourceW(
                        hUpdate,
                        manifestType,
                        manifestName,
                        language,
                        mutablePtr,
                        DWORD(buf.count))
                    if !ok {
                        throw KSPEResourcePatchError(
                            stage: "UpdateResource(RT_MANIFEST)",
                            lastError: GetLastError())
                    }
                }
            }

            commit = true
        }
    }
#endif
