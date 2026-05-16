# RFC-003 — Linux Embedded Config & Standalone Single-Binary

| 항목 | 내용 |
|------|------|
| 상태 | 초안 (Draft) |
| 날짜 | 2026-05-16 |
| 영향 범위 | `Sources/KalsaePlatformLinux/` (신규 `KSEmbeddedResourceLoader`) · `Sources/KalsaeCLI/` (`BuildCommand` Linux 분기 + 신규 `ELFSectionEmbedder`) · 빌드 산출물 (단일 ELF 실행파일) |
| 관련 | Phase 3.3 로드맵, [RFC-002](RFC-002-linux-multi-window.md) (별개), Windows standalone 후처리 ([KSEmbeddedConfigLoader.swift](../../Sources/KalsaePlatformWindows/KSEmbeddedConfigLoader.swift)) |

---

## 1. 동기 (Motivation)

Windows 는 `kalsae build --standalone` 후처리가 `kalsae.json` / `ks-runtime.json` /
프론트엔드 ZIP 을 EXE 의 PE `RT_RCDATA` 섹션에 임베드해 **외부 파일 0 개의 단일
실행파일** 부팅을 지원한다.

런타임 측 진입점:
[KSEmbeddedResourceLoader](../../Sources/KalsaePlatformWindows/KSEmbeddedConfigLoader.swift) L15
- `loadEmbeddedResource(named: "KSAS_CONFIG_JSON")` → `kalsae.json`
- `loadEmbeddedResource(named: "KSAS_RUNTIME_JSON")` → runtime 메타
- `loadEmbeddedResource(named: "KSAS_ASSETS_ZIP")` → 프론트엔드 자산 zip
  (`Sources/KalsaePlatformWindows/WebView2/KSWebView2Runtime.swift` L112)

빌드 측: `BuildCommand --standalone` 이 ResourceHacker / rcedit 를 호출해 PE 리소스
주입. 호스트 Linux 에는 동등한 경로가 없어 `kalsae build` 가 항상 외부 파일
번들 (실행파일 + `kalsae.json` + `frontend/` 디렉토리) 만 산출한다.

목표: **Linux 도 단일 ELF 실행파일로 부팅** 가능하게 한다. PE `RT_RCDATA` 의
Linux 대응은 표준 `objcopy --add-section <section>=<file>` 또는 빌드 시 어셈블리
스텁을 통한 ELF 섹션 임베딩이다.

_🇰🇷 Windows 의 standalone(단일 EXE) 동작을 Linux 도 갖추도록 ELF 섹션 기반 임베딩으로 이식._

---

## 2. 목표 / 비목표

### 목표
- `kalsae build --standalone` 이 Linux 호스트에서도 동작해 **단일 ELF 실행파일**을
  생성.
- 런타임 측 `KSEmbeddedResourceLoader` API 를 **Linux 에서도 동일 시그니처로 노출**
  (`loadEmbeddedResource(named:) -> Data?`). 호출자 ([WebView2Callbacks.swift](../../Sources/KalsaePlatformWindows/WebView2/WebView2Callbacks.swift) L482,
  [KSWebView2Runtime.swift](../../Sources/KalsaePlatformWindows/WebView2/KSWebView2Runtime.swift) L112/130/183,
  [KSApp+Boot.swift](../../Sources/Kalsae/KSApp+Boot.swift)) 가 OS 무관하게 사용.
- 리소스 이름 prefix `KSAS_` 그대로 유지 → ELF 섹션 이름은 `.ksas.config_json` 등
  점·소문자·언더스코어 규칙으로 매핑.
- `objcopy` 의존: GNU binutils 의 표준 도구. 추가 외부 의존성 도입 없음.

### 비목표
- macOS 단일 `.app` 임베디드 — 이미 `Bundle.module.url(...)` 로 충분하며 `.app`
  자체가 단일 배포 단위.
- iOS / Android — `Bundle.main` + APK assets 가 동일 역할.
- 압축/암호화 — 임베디드 페이로드는 압축되지 않은 raw 바이트 (자산 zip 은 이미
  zip 이라 이중 압축 불필요). 추후 RFC 에서 다룸.
- `--standalone` 의 LGPL 동적 링크 정책 변화 — RFC 본문 §6 참조 (불변).

---

## 3. 채택 안

### 3.1 ELF 섹션 임베딩 (빌드 측)

`objcopy --add-section <section>=<file> --set-section-flags <section>=noload,readonly`
는 GNU/LLVM binutils 표준이며 `apt install binutils` 로 보장된다. 빌드 후처리
파이프라인:

```text
[1] swift build -c release --product <App>            # ELF 생성
[2] objcopy --add-section .ksas.config_json=kalsae.json \
            --set-section-flags .ksas.config_json=noload,readonly \
            <App> <App>
[3] objcopy --add-section .ksas.assets_zip=frontend.zip ...
[4] objcopy --add-section .ksas.runtime_json=ks-runtime.json ...
[5] strip --strip-unneeded <App>   # optional
```

리소스 이름 매핑 규칙:

| Windows PE RCDATA | Linux ELF section |
|-------------------|--------------------|
| `KSAS_CONFIG_JSON` | `.ksas.config_json` |
| `KSAS_RUNTIME_JSON` | `.ksas.runtime_json` |
| `KSAS_ASSETS_ZIP` | `.ksas.assets_zip` |

규칙: lowercase, `_` → `_` 유지, `KSAS_` prefix → `.ksas.` prefix. 섹션 이름은
ELF `SHT_NOTE` 가 아닌 일반 `SHT_PROGBITS` + `SHF_ALLOC` off (`noload`) 로 만들어
런타임에 메모리 매핑 비용 없이 디스크에서만 조회한다 (자산 zip 이 크기 때문).

### 3.2 런타임 측 — Linux `KSEmbeddedResourceLoader`

신규 파일: `Sources/KalsaePlatformLinux/KSEmbeddedConfigLoader.swift`

ELF 섹션 조회는 다음 두 방식 중 택1:

- **(a) `dl_iterate_phdr` + ELF 헤더 직접 파싱** — `libc` 만으로 가능. self
  `/proc/self/exe` 를 mmap 하지 않고 in-process 의 program headers 를 순회.
- **(b) `/proc/self/exe` 를 열어 ELF section header table 파싱** — 단순. 표준
  ELF 레이아웃 가정.

채택: **(b)**. 코드 단순성과 디버깅 용이성. 성능은 부팅 1회 호출이라 무시 가능.

```swift
#if os(Linux)
    public import Foundation

    public enum KSEmbeddedResourceLoader {
        /// `.ksas.<name_lowercase>` 섹션의 바이트를 반환. 없으면 nil.
        /// Windows 의 `loadEmbeddedResource(named: "KSAS_FOO")` 와 동일 의미.
        public static func loadEmbeddedResource(named resourceName: String) -> Data? {
            let sectionName = mapResourceNameToSection(resourceName)
            return readELFSection(named: sectionName)
        }

        // KSAS_CONFIG_JSON → .ksas.config_json
        private static func mapResourceNameToSection(_ name: String) -> String {
            let stripped = name.hasPrefix("KSAS_") ? String(name.dropFirst(5)) : name
            return ".ksas." + stripped.lowercased()
        }

        private static func readELFSection(named name: String) -> Data? {
            // 1. /proc/self/exe 를 open + mmap (PROT_READ)
            // 2. ELF64 header 검증 (e_ident magic, e_type ET_EXEC|ET_DYN)
            // 3. section header table (e_shoff, e_shnum, e_shentsize) 순회
            // 4. .shstrtab (e_shstrndx) 에서 섹션 이름 lookup
            // 5. 매칭되는 SHT_PROGBITS 의 sh_offset + sh_size 만큼 Data 로 복사
            // 6. munmap + close
            // 실패 시 nil
        }
    }

    public enum KSEmbeddedConfigLoader {
        public static func loadEmbeddedConfigData() -> Data? {
            KSEmbeddedResourceLoader.loadEmbeddedResource(named: "KSAS_CONFIG_JSON")
        }
    }
#endif
```

플랫폼 분기:

- `Sources/Kalsae/KSApp+Boot.swift` 의 `loadEmbeddedConfigData` 호출 지점은
  이미 Windows-only `#if` 로 둘러싸여 있음. **이 가드를 `#if os(Windows) || os(Linux)`
  로 확장**.
- 호출자 4곳 ([WebView2Callbacks.swift](../../Sources/KalsaePlatformWindows/WebView2/WebView2Callbacks.swift) L482, [KSWebView2Runtime.swift](../../Sources/KalsaePlatformWindows/WebView2/KSWebView2Runtime.swift) L112/130/183) 은 **Windows
  PAL 내부** 이므로 변경 불필요. Linux PAL 의 대응 진입점 (자산 zip 사용처) 만
  추가 작업이 필요한지 §3.4 에서 검토.

### 3.3 BuildCommand 후처리 (Linux 분기)

[Sources/KalsaeCLI/Commands/BuildCommand.swift](../../Sources/KalsaeCLI/Commands/BuildCommand.swift) L48 의
`--standalone` 분기를 Linux 에서도 활성화:

- 신규 Support 파일: `Sources/KalsaeCLI/Support/ELFSectionEmbedder.swift`
  - `static func embed(executable: URL, sections: [(name: String, payload: URL)]) throws(KSError)`
  - 내부: `Process` 로 `objcopy` 호출. PATH 에 없으면 `KSError(.toolMissing,
    "objcopy not found; install GNU binutils (apt install binutils)")`.
  - `--allow-fallback` 시 경고 후 일반 빌드 산출물로 폴백 (Windows 와 동일 시맨틱).
- `BuildCommand` Linux 호스트 분기에서 다음 페이로드 임베드:
  - `kalsae.json` → `.ksas.config_json` (sanitized: §3.5)
  - `ks-runtime.json` → `.ksas.runtime_json`
  - `frontend.zip` → `.ksas.assets_zip` ([AssetZipBuilder.swift](../../Sources/KalsaeCLI/Support/AssetZipBuilder.swift) 재사용)
- 산출물: `dist/linux-<App>-<ver>-standalone/<App>` (단일 ELF). NOTICE 파일은
  여전히 함께 동봉 (AGENTS.md §9 LGPL 정책 — 동적 링크 + 시스템 패키지 의존
  변동 없음).

### 3.4 자산 zip 의 Linux 런타임 사용처

Windows 는 [KSWebView2Runtime.swift](../../Sources/KalsaePlatformWindows/WebView2/KSWebView2Runtime.swift) L112 에서 `KSAS_ASSETS_ZIP` 을 풀어
가상 호스트 (`https://app.kalsae/`) 가 응답하도록 한다. Linux 는 동등 위치가
[KSLinuxPlatform.swift](../../Sources/KalsaePlatformLinux/KSLinuxPlatform.swift) 의 `ks://` 스킴 핸들러
(CKalsaeGtk `webkit_web_context_register_uri_scheme` 와 연결된 `on_kb_scheme_request`)
이다.

스킴 핸들러는 현재 `assetRoot` 디렉토리에서 파일을 읽는다. 임베디드 모드에서는:

- 부팅 시 `KSAS_ASSETS_ZIP` 을 `XDG_RUNTIME_DIR/kalsae-<pid>/` 에 전개
  (Windows 의 임시 디렉토리 추출 패턴과 동일).
- `setAssetRoot(<전개경로>)` 호출.
- 프로세스 종료 시 `atexit` 또는 `KSApp` deinit 에서 디렉토리 삭제 (실패해도
  무시 — XDG_RUNTIME_DIR 은 로그아웃 시 정리됨).

이 동작은 Linux PAL 측 [KSLinuxPlatform.swift](../../Sources/KalsaePlatformLinux/KSLinuxPlatform.swift) 의 부팅 경로 (또는 [KSApp+Boot.swift](../../Sources/Kalsae/KSApp+Boot.swift)
의 OS-무관 분기) 에 약 30~50 줄 추가로 처리 가능.

### 3.5 보안 — config 정화 (sanitization)

Windows standalone 경로와 동일하게 적용:
- `kalsae.json` 의 절대경로 / dev-only 키 제거.
- `frontendDist` 경로는 임베드 후 의미 없음 → 빈 문자열로 정규화.
- `security.devtools` 강제 `false` (이미 Windows 동일).

기존 sanitizer ([Sources/KalsaeCLI/Support/](../../Sources/KalsaeCLI/Support/)) 재사용 — Linux 분기에서 동일 함수 호출.

---

## 4. 대안 (Considered Alternatives)

### Option A — `__attribute__((section(".ksas.config_json")))` 정적 임베드

빌드 시 C 컴파일러로 페이로드를 `.o` 로 만들어 링크. 장점: `objcopy` 의존 X.
단점: 페이로드가 컴파일 단위에 묶여야 함 → SwiftPM 빌드 그래프 변경 필요. **거부**.

### Option B — AppImage / Flatpak 만 지원

장점: 표준 단일 배포 단위. 단점: AppImage 는 FUSE 의존, Flatpak 은 sandbox 모델이
달라 LGPL 동적 링크 가정 깨짐. Kalsae 의 "OS 시스템 패키지 동적 링크" 원칙과 충돌.
**비목표로 분리** — AppImage 패키저는 별도 RFC.

### Option C — config 만 임베드, 자산은 항상 외부 디렉토리

장점: 구현 단순. 단점: "단일 실행파일" 약속을 깸. Windows 표면과 비대칭. **거부**.

---

## 5. 마이그레이션·호환성

- 기존 Linux 빌드: `--standalone` 미지정 → 동작 무변경.
- 신규 Linux `--standalone` 빌드: 단일 ELF. 기존 외부 `kalsae.json` 우선
  ([KSApp+Boot.swift](../../Sources/Kalsae/KSApp+Boot.swift) 의 fallback 순서 그대로 — 외부 파일이 있으면 그것을 우선,
  없을 때만 임베디드 폴백).
- Windows ↔ Linux: 같은 `KSEmbeddedResourceLoader.loadEmbeddedResource(named:)`
  시그니처 → 호출 코드는 OS 분기 불필요.

---

## 6. LGPL / 보안 정책 영향

- WebKitGTK / GTK / libsoup / libsecret 는 여전히 **동적 링크 + 시스템 패키지
  의존** (AGENTS.md §9). 단일 ELF 안에 `.so` 를 임베드하지 않는다.
- ELF 섹션에 들어가는 것은 Kalsae 자체 자산 (config / runtime / frontend) 뿐.
- `--standalone` 빌드의 라이선스 영향: Kalsae MIT 코드 + 사용자 자산만 임베드 →
  변경 없음.
- 보안: 임베디드 config 는 빌드 시 sanitize (§3.5). 자산은 신뢰된 빌드 경로의
  파일이므로 변조 위협은 빌드 환경 보안에 종속 (Windows 와 동일).

---

## 7. 테스트 계획

신규 테스트:

- `Tests/KalsaeCLITests/ELFSectionEmbedderTests.swift`
  - `@Test func embed_addsSectionToELF()` — 임시 ELF (또는 hello world 컴파일) 에
    섹션 추가 후 `readelf -S` 로 검증
  - `@Test func embed_missingObjcopy_throwsToolMissing()` — PATH 조작
- `Tests/KalsaePlatformLinuxTests/KSEmbeddedResourceLoaderTests.swift`
  - `@Test func loadEmbeddedResource_returnsNilWhenSectionAbsent()`
  - `@Test func loadEmbeddedResource_decodesSectionPayload()` — 테스트 헬퍼로 자기
    ELF 에 섹션을 임시 추가하기 어려우므로, 별도 fixture 바이너리를 빌드해 테스트.

CI: [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) Linux 잡에 `binutils`
설치 + 새 테스트 실행. macOS / Windows CI 는 영향 없음.

---

## 8. 미해결 질문

- **Q1.** ELF section 최대 크기? `objcopy` 자체 제한은 없으나 매우 큰 자산 zip 의
  경우 부팅 시 추출 비용이 큼. 답: 일단 제한 없음. 실측 후 RFC v2 에서 임계 검토.
- **Q2.** PIE / non-PIE 모두 지원? Swift Linux 빌드는 기본 PIE → ELF `ET_DYN`.
  답: §3.2 (b) 의 파서가 둘 다 처리 (ET_EXEC | ET_DYN).
- **Q3.** `strip` 후에도 섹션 보존? `objcopy --set-section-flags` 의 `noload` +
  `readonly` 면 `strip --strip-unneeded` 는 보존. `strip --strip-all` 은 위험 —
  파이프라인에서 `--strip-unneeded` 만 사용.
- **Q4.** ARM64 (`aarch64-unknown-linux-gnu`) ELF 도 동일 동작? `objcopy` 는
  타깃 아키텍처별 바이너리 (`aarch64-linux-gnu-objcopy`) 가 필요할 수 있음. 답:
  cross-compile 시 toolchain 의 objcopy 사용. BuildCommand 가 환경변수
  `OBJCOPY` 우선 존중.

---

## 9. 구현 순서 (참고)

1. CLI: `ELFSectionEmbedder` 작성 + `objcopy` shell-out 테스트.
2. CLI: `BuildCommand` Linux 호스트 분기 (`--standalone`) 활성화 + sanitize 재사용.
3. PAL: `KSEmbeddedResourceLoader` Linux 구현 (ELF section 파서) + 단위 테스트.
4. PAL: 자산 zip 전개 → `setAssetRoot` Linux 부팅 흐름 통합 (§3.4).
5. Boot: [KSApp+Boot.swift](../../Sources/Kalsae/KSApp+Boot.swift) 의
   `loadEmbeddedConfigData` 가드 확장 (`os(Windows) || os(Linux)`).
6. 통합 테스트: `kalsae build --standalone` Linux 결과 ELF 를 `readelf -S` 로
   검증 + 실행 부팅 (Linux CI 잡).
7. 문서: [README.md](../../README.md) 의 standalone 플랫폼 표 갱신, AGENTS.md §5
   Linux 항목에 standalone 노트 추가.

---

_🇰🇷 Linux 단일 실행파일은 `objcopy --add-section` 으로 ELF 섹션에 config / runtime
/ 자산 zip 을 임베드하고, 런타임은 `/proc/self/exe` 의 section header table 을
파싱해 동일한 `KSEmbeddedResourceLoader.loadEmbeddedResource(named:)` API 로 제공한다.
Windows PE RCDATA 와 시맨틱 동등. 실제 구현은 Linux 호스트 가용 시점에 착수._
