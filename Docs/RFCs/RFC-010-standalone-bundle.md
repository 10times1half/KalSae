# RFC-010 — 단일 실행파일 번들 (`--standalone`)

| 항목 | 내용 |
|------|------|
| 상태 | 초안 (Draft) |
| 날짜 | 2026-05-09 |
| 영향 범위 | `Sources/CKalsaeWV2/`, `Sources/KalsaeCLI/`, `Sources/KalsaePlatformWindows/`, `Package.swift` |
| 관련 | `KSPackager`, `kswv2_loader`, `KSWebView2LoaderResolver`, `KSWebView2Provisioner` |

---

## 1. 동기 (Motivation)

`kalsae build`가 생성하는 패키지 산출물은 현재 다음과 같은 파일들로 구성된다:

```
<AppName>.exe          ← 메인 실행파일
WebView2Loader.dll     ← WebView2 런타임 로더 DLL
<AppName>.exe.manifest ← SxS 매니페스트 (DPI awareness)
Kalsae.json            ← 설정
Resources/             ← 프론트엔드 에셋
webview2-runtime/      ← fixed 모드 WebView2 런타임 (선택)
MicrosoftEdgeWebview2Setup.exe ← evergreen 부트스트래퍼 (선택)
kalsae.runtime.json    ← 런타임 설정
```

사용자 입장에서는 "단일 `.exe` 하나만 배포하면 끝"인 경험을 원한다. Wails, Electron 등 경쟁 프레임워크는 단일 바이너리 배포를 지원하거나 최소한의 파일로 구성된다.

본 RFC는 `kalsae build --standalone` 플래그를 추가해 **WebView2Loader.dll을 exe에 내장**하고, **프론트엔드 에셋을 exe에 내장**하여 실질적인 단일 실행파일을 생성하는 방안을 제시한다.

---

## 2. 설계 결정 (Design Decisions)

### 2.1 WebView2Loader.dll 내장 방식

**결정: 임시 파일 덤프 (Temp File Dump)**

WebView2Loader.dll을 Win32 `RT_RCDATA` 리소스로 exe에 내장하고, 런타임에 `%TEMP%` 디렉터리에 추출한 뒤 `LoadLibraryW`로 로드한다.

**선택 이유:**

| 방식 | 장점 | 단점 |
|------|------|------|
| **메모리 직접 로드** (PE 로더 구현) | 진정한 단일 exe | 구현 복잡도 매우 높음, PE 재배치/IAT 패치/TLS 초기화 필요, 보안 소프트웨어 오탐 가능 |
| **임시 파일 덤프** ✅ | 구현 단순, 기존 `LoadLibraryW` 로직 재사용, 안정적 | `%TEMP%`에 임시 파일 생성, 프로세스 종료 시 cleanup 필요 |
| **정적 링크** (WebView2LoaderStatic.lib) | DLL 불필요 | 아키텍처별 lib 필요, SwiftPM에서 MSVC 정적 링크 설정 복잡, 라이선스 호환성 확인 필요 |

Wails도 동일한 임시 파일 덤프 방식을 사용한다 (`go:embed` → `%TEMP%`에 쓰기 → `LoadLibraryW`).

### 2.2 프론트엔드 에셋 내장 방식

**결정: 기존 `WebResourceRequested` 핸들러 재사용, Swift `Data` 리터럴로 내장**

현재 Kalsae는 `WebResourceRequested` 이벤트를 후킹해 외부 `Resources/` 디렉터리에서 파일을 서빙한다 (`kswv2_resource.cpp` + Swift 측 `KSAssetResolver`). 이 구조를 유지한 채, `KSAssetResolver`가 디스크 대신 컴파일 타임에 내장된 `Data`를 읽도록 변경한다.

**선택 이유:**
- 기존 `WebResourceRequested` 인프라를 그대로 재사용
- SwiftPM의 `Resources` 디렉터리와 `.copy`를 활용해 빌드 타임에 에셋을 번들에 포함
- `--standalone` 모드에서만 내장 데이터 사용, 일반 모드는 현재와 동일

### 2.3 아키텍처 대응

**결정: 빌드 시 `--arch` 플래그로 지정된 아키텍처의 DLL만 내장**

단일 exe는 하나의 아키텍처만 지원한다. `--arch x64`면 x64용 WebView2Loader.dll만 내장한다. 향후 아키텍처-agnostic 단일 바이너리는 이 RFC의 범위를 벗어난다.

---

## 3. 상세 구현 계획

### 3.1 C++ shim: 리소스에서 DLL 추출 (`kswv2_loader.cpp`)

`kswv2_loader.cpp`에 `LoadLibraryW` 호출 전에 리소스에서 DLL을 추출하는 fallback 경로를 추가한다.

```cpp
// kswv2_loader.cpp — 새 함수 추가

/// Win32 RT_RCDATA 리소스에서 WebView2Loader.dll을 추출해 %TEMP%에 쓰고
/// LoadLibraryW로 로드한다. 리소스가 없으면(일반 모드) FALSE를 반환한다.
static BOOL TryLoadFromResource() {
    HRSRC hRes = FindResourceW(NULL, L"KWV2_LOADER_DLL", RT_RCDATA);
    if (!hRes) return FALSE;  // 리소스 없음 → 일반 LoadLibraryW로 fallback

    HGLOBAL hGlob = LoadResource(NULL, hRes);
    void *data = LockResource(hGlob);
    DWORD size = SizeofResource(NULL, hRes);
    if (!data || size == 0) return FALSE;

    // %TEMP%에 임시 파일 생성
    wchar_t tmpDir[MAX_PATH], tmpFile[MAX_PATH];
    if (!GetTempPathW(MAX_PATH, tmpDir)) return FALSE;
    if (!GetTempFileNameW(tmpDir, L"kwv", 0, tmpFile)) return FALSE;

    HANDLE hFile = CreateFileW(tmpFile, GENERIC_WRITE, 0, NULL,
                               CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) return FALSE;

    DWORD written = 0;
    BOOL ok = WriteFile(hFile, data, size, &written, NULL);
    CloseHandle(hFile);

    if (!ok || written != size) {
        DeleteFileW(tmpFile);
        return FALSE;
    }

    // 임시 파일 로드
    HMODULE hMod = LoadLibraryW(tmpFile);
    if (!hMod) {
        DeleteFileW(tmpFile);
        return FALSE;
    }

    // 함수 포인터 획득
    g_pfnCreateEnv = reinterpret_cast<FnCreateEnv>(
        GetProcAddress(hMod, "CreateCoreWebView2EnvironmentWithOptions"));
    g_pfnGetVersion = reinterpret_cast<FnGetVersion>(
        GetProcAddress(hMod, "GetAvailableCoreWebView2BrowserVersionString"));

    if (!g_pfnCreateEnv || !g_pfnGetVersion) {
        FreeLibrary(hMod);
        DeleteFileW(tmpFile);
        return FALSE;
    }

    g_hModule = hMod;

    // cleanup: 프로세스 종료 시 임시 파일 삭제 예약
    // (FreeLibrary 시점에 파일이 잠겨 있으므로 지금 삭제 불가)
    // 간단한 atexit 또는 DLL_PROCESS_DETACH에서 처리
    return TRUE;
}
```

**기존 `LoadOnce` 함수 수정:**

```cpp
static BOOL CALLBACK LoadOnce(PINIT_ONCE, PVOID, PVOID *) {
    // 1) 리소스에서 로드 시도 (standalone 모드)
    if (TryLoadFromResource()) return TRUE;

    // 2) 디렉터리가 설정되어 있으면 prepend
    if (g_dir[0] != L'\0') {
        SetDllDirectoryW(g_dir);
    }

    // 3) 일반 LoadLibraryW (기존 코드)
    HMODULE hMod = LoadLibraryW(L"WebView2Loader.dll");

    if (g_dir[0] != L'\0') {
        SetDllDirectoryW(nullptr);
    }
    // ... 이하 기존 로직 동일 ...
}
```

**임시 파일 cleanup:**

```cpp
// kswv2_loader.cpp — DLL_PROCESS_DETACH에서 cleanup
// 또는 atexit() 등록

// 전역 변수에 임시 파일 경로 저장
static wchar_t g_tmpFile[MAX_PATH] = {};

// TryLoadFromResource 성공 시 g_tmpFile에 경로 저장
// cleanup은:
//   a) atexit() — 간단하지만 FreeLibrary보다 먼저 실행될 수 있음
//   b) DLL_PROCESS_DETACH — DllMain에서 처리
//   c) 지연 삭제 — 다음 부팅 시 이전 임시 파일 정리

// 권장: g_tmpFile에 경로를 저장하고, 다음 LoadOnce 실행 시
// 이전 g_tmpFile이 있으면 삭제 후 새로 생성. 프로세스 종료 시
// OS가 자동 cleanup하므로 최악의 경우에도 문제없음.
```

### 3.2 리소스 파일 추가 (`CKalsaeWV2`)

**`Sources/CKalsaeWV2/src/loader_resource.rc`** 생성:

```rc
// loader_resource.rc
// WebView2Loader.dll을 Win32 RCDATA 리소스로 내장한다.
// 아키텍처별로 다른 .rc 파일이 필요하다.
// 빌드 시 --arch에 따라 적절한 파일이 선택된다.

#define KWV2_LOADER_DLL 100
KWV2_LOADER_DLL RCDATA "Vendor/WebView2/runtimes/win-x64/native/WebView2Loader.dll"
```

**아키텍처별 .rc 파일:**

| 파일 | 내용 |
|------|------|
| `loader_resource.x64.rc` | `win-x64/native/WebView2Loader.dll` |
| `loader_resource.arm64.rc` | `win-arm64/native/WebView2Loader.dll` |
| `loader_resource.x86.rc` | `win-x86/native/WebView2Loader.dll` |

빌드 시 `--arch`에 따라 조건부로 포함한다.

### 3.3 `Package.swift` — 리소스 컴파일 설정

SwiftPM은 `.rc` 파일을 자동으로 처리하지 않는다. 따라서 별도의 빌드 단계가 필요하다.

**옵션 A: 빌드 전 스크립트 (권장)**

`kalsae build`의 `--standalone` 모드에서 `swift build` 호출 전에 `rc.exe`를 실행해 `.res` 파일을 생성하고, `unsafeFlags`로 링크한다.

```swift
// Package.swift — CKalsaeWV2 타겟에 unsafeFlags 추가
.target(
    name: "CKalsaeWV2",
    ...
    linkerSettings: [
        .unsafeFlags(["-Xlinker", "-include:loader_resource.res"],
                     .when(platforms: [.windows])),
        ...
    ]
)
```

단, `unsafeFlags`는 모든 빌드에 적용되므로, 일반 모드에서는 `.res` 파일이 없어 링크 경고가 발생할 수 있다. 따라서 **빌드 스크립트에서 조건부로 `.res` 파일을 생성**하고, `standalone` 모드에서만 `-Xlinker` 플래그를 추가하는 방식이 더 안전하다.

**옵션 B: Swift 바이트 배열로 포함 (대안)**

`.rc` 파일 대신, Swift 측에서 DLL을 `ByteArray`로 컴파일 타임에 포함시키고 C 쪽에 전달한다.

```swift
// KalsaePlatformWindows/StandaloneLoaderDLL.swift
// (빌드 스크립트가 생성)
internal let webView2LoaderDLL: [UInt8] = [
    0x4D, 0x5A, 0x90, 0x00, // MZ header...
    // ... WebView2Loader.dll의 전체 바이트
]
```

이 방식은 SwiftPM의 `.rc` 미지원 문제를 회피하지만, DLL 크기(~1MB)만큼 Swift 소스가 커지고 빌드 스크립트가 필요하다.

**권장: 옵션 A (rc.exe + .res 파일)** — Win32 표준 방식이며, DLL 업데이트 시 .rc 파일만 재컴파일하면 된다.

### 3.4 `KSPackager.swift` — `--standalone` 모드

**`KSPackager.Options`에 `standalone` 플래그 추가:**

```swift
public struct Options: Sendable {
    // ... 기존 필드 ...
    public var standalone: Bool  // 새 필드

    public init(
        // ... 기존 파라미터 ...
        standalone: Bool = false
    ) {
        // ... 기존 초기화 ...
        self.standalone = standalone
    }
}
```

**`copyLoaderDLL` 수정 — standalone 모드에서 DLL 복사 생략:**

```swift
private static func copyLoaderDLL(
    opts: Options,
    warnings: inout [String]
) {
    // standalone 모드에서는 DLL이 exe에 내장되어 있으므로 복사 불필요
    guard !opts.standalone else { return }

    // ... 기존 DLL 복사 로직 ...
}
```

**`KSPackager.run()` 수정 — standalone 모드에서 manifest 처리:**

standalone 모드에서도 SxS manifest는 여전히 필요하다 (DPI awareness, Common Controls v6). manifest는 exe에 RT_MANIFEST 리소스로 내장하거나, 외부 파일로 유지한다.

```swift
// standalone 모드에서는 manifest도 exe 리소스로 내장해야 함
// (현재는 외부 .manifest 파일)
// → 별도의 .res 파일로 컴파일하거나, mt.exe(Microsoft Manifest Tool)로 내장
```

### 5. `BuildCommand.swift` — `--standalone` 플래그

```swift
@Flag(
    name: .long,
    help: "Produce a standalone single-file executable by embedding WebView2Loader.dll and frontend assets."
)
var standalone: Bool = false
```

**`runPackageWindows`에 `standalone` 전달:**

```swift
let opts = KSPackager.Options(
    // ... 기존 ...
    standalone: standalone)
```

**빌드 전 단계 (`run` 메서드):**

standalone 모드에서는 `swift build` 전에:
1. `rc.exe`로 `.res` 파일 생성 (WebView2Loader.dll + manifest)
2. `unsafeFlags`로 `.res` 파일 링크

```swift
if standalone {
    #if os(Windows)
        try compileResource(arch: arch, cwd: cwd, config: configuration)
    #endif
}
```

### 3.6 프론트엔드 에셋 내장 (Phase 2)

프론트엔드 에셋 내장은 Phase 1(WebView2Loader.dll 내장) 이후에 진행한다.

**방식:** `kalsae build` 시 프론트엔드 dist 파일들을 zip으로 압축해 Swift 소스에 `ByteArray`로 포함시키고, 런타임에 메모리에서 압축을 풀어 `KSAssetResolver`가 서빙하도록 한다.

```swift
// KalsaePlatformWindows/StandaloneAssets.swift
// (kalsae build --standalone 시 생성)
internal let bundledAssets: [String: [UInt8]] = [
    "index.html": [...],
    "assets/app.js": [...],
    // ...
]
```

또는 zip 압축:

```swift
internal let bundledAssetsZip: [UInt8] = [...]  // deflate 압축된 zip
```

`KSAssetResolver`는 `--standalone` 모드에서 내장 데이터를 우선 조회하고, 없으면 디스크에서 읽는다.

---

## 4. 마이그레이션 / 호환성

### 4.1 일반 모드 vs standalone 모드

| 항목 | 일반 모드 (`kalsae build`) | Standalone 모드 (`kalsae build --standalone`) |
|------|---------------------------|----------------------------------------------|
| WebView2Loader.dll | 외부 파일로 복사 | exe에 내장 (임시 파일 추출) |
| 프론트엔드 에셋 | 외부 `Resources/` 디렉터리 | exe에 내장 (Phase 2) |
| SxS manifest | 외부 `.manifest` 파일 | exe에 RT_MANIFEST로 내장 |
| 출력 구조 | `dist/<App>-<ver>-<arch>/` 디렉터리 | 단일 `.exe` 파일 |
| WebView2Loader.dll 복사 | `stageLoaderDLL()`로 staging | 불필요 |

### 4.2 기존 프로젝트 영향

- `--standalone`은 새 플래그로, 기존 `kalsae build` 동작은 변경되지 않음
- standalone 모드로 빌드된 exe는 일반 모드와 동일한 API/런타임 동작
- 단, `%TEMP%`에 임시 파일이 생성되므로, 일부 보안 정책이严格的 환경에서는 주의 필요

---

## 5. 구현 단계 (Phases)

### Phase 1: WebView2Loader.dll 내장 (예상: 2-3일)

| 단계 | 작업 | 파일 |
|------|------|------|
| 1.1 | `kswv2_loader.cpp`에 `TryLoadFromResource()` 추가 | `Sources/CKalsaeWV2/src/kswv2_loader.cpp` |
| 1.2 | 아키텍처별 `.rc` 파일 생성 | `Sources/CKalsaeWV2/src/loader_resource.*.rc` |
| 1.3 | `BuildCommand.swift`에 `--standalone` 플래그 추가 | `Sources/KalsaeCLI/Commands/BuildCommand.swift` |
| 1.4 | `KSPackager.Options`에 `standalone` 필드 추가 | `Sources/KalsaeCLI/Support/Packager.swift` |
| 1.5 | `copyLoaderDLL`에서 standalone 모드 처리 | `Sources/KalsaeCLI/Support/Packager.swift` |
| 1.6 | 빌드 전 `rc.exe` 호출 로직 구현 | `Sources/KalsaeCLI/Commands/BuildCommand.swift` |
| 1.7 | SxS manifest를 exe 리소스로 내장 (mt.exe 또는 .res) | `Sources/KalsaeCLI/Commands/BuildCommand.swift` |
| 1.8 | `stageLoaderDLL`에서 standalone 모드 스킵 | `Sources/KalsaeCLI/Support/WebView2Provisioner.swift` |

### Phase 2: 프론트엔드 에셋 내장 (예상: 2-3일)

| 단계 | 작업 | 파일 |
|------|------|------|
| 2.1 | 프론트엔드 dist를 Swift ByteArray로 변환하는 스크립트 | `Scripts/embed-assets.swift` |
| 2.2 | `KSAssetResolver`에 내장 데이터 조회 로직 추가 | `Sources/KalsaePlatformWindows/` |
| 2.3 | `BuildCommand.swift`에서 에셋 내장 단계 추가 | `Sources/KalsaeCLI/Commands/BuildCommand.swift` |
| 2.4 | zip 압축 방식 평가 및 구현 | `Sources/KalsaeCLI/Support/` |

### Phase 3: 테스트 및 문서화 (예상: 1일)

| 단계 | 작업 |
|------|------|
| 3.1 | standalone 모드 통합 테스트 (Windows) |
| 3.2 | 비-standalone 모드 회귀 테스트 |
| 3.3 | CLI 도움말 및 문서 업데이트 |

---

## 6. 고려되지 않은 사항 / 향후 과제

- **macOS/Linux**: macOS는 WKWebView가 내장되어 WebView2Loader.dll이 불필요. Linux는 WebKitGTK가 시스템 패키지로 제공. `--standalone`은 Windows 전용.
- **ARM64 크로스 컴파일**: Windows ARM64용 standalone 빌드는 ARM64 WebView2Loader.dll이 필요. SwiftPM의 ARM64 크로스 컴파일 지원이 선행되어야 함.
- **코드 사이닝**: standalone exe에 코드 사이닝 적용 시, 내장 리소스가 서명에 영향을 주지 않는지 확인 필요.
- **바이러스 백신**: 임시 파일 덤프 방식이 일부 AV에서 의심스러운 동작으로 탐지될 가능성. Wails도 동일한 이슈를 겪고 있음.
- **완전한 단일 exe**: PE 메모리 로더를 구현하면 `%TEMP%` 파일 없이 진정한 단일 exe가 가능하나, 현재 Phase 1 범위를 벗어남.

---

## 7. 참고

- Wails v2 소스코드: `embed.go` — `//go:embed`로 WebView2Loader.dll 내장
- MemoryModule (https://github.com/fancycode/MemoryModule) — PE 메모리 로더 오픈소스 구현
- WebView2LoaderStatic.lib 정적 링크 — Microsoft.Web.WebView2 NuGet 패키지의 Static 옵션
