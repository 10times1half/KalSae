# RFC-005 — KalsaeCLI 모듈 코드 품질 검토 보고서 (Code Review)

| 항목 | 내용 |
|------|------|
| 상태 | 초안 (Draft) |
| 날짜 | 2026-05-09 |
| 영향 범위 | `KalsaeCLI` 전 모듈 (Commands 6개, Support 18개, 총 24개 파일, 약 4,500라인) |
| 관련 | `AGENTS.md`, `Shell.swift`, `BuildCommand.swift`, `DevCommand.swift`, `Packager.swift`, `Doctor.swift`, `ResourceSyncManager.swift`, `BindingsGenerator+Visitor.swift` |

---

## 1. 동기 (Motivation)

KalsaeCLI는 Kalsae 프레임워크의 사용자 대면(command-line interface) 모듈로, 프로젝트 스캐폴딩(`new`), 개발 서버 실행(`dev`), 릴리스 빌드(`build`), 환경 진단(`doctor`), 타입스크립트 바인딩 생성(`generate bindings`), 버전 출력(`version`) 등 프레임워크의 모든 개발자 워크플로를 담당한다.

본 문서는 KalsaeCLI 모듈의 **24개 파일, 약 4,500라인**의 Swift 소스 코드를 Swift 6.0 모범 사례, AGENTS.md 코딩 컨벤션, 보안 원칙, 동시성 모델, 플랫폼 호환성 관점에서 엄격히 검토한 결과를 기록한다.

---

## 2. 검토 범위 (Scope)

| 영역 | 파일 수 | 주요 파일 |
|------|---------|-----------|
| CLI Entry | 1 | `KalsaeCLI.swift` |
| Commands | 6 | `BuildCommand.swift`, `DevCommand.swift`, `DoctorCommand.swift`, `GenerateCommand.swift`, `NewCommand.swift`, `VersionCommand.swift` |
| Shell/Process | 1 | `Shell.swift` |
| Build/Package | 6 | `BuildDevPlan.swift`, `BuildTimings.swift`, `Packager.swift`, `PackagerMac.swift`, `PackagerNSIS.swift`, `BundleAnalyzer.swift` |
| Scaffold/Template | 3 | `ProjectTemplate.swift`, `ExternalScaffolder.swift`, `NSISTemplate.swift` |
| Bindings Generator | 5 | `BindingsGenerator.swift`, `+Models.swift`, `+Renderer.swift`, `+TypeMapper.swift`, `+Visitor.swift` |
| Utilities | 6 | `ResourceSyncManager.swift`, `Doctor.swift`, `SigntoolHook.swift`, `StandalonePostProcessor.swift`, `WebView2Provisioner.swift`, `ZipArchiver.swift`, `AssetZipBuilder.swift` |

---

## 3. 심각도 기준 (Severity Definitions)

| 심각도 | 정의 | 조치 시한 |
|--------|------|-----------|
| 🔴 CRITICAL | 컴파일 오류, 런타임 크래시, 데이터 손실, 보안 취약점, 코딩 컨벤션 위반 | 즉시 수정 |
| 🟠 HIGH | 잠재적 버그, 코드 중복, 단일 책임 원칙 위반, 플랫폼 호환성 문제 | 다음 마일스톤 |
| 🟡 MEDIUM | 성능 저하, 유지보수성 저하, 불완전한 오류 처리 | 백로그 |
| 🟢 LOW | 사소한 스타일 문제, 오타, 데드 코드 | 시간 허락 시 |

---

## 4. 상세 검토 결과 (Detailed Findings)

### 4.1 🔴 CRITICAL — 즉시 수정 필요

#### 4.1.1 `Shell.swift` — `public import Foundation` 위치 오류

- **파일**: `Sources/KalsaeCLI/Support/Shell.swift`
- **위치**: 라인 1-3
- **현재 코드**:
  ```swift
  // MARK: - 오류
  public import Foundation

  // MARK: - PATH 조회
  ```
- **문제**: `public import Foundation`이 파일 최상단이 아니라 `// MARK: - 오류` 주석 **다음**에 위치. Swift 6의 `InternalImportsByDefault` 정책 하에서 `public import`는 파일의 첫 번째 유효한 코드여야 의미가 명확함. 다른 모든 KalsaeCLI 파일은 import가 파일 최상단에 위치함.
- **권장 조치**: `public import Foundation`을 파일 최상단으로 이동. MARK 주석은 import 아래에 배치.
- **참고**: AGENTS.md §4 "SwiftPM specifics" — `public import Foundation` (etc.) required for files that expose public types.

#### 4.1.2 `BuildCommand.swift` — Import 블록 내 doc comment 삽입

- **파일**: `Sources/KalsaeCLI/Commands/BuildCommand.swift`
- **위치**: 라인 1-5
- **현재 코드**:
  ```swift
  import ArgumentParser
  import Foundation
  import KalsaeCLICore
  /// `kalsae build` — 릴리스 ...
  import KalsaeCore
  ```
- **문제**: `import KalsaeCLICore`와 `import KalsaeCore` 사이에 doc comment가 끼어있고, `import KalsaeCore`가 doc comment **다음**에 위치. 다른 모든 Command 파일은 import가 연속된 블록으로 정리되어 있음.
- **권장 조치**: doc comment를 import 블록 위로 이동하거나, import 블록을 연속되게 정리.

#### 4.1.3 `DevCommand.swift` — 동일한 Import 패턴 문제

- **파일**: `Sources/KalsaeCLI/Commands/DevCommand.swift`
- **위치**: 라인 1-5
- **현재 코드**:
  ```swift
  import ArgumentParser
  import Foundation
  import KalsaeCLICore
  /// `Kalsae dev` — 개발 모드로 ...
  import KalsaeCore
  ```
- **문제**: BuildCommand.swift와 동일한 import 순서 문제.
- **권장 조치**: 동일.

#### 4.1.4 `Shell.swift` — `findExecutable` public 함수 doc comment 누락

- **파일**: `Sources/KalsaeCLI/Support/Shell.swift`
- **위치**: 라인 33 (`public func findExecutable(named name: String) -> URL?`)
- **문제**: `public` 함수임에도 doc comment(`///`)가 없음. AGENTS.md §4는 "Doc comments on public API are required"라고 명시.
- **권장 조치**: `///` doc comment 추가.

---

### 4.2 🟠 HIGH — 리팩토링 권장

#### 4.2.1 `BuildCommand.swift` — `run()` 메서드 단일 책임 원칙 위반

- **파일**: `Sources/KalsaeCLI/Commands/BuildCommand.swift`
- **위치**: 라인 161-316 (약 155줄)
- **문제**: `run()` 메서드가 serial build path(~35줄)와 parallel build path(~80줄)를 모두 포함하며, 두 경로 간 코드 중복이 심각함:
  - `timer.measure(...)` 패턴 중복
  - `validateWebView2Preconditions` 중복 호출
  - `syncFrontendResourcesIfNeeded` 중복 호출
  - `renameOutputBinaryIfNeeded` 중복 호출
  - `KSWebView2Provisioner.stageLoaderDLL` 중복 호출
- **권장 조치**: `runSerial()` / `runParallel()`로 메서드 분리, 또는 `BuildStrategy` 프로토콜 도입.

#### 4.2.2 `BuildCommand.swift` — 조건부 컴파일로 인한 코드 단절

- **파일**: `Sources/KalsaeCLI/Commands/BuildCommand.swift`
- **위치**: 라인 394-510 (`runPackageWindows`), 532-587 (`runPackageMacOS`)
- **문제**: `#if os(Windows)` / `#if os(macOS)`로 전체 메서드가 감싸져 있어:
  - 컴파일되지 않는 플랫폼의 코드를 정적 분석 도구가 검사 불가
  - `#else` 분기의 fallback 메시지(`print("⚠ Packaging is not supported...")`)가 중복
  - 플랫폼 추가 시 메서드 중복 증가
- **권장 조치**: 프로토콜 기반 전략 패턴(`KSPackagerStrategy`) 도입 검토.

#### 4.2.3 `Packager.swift` — `Fingerprint` 하위호환성 문제

- **파일**: `Sources/KalsaeCLI/Support/Packager.swift`
- **위치**: 라인 731-736
- **현재 코드**:
  ```swift
  var standalone: Bool = false
  var installMode: String = ""
  var stripSourceMaps: Bool = false
  var stripExtensions: [String] = []
  ```
- **문제**: 새 필드가 추가될 때마다 기본값이 `false`/`""`/`[]`이므로, 이전 버전 CLI가 쓴 fingerprint와 비교 시 항상 mismatch → 항상 full rebuild 발생. 이는 RFC-002 §3.1의 incremental 빌드 의도와 반함.
- **권장 조치**: 새 필드를 `Optional`로 선언하거나, `Equatable` 구현에서 새 필드를 제외하는 전략 고려.

#### 4.2.4 `Packager.swift` — `retryingTransient` 플랫폼 의존성 문제

- **파일**: `Sources/KalsaeCLI/Support/Packager.swift`
- **위치**: 라인 645-667
- **문제**: `retryingTransient` 함수가 `#if os(Windows)`로 감싸져 있지만, `safeCopy()`가 항상 이 함수를 호출함. non-Windows에서는 `isTransientFileError` 함수가 정의되지 않아(`#if os(Windows)` 내부에 있음) 향후 Windows 전용 코드 추가 시 컴파일 에러 발생 가능.
- **권장 조치**: `retryingTransient` 자체를 `#if os(Windows)`로 감싸고, non-Windows용 stub 제공.

#### 4.2.5 `Doctor.swift` — `captureVersion()`의 Process 생성 중복

- **파일**: `Sources/KalsaeCLI/Support/Doctor.swift`
- **위치**: 라인 233-274
- **문제**: `captureVersion()`이 `Shell.swift`의 `shell()`/`spawn()`을 재사용하지 않고 자체적으로 `Process` + `Pipe`를 구성. Windows `.cmd`/`.bat` 처리 로직이 `Shell.swift`의 `makeProcess()`와 중복됨.
- **권장 조치**: `Shell.swift`에 `captureOutput(command:arguments:)` 유틸리티를 추가하여 중복 제거.

#### 4.2.6 `ResourceSyncManager.swift` — `relativize()` 경로 처리 버그

- **파일**: `Sources/KalsaeCLI/Support/ResourceSyncManager.swift`
- **위치**: 라인 262-266
- **현재 코드**:
  ```swift
  private static func relativize(_ path: String, base: String) -> String {
      return path.replacingOccurrences(of: base, with: "")
          .trimmingCharacters(in: CharacterSet(charactersIn: "\\/"))
          .replacingOccurrences(of: "\\", with: "/")
  }
  ```
- **문제**: `base`가 `path` 내에 여러 번 나타나거나, `base`가 다른 경로의 prefix와 우연히 일치하는 경우 잘못 동작. 예: `base="/a"`, `path="/a/b/a/c"`면 `"/b/a/c"`가 아닌 `"/b/c"`가 됨.
- **권장 조치**: `NSString.pathComponents` 기반의 정확한 relativize 구현으로 교체.

---

### 4.3 🟡 MEDIUM — 개선 권장

#### 4.3.1 `BuildCommand.swift` — `parseInstallMode()` 과도한 정규화

- **파일**: `Sources/KalsaeCLI/Commands/BuildCommand.swift`
- **위치**: 라인 512-530
- **현재 코드**:
  ```swift
  let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "")
      .lowercased()
  ```
- **문제**: `"down-load"`나 `"em-bed-boot-strap-per"` 같은 오타도 허용. 사용자 경험 측면에서 관대한 것은 장점일 수 있으나, 예상치 못한 값이 매칭될 위험.
- **권장 조치**: 허용할 변형을 명시적으로 열거하거나, `ExpressibleByArgument` 준수 고려.

#### 4.3.2 `DevCommand.swift` — `@unchecked Sendable` 사용

- **파일**: `Sources/KalsaeCLI/Commands/DevCommand.swift`
- **위치**: 라인 304-327
- **현재 코드**:
  ```swift
  final class PingResult: @unchecked Sendable {
      var ok: Bool = false
  }
  ```
- **문제**: `@unchecked Sendable`은 데이터 경쟁 가능성을 컴파일러가 검증하지 않음. `ok` 프로퍼티가 `URLSession` completion handler와 메인 스레드 사이에서 동기화 없이 접근됨.
- **권장 조치**: `Actor`로 변경하거나, `withCheckedContinuation` 사용.

#### 4.3.3 `DevCommand.swift` — `watchFingerprint()` 비효율적 폴링

- **파일**: `Sources/KalsaeCLI/Commands/DevCommand.swift`
- **위치**: 라인 266-302
- **문제**: `watchInterval` 기본값이 1초이므로, 1초마다 전체 Sources 트리를 `FileManager.enumerator`로 스캔. 프로젝트가 커질수록 CPU/IO 부하 증가.
- **권장 조치**: `FSEvents`(macOS) / `ReadDirectoryChangesW`(Windows) 기반의 네이티브 파일 알림 도입 검토.

#### 4.3.4 `Packager.swift` — `rewritePackagedConfig()` JSONSerialization 사용

- **파일**: `Sources/KalsaeCLI/Support/Packager.swift`
- **위치**: 라인 404-434
- **문제**: `Codable` 모델(`KSConfig`)이 이미 있는데, 패키징된 config 재작성에 `JSONSerialization`을 사용. 미래 필드 보존을 위한 의도된 선택이지만, `KSConfig`의 스키마 변경 시 `rewritePackagedConfig`가 동기화되지 않을 위험.
- **권장 조치**: `KSConfig`에 `mutating` rewrite 메서드를 추가하거나, 최소한 단위 테스트에서 스키마 동기화 검증.

#### 4.3.5 `ProjectTemplate.swift` — `substitute()` 다중 문자열 치환 비효율

- **파일**: `Sources/KalsaeCLI/Support/ProjectTemplate.swift`
- **위치**: 라인 242-258
- **문제**: `substitute()`가 10개의 `replacingOccurrences(of:with:)`를 체이닝. O(n*m) 성능. 템플릿 파일이 커지면 각 치환마다 전체 문자열을 순회.
- **권장 조치**: 단일 패스 치환기 구현 또는 `NSRegularExpression` 기반 템플릿 엔진 도입.

#### 4.3.6 `BindingsGenerator+Visitor.swift` — 한글 오타

- **파일**: `Sources/KalsaeCLI/Support/BindingsGenerator+Visitor.swift`
- **위치**: 라인 8
- **현재 코드**: `/// 이 방문자는 의도적으로 너그럽rd게 설계되어 있다:`
- **문제**: "너그럽게"의 오타 (`rd`가 잘못 삽입됨).
- **권장 조치**: "너그럽게"로 수정.

---

### 4.4 🟢 LOW — 사소한 개선

#### 4.4.1 `Shell.swift` — 빈 MARK 섹션

- **파일**: `Sources/KalsaeCLI/Support/Shell.swift`
- **위치**: 라인 1-8
- **문제**: `// MARK: - 오류`와 `// MARK: - PATH 조회` 사이에 실제 코드가 없거나, 주석과 실제 코드 위치가 불일치.
- **권장 조치**: MARK 구분선을 실제 코드 섹션 앞으로 이동.

#### 4.4.2 `BuildCommand.swift` — `AppInfo.frontendDist` 데드 코드

- **파일**: `Sources/KalsaeCLI/Commands/BuildCommand.swift`
- **위치**: 라인 589-595
- **현재 코드**:
  ```swift
  private struct AppInfo {
      let appName: String
      let version: String
      let identifier: String
      let frontendDist: String  // ← 사용되지 않음
      let executableName: String
  }
  ```
- **문제**: `frontendDist`가 `parseAppInfo()`에서 설정되지만(`config.build.frontendDist`), `AppInfo`를 사용하는 모든 곳에서 참조되지 않음.
- **권장 조치**: 데드 코드 제거.

#### 4.4.3 `Packager.swift` — `copyTree()`의 불필요한 `deletingLastPathComponent()`

- **파일**: `Sources/KalsaeCLI/Support/Packager.swift`
- **위치**: 라인 686-695
- **문제**: `copyTree()`에서 `dst.deletingLastPathComponent()`가 `dst`가 단일 경로 컴포넌트일 때 의도와 다를 수 있음.
- **권장 조치**: 부모 디렉터리 생성 로직 검토 및 단순화.

#### 4.4.4 `Doctor.swift` — `.git/config` 직접 읽기

- **파일**: `Sources/KalsaeCLI/Support/Doctor.swift`
- **위치**: 라인 409-421
- **문제**: `checkSwiftSyntaxCache()`가 `.git/config` 파일을 직접 읽어 원격 URL 검증. `.git` 디렉터리 구조는 Git 내부 구현 상세.
- **권장 조치**: `git remote get-url` 명령어 사용으로 변경.

---

## 5. 종합 평가 (Overall Assessment)

### 5.1 강점 (Strengths)

| 영역 | 평가 |
|------|------|
| **모듈 구조** | Commands/Support 분리가 명확하고, 각 파일의 책임이 잘 정의됨 |
| **Swift 6 준수** | `public import`, `InternalImportsByDefault`, typed throws 등 Swift 6 모범 사례를 대부분 잘 지킴 |
| **오류 처리** | `ValidationError` 일관된 사용, typed throws 패턴(`throws(KSError)`) 우수 |
| **플랫폼 대응** | `#if os(Windows/macOS/Linux)` 적절히 사용, 각 플랫폼별 PAL 구현 완비 |
| **테스트 용이성** | `FileManager` 주입, `skipExternalChecks` 옵션, `preserved` 파라미터 등 의존성 주입 패턴 우수 |
| **보안** | 셸 인젝션 방지(Process arguments 사용, 문자열 보간 지양), 경로 인용 처리 우수 |
| **점진적 빌드** | Fingerprint 기반 incremental rebuild, size+mtime 비교 증분 sync 등 성능 최적화 고려 |

### 5.2 개선 기회 (Opportunities)

| 영역 | 평가 |
|------|------|
| **import 정리** | 3개 파일에서 import 순서/위치 일관성 부족 (CRITICAL) |
| **메서드 크기** | `BuildCommand.run()` 155줄 — 단일 책임 원칙 위반 (HIGH) |
| **코드 중복** | Serial/Parallel build path, Windows/macOS packaging, Shell/Doctor Process 생성 (HIGH) |
| **하위호환성** | `Fingerprint` 새 필드 추가 시 항상 full rebuild (HIGH) |
| **동시성** | `@unchecked Sendable` 사용, blocking I/O (MEDIUM) |
| **성능** | 1초 간격 전체 디렉터리 폴링, 다중 문자열 치환 (MEDIUM) |

### 5.3 파일별 품질 점수

| 파일 | 라인 수 | 심각도별 이슈 수 | 종합 평가 |
|------|---------|-----------------|-----------|
| `KalsaeCLI.swift` | 20 | 0 | ✅ 우수 |
| `BuildCommand.swift` | 739 | 🔴1 🟠2 🟡1 🟢1 | ⚠️ 개선 필요 |
| `DevCommand.swift` | 390 | 🔴1 🟡2 | ⚠️ 개선 필요 |
| `DoctorCommand.swift` | 99 | 0 | ✅ 우수 |
| `GenerateCommand.swift` | 76 | 0 | ✅ 우수 |
| `NewCommand.swift` | 414 | 0 | ✅ 우수 |
| `VersionCommand.swift` | 29 | 0 | ✅ 우수 |
| `Shell.swift` | 176 | 🔴2 🟢1 | ⚠️ 개선 필요 |
| `Packager.swift` | 764 | 🟠2 🟡1 🟢1 | ⚠️ 개선 필요 |
| `PackagerMac.swift` | 265 | 0 | ✅ 우수 |
| `PackagerNSIS.swift` | 64 | 0 | ✅ 우수 |
| `BuildDevPlan.swift` | 175 | 0 | ✅ 우수 |
| `BuildTimings.swift` | 103 | 0 | ✅ 우수 |
| `BundleAnalyzer.swift` | 204 | 0 | ✅ 우수 |
| `ResourceSyncManager.swift` | 267 | 🟠1 | ⚠️ 개선 필요 |
| `ProjectTemplate.swift` | 293 | 🟡1 | ✅ 양호 |
| `Doctor.swift` | 424 | 🟠1 🟢1 | ✅ 양호 |
| `ExternalScaffolder.swift` | 194 | 0 | ✅ 우수 |
| `NSISTemplate.swift` | 141 | 0 | ✅ 우수 |
| `SigntoolHook.swift` | 39 | 0 | ✅ 우수 |
| `StandalonePostProcessor.swift` | 220 | 0 | ✅ 우수 |
| `WebView2Provisioner.swift` | 294 | 0 | ✅ 우수 |
| `ZipArchiver.swift` | 194 | 0 | ✅ 우수 |
| `AssetZipBuilder.swift` | 79 | 0 | ✅ 우수 |
| `BindingsGenerator.swift` | 101 | 0 | ✅ 우수 |
| `BindingsGenerator+Models.swift` | 49 | 0 | ✅ 우수 |
| `BindingsGenerator+Renderer.swift` | 117 | 0 | ✅ 우수 |
| `BindingsGenerator+TypeMapper.swift` | 92 | 0 | ✅ 우수 |
| `BindingsGenerator+Visitor.swift` | 168 | 🟡1 | ✅ 양호 |

---

## 6. 권장 조치 우선순위 (Recommended Action Items)

### Phase 1 — 즉시 (Immediate)

| # | 이슈 | 파일 | 난이도 | 예상 작업량 |
|---|------|------|--------|------------|
| 1 | `public import Foundation` 위치 수정 | `Shell.swift` | 하 | 1분 |
| 2 | Import 블록 doc comment 정리 | `BuildCommand.swift`, `DevCommand.swift` | 하 | 2분 |
| 3 | `findExecutable` doc comment 추가 | `Shell.swift` | 하 | 1분 |
| 4 | `BindingsGenerator+Visitor.swift` 오타 수정 | `BindingsGenerator+Visitor.swift` | 하 | 1분 |

### Phase 2 — 단기 (Short-term)

| # | 이슈 | 파일 | 난이도 | 예상 작업량 |
|---|------|------|--------|------------|
| 5 | `BuildCommand.run()` 메서드 분할 | `BuildCommand.swift` | 중 | 2시간 |
| 6 | `AppInfo.frontendDist` 데드 코드 제거 | `BuildCommand.swift` | 하 | 5분 |
| 7 | `relativize()` 경로 처리 버그 수정 | `ResourceSyncManager.swift` | 중 | 30분 |
| 8 | `@unchecked Sendable` → `withCheckedContinuation` | `DevCommand.swift` | 중 | 30분 |

### Phase 3 — 중기 (Medium-term)

| # | 이슈 | 파일 | 난이도 | 예상 작업량 |
|---|------|------|--------|------------|
| 9 | `Fingerprint` 하위호환성 개선 | `Packager.swift` | 중 | 1시간 |
| 10 | `captureVersion()` 중복 제거 | `Doctor.swift`, `Shell.swift` | 중 | 1시간 |
| 11 | `retryingTransient` 플랫폼 분리 | `Packager.swift` | 하 | 15분 |
| 12 | `parseInstallMode()` 명시적 열거 | `BuildCommand.swift` | 하 | 15분 |

### Phase 4 — 장기 (Long-term)

| # | 이슈 | 파일 | 난이도 | 예상 작업량 |
|---|------|------|--------|------------|
| 13 | 플랫폼별 전략 패턴 도입 | `BuildCommand.swift`, `Packager.swift` | 상 | 4시간 |
| 14 | 네이티브 파일 알림 도입 | `DevCommand.swift` | 상 | 8시간 |
| 15 | 단일 패스 템플릿 치환기 | `ProjectTemplate.swift` | 중 | 2시간 |
| 16 | `rewritePackagedConfig` Codable 동기화 | `Packager.swift` | 중 | 1시간 |

---

## 7. 참고 (References)

- [AGENTS.md](../../AGENTS.md) — 프로젝트 코딩 컨벤션
- [RFC-002: Security Audit](RFC-002-security-audit.md) — 보안 검토 결과
- [RFC-003: KalsaeCore Code Review](RFC-003-kalsaecore-code-review.md) — KalsaeCore 모듈 코드 검토
- [RFC-004: PAL Code Review](RFC-004-pal-code-review.md) — PAL 모듈 코드 검토
- [Swift 6.0 Release Notes](https://www.swift.org/blog/swift-6-0-released/) — Swift 6.0 주요 변경사항
