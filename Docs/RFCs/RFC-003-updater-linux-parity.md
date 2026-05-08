# RFC-003 — KalsaePluginUpdater Linux↔Windows 동등성: 상세 구현 계획

| 항목 | 내용 |
|------|------|
| 상태 | 초안 (Draft) |
| 날짜 | 2026-05-08 |
| 영향 범위 | RFC-001 `KalsaePluginUpdater` 수정 + 신규 모듈/타입 |
| 관련 | RFC-001, Tauri `tauri-plugin-updater`, KalsaePlatformLinux PAL |

---

## 1. 동기(Motivation)

RFC-001은 Linux 설치 흐름을 AppImage 교체만으로 제한하고, 임시 경로에 고정
`/tmp/kalsae-updates/`를 사용하며, deb/rpm 패키지 설치 흐름이 누락되어 있다.
Windows(NSIS/MSI)·macOS(DMG) 대비 Linux 지원이 불완전하다.

Tauri `tauri-plugin-updater`는 Linux에서 AppImage·deb·rpm 세 가지를 모두 지원하며,
pkexec → GUI 비밀번호 다이얼로그 → sudo 폴백 체인으로 권한 상승을 처리한다.
임시 디렉터리는 다단계 폴백 + 랜덤화 + same-device 체크로 보안을 확보한다.

이 RFC는 **RFC-001에 대한 수정 제안**으로, Tauri 방식을 참조 모델로 삼아
Linux 기능을 Windows/macOS와 동등하게 끌어올린다.

> **참고:** Wails에는 내장 업데이터가 없으므로 참조 대상에서 제외한다.

---

## 2. 확정된 결정사항

| # | 항목 | 결정 |
|---|------|------|
| 1 | .deb/.rpm 패키지 지원 | **Tauri 방식 채택**: pkexec → zenity/kdialog → sudo 폴백으로 권한 상승 허용. RFC-001 §2 비목표의 "루트 권한 설치 미지원" 조항을 수정 |
| 2 | Linux 임시 다운로드 경로 | **Tauri 방식 채택**: temp_dir → cache_dir → 부모디렉 다단계 폴백 + 랜덤 서브디렉 생성 + 0700 권한 + same-device 체크 |
| 3 | Taskbar progress 연동 | **Linux no-op 명시**. RFC-001에 플랫폼 노트 추가 |
| 4 | AppImage 교체 후 재실행 | **`Process.launchDetached` 후 `ctx.quit()`** |
| 5 | rpm 지원 범위 | **v1에 포함** (Tauri와 동일). deb/rpm/AppImage 세 가지 모두 v1 범위 |

---

## 3. RFC-001 변경 명세

### 3.1 §2 비목표 수정

**현행** (RFC-001 `Docs/RFCs/RFC-001-updater.md` 46행):
```
- **루트 권한 설치**: per-user 설치 경로(AppData, ~/Applications)만 지원.
```

**변경:**
```
- **루트 권한 설치**: Windows/macOS는 per-user 설치 경로(AppData, ~/Applications)만 지원한다.
  Linux deb/rpm 설치 시에는 pkexec/zenity/kdialog/sudo를 통한 권한 상승을 지원한다.
```

### 3.2 §2 목표 수정 — 플랫폼 지원

**현행** (RFC-001 38행):
```
- **플랫폼 지원**: Windows(NSIS/MSI 인스톨러), macOS(`.app` DMG), Linux(AppImage / `.deb`)
```

**변경:**
```
- **플랫폼 지원**: Windows(NSIS/MSI 인스톨러), macOS(`.app` DMG), Linux(AppImage / `.deb` / `.rpm`)
```

### 3.3 §4 매니페스트 형식 확장

#### 3.3.1 Linux 플랫폼 항목 추가 (RFC-001 174행 부근)

기존 `linux-x86_64` AppImage 항목에 더하여 deb/rpm 항목을 추가한다.
같은 플랫폼에 여러 설치 타입이 있을 경우 `{os}-{arch}-{installerType}` 키를 사용한다
(Tauri와 동일).

```json
"linux-x86_64": {
  "url": "https://example.com/releases/1.2.0/myapp-1.2.0-x86_64.AppImage",
  "size": 11000000,
  "sha256": "jkl012...",
  "signature": "BASE64_ED25519_SIG",
  "installerType": "appimage"
},
"linux-x86_64-deb": {
  "url": "https://example.com/releases/1.2.0/myapp-1.2.0-amd64.deb",
  "size": 10500000,
  "sha256": "mno345...",
  "signature": "BASE64_ED25519_SIG",
  "installerType": "deb"
},
"linux-x86_64-rpm": {
  "url": "https://example.com/releases/1.2.0/myapp-1.2.0-x86_64.rpm",
  "size": 10600000,
  "sha256": "pqr678...",
  "signature": "BASE64_ED25519_SIG",
  "installerType": "rpm"
}
```

#### 3.3.2 플랫폼 키 규칙 보충 (RFC-001 186행 부근)

**추가:**

> `installerType` 허용 값: `nsis`, `msi`, `dmg`, `appimage`, `deb`, `rpm`.
>
> 같은 OS-arch에 여러 설치 타입이 있을 경우 플랫폼 키를 `{os}-{arch}-{installerType}`로
> 확장한다. 플러그인은 현재 번들 타입에 맞는 키를 먼저 찾고(`linux-x86_64-deb`),
> 없으면 기본 키(`linux-x86_64`)로 폴백한다 (Tauri의 타겟 검색 순서와 동일).

### 3.4 §6.2 임시 저장 경로 수정 (RFC-001 282행)

**현행:**
```
Windows: %TEMP%\kalsae-updates\{version}\{filename}
macOS:   $TMPDIR/kalsae-updates/{version}/{filename}
Linux:   /tmp/kalsae-updates/{version}/{filename}
```

**변경:**
```
Windows: %TEMP%\kalsae-updates\{random}\{filename}    (이미 per-user)
macOS:   $TMPDIR/kalsae-updates/{random}/{filename}    (이미 per-user)
Linux:   다단계 폴백 (§6.2.1 참조)
```

#### 6.2.1 Linux 임시 디렉터리 전략 (Tauri 참조)

다음 순서로 임시 디렉터리 후보를 시도한다:

1. `FileManager.default.temporaryDirectory` (`$TMPDIR` 또는 `/tmp`)
2. `XDG_CACHE_HOME` / `~/.cache`
3. 현재 실행 파일의 부모 디렉터리

각 후보에서:
- `kalsae_update_{UUID}` 형식의 랜덤화된 서브디렉터리를 생성한다.
- 퍼미션을 `0700`으로 설정한다 (symlink attack 방지).
- **Same-device 체크**: 임시 디렉터리와 설치 대상이 같은 파일시스템(device)인지
  확인한다. 다르면 다음 후보로 넘어간다. atomic rename을 보장하기 위함이다.

설치 완료 또는 취소 후 디렉터리를 삭제한다.

### 3.5 §7 설치 흐름 — Linux 섹션 확장 (RFC-001 305행)

기존 AppImage 흐름을 확장하고, deb/rpm 흐름을 신규 추가한다.

#### Linux (AppImage) — 개선

```swift
// 1. 현재 AppImage 경로: APPIMAGE 환경변수 또는 ProcessInfo.processInfo.arguments[0]
// 2. 임시 디렉터리에 현재 AppImage를 백업으로 이동 (rename)
// 3. 다운로드된 새 AppImage를 현재 경로에 쓴다
// 4. chmod +x 설정
// 5. 실패 시: 백업에서 복원 (rename back)
// 6. 성공 시:
//    - installMode == .quitAndInstall:
//      Process.launchDetached(현재경로)  // 새 AppImage 재실행
//      ctx.quit()
//    - installMode == .installOnNextLaunch:
//      ctx.quit()  // 사용자가 수동 재시작
```

> **플랫폼 노트:** Linux에서는 `downloadProgress` 이벤트가 JS 프론트엔드로만
> 전달되며, taskbar progress 연동은 지원하지 않는다 (GTK4에 표준 API 부재).

#### Linux (deb) — 신규

```swift
// 1. 다운로드된 바이트를 임시 경로에 {package}.deb로 저장
// 2. 권한 상승 체인으로 설치:
//    a) pkexec dpkg -i {path}
//    b) 실패 시 → zenity/kdialog로 비밀번호 수집 → sudo -S dpkg -i {path}
//    c) 최종 폴백 → sudo dpkg -i {path} (터미널 sudo)
// 3. 설치 성공 후 ctx.quit()
```

#### Linux (rpm) — 신규

```swift
// 1. 다운로드된 바이트를 임시 경로에 {package}.rpm으로 저장
// 2. 권한 상승 체인으로 설치:
//    a) pkexec rpm -U {path}
//    b) 실패 시 → zenity/kdialog로 비밀번호 수집 → sudo -S rpm -U {path}
//    c) 최종 폴백 → sudo rpm -U {path} (터미널 sudo)
// 3. 설치 성공 후 ctx.quit()
```

#### 권한 상승 체인 (deb/rpm 공통)

Tauri의 `try_install_with_privileges` 패턴을 따른다:

1. **pkexec** (Polkit 그래픽 인증): `pkexec {cmd} {arg} {path}`
2. **GUI 비밀번호 다이얼로그**: zenity `--password` 또는 kdialog `--password`로
   비밀번호를 수집한 뒤 `sudo -S`로 파이프
3. **터미널 sudo**: `sudo {cmd} {arg} {path}` (헤드리스 환경 대응)

모든 단계에서 실패하면 `KSError(.authenticationFailed)`를 반환한다.

### 3.6 §8 미결 사항 — #5 업데이트 (RFC-001 332행)

**현행:**
```
| 5 | **Windows 관리자 권한** | per-user NSIS vs system-wide MSI | per-user만 지원. MSI system-wide는 별도 entitlement 문서 필요 |
```

**변경:**
```
| 5 | **관리자/루트 권한** | Windows per-user / Linux pkexec·sudo | Windows는 per-user만 지원 (MSI system-wide는 별도 문서 필요). Linux deb/rpm은 pkexec → zenity/kdialog → sudo 폴백 체인으로 권한 상승 |
```

### 3.7 §10 구현 단계 — 에러 코드 추가 (RFC-001 362행)

§10 #2의 에러 코드 목록에 다음을 추가한다:

```
- `authenticationFailed` — Linux 권한 상승 실패 (pkexec/zenity/sudo 모두 실패)
- `packageInstallFailed` — deb/rpm 인스톨러 실행 실패
```

---

## 4. 현재 PAL 격차 (참고)

RFC-001 범위 밖이지만, 업데이터 구현 시 영향을 줄 수 있는 기존 PAL 격차를 기록한다.

| 기능 | Windows | Linux | 비고 |
|------|---------|-------|------|
| Display 열거 (`listDisplays`/`currentDisplay`) | 구현됨 | 미구현 (프로토콜 기본 throw) | 업데이터와 직접 무관 |
| Taskbar progress (`setTaskbarProgress`) | ITaskbarList3 구현 | 미구현 (프로토콜 기본 no-op) | §3.5 플랫폼 노트로 명시 |
| 트레이 서브메뉴 | 완전 지원 | 플랫 메뉴만 | 업데이터와 직접 무관 |
| 글로벌 핫키 | 완전 지원 | 창-범위만 (Wayland 제한) | 업데이터와 직접 무관 |

---

## 5. 참조 모델 분석: Tauri updater

### Linux 임시 경로 전략
- `std::env::temp_dir()` → `dirs::cache_dir()` → 실행 파일 부모 디렉터리 순서로 폴백
- `tempfile::Builder::new().prefix("tauri_current_app").tempdir_in(...)` 로 랜덤화
- `0700` 퍼미션 설정
- `extract_path_metadata.dev() == tmp_dir_metadata.dev()` 로 same-device 체크

### Linux 패키지 설치
- `install_appimage()`: 현재 AppImage를 임시 디렉터리로 백업 → 새 파일 쓰기 → 실패 시 복원
- `install_deb()`: `pkexec dpkg -i` → zenity/kdialog 비밀번호 → `sudo -S dpkg -i` → `sudo dpkg -i`
- `install_rpm()`: `pkexec rpm -U` → zenity/kdialog 비밀번호 → `sudo -S rpm -U` → `sudo rpm -U`

### installerType 열거
Tauri의 `Installer` enum: `AppImage`, `Deb`, `Rpm`, `App`, `Msi`, `Nsis`

---

## 6. 구현 상세

### 6.0 모듈 구조

RFC-001 §10에서 명시한 `Sources/KalsaePluginUpdater/` 모듈에 다음 파일을 추가한다.
기존 `KalsaePluginProcess` 패턴(.swift 1개당 1주제)을 따른다.

```
Sources/KalsaePluginUpdater/
  KSUpdaterConfig.swift              RFC-001 §3.2 (기존 — 변경 없음)
  KSUpdaterPlugin.swift              RFC-001 §3.1 (기존 — 번들 감지 로직 추가)
  KSUpdateDownloader.swift           RFC-001 §6   (기존 — 임시 디렉터리 전략 교체)
  KSUpdateSignatureVerifier.swift    RFC-001 §5   (기존 — 변경 없음)
  KSInstallerType.swift              ★ 신규: 인스톨러 타입 열거
  KSUpdateManifest.swift             ★ 신규: 매니페스트 파싱 + 타겟 검색
  KSUpdateTempDir.swift              ★ 신규: 임시 디렉터리 다단계 폴백
  KSUpdateInstaller.swift            ★ 신규: 인스톨러 프로토콜 + 팩토리
  KSUpdateInstaller+AppImage.swift   ★ 신규: AppImage 백업/교체/복원
  KSUpdateInstaller+Deb.swift        ★ 신규: deb + 권한 상승
  KSUpdateInstaller+Rpm.swift        ★ 신규: rpm + 권한 상승
  KSUpdateInstaller+Windows.swift    RFC-001 §7   (기존 — KSUpdateInstaller 프로토콜 채택으로 시그니처 변경)
  KSUpdateInstaller+Mac.swift        RFC-001 §7   (기존 — KSUpdateInstaller 프로토콜 채택으로 시그니처 변경)
  KSPrivilegeEscalation.swift        ★ 신규: Linux pkexec/zenity/sudo 체인
  KSBundleDetector.swift             ★ 신규: Linux 번들 타입 감지
```

### 6.1 Phase A — RFC-001 문서 수정 (RFC-003 승인 즉시)

RFC-003의 §3 변경 명세를 RFC-001에 반영한다. 각 단계의 정확한 diff:

| 단계 | 대상 | diff 대상 행 | 변경 내용 요약 |
|------|------|-------------|--------------|
| A-1 | RFC-001 §2 목표 38행 | `.deb`)` → `.deb` / `.rpm`)` | 3자 추가 |
| A-2 | RFC-001 §2 비목표 46행 | 단일행 → 2행 (Linux 예외 추가) | §3.1 텍스트 그대로 |
| A-3 | RFC-001 §4 매니페스트 174행 이후 | `linux-x86_64-deb`, `linux-x86_64-rpm` JSON 블록 + 키 규칙 | §3.3 텍스트 그대로 |
| A-4 | RFC-001 §6.2 282행 | 3행 경로표 → `{random}` + 하위 §6.2.1 | §3.4 텍스트 그대로 |
| A-5 | RFC-001 §7 305행 이후 | AppImage 개선 + deb/rpm 신규 + 권한 상승 체인 | §3.5 텍스트 그대로 |
| A-6 | RFC-001 §8 #5 332행 | 항목명 + 내용 확장 | §3.6 텍스트 그대로 |
| A-7 | RFC-001 §10 #2 362행 | 에러 코드 2건 추가 | §3.7 텍스트 그대로 |

**완료 조건:** RFC-001 diff를 읽었을 때 위 7개 변경이 모두 반영되고, 기존
내용과 충돌 없음.

---

### 6.2 Phase B — 타입 및 프로토콜 설계

#### B-1. `KSInstallerType.swift` (신규)

```swift
// Sources/KalsaePluginUpdater/KSInstallerType.swift
import Foundation

/// 매니페스트에서 사용되는 인스톨러 타입.
/// RFC-001 §4 `installerType` 필드의 허용 값과 1:1 대응한다.
public enum KSInstallerType: String, Codable, Sendable, CaseIterable {
    case nsis
    case msi
    case dmg
    case appimage
    case deb
    case rpm
}
```

#### B-2. `KSUpdateManifest.swift` (신규)

RFC-001 §4 매니페스트 JSON을 파싱하는 모델. RFC-003의 확장 키 규칙을 포함한다.

```swift
// Sources/KalsaePluginUpdater/KSUpdateManifest.swift
import Foundation
public import KalsaeCore

/// 서버에서 반환하는 릴리스 매니페스트 전체.
/// RFC-001 §4 JSON 스키마와 1:1 대응.
public struct KSRemoteRelease: Codable, Sendable {
    public let schemaVersion: Int
    public let channel: String
    public let version: String
    public let releaseDate: String          // ISO 8601
    public let releaseNotes: String?
    public let mandatory: Bool
    /// 플랫폼별 에셋 맵. 키: `{os}-{arch}` 또는 `{os}-{arch}-{installerType}`.
    public let platforms: [String: KSPlatformAsset]
}

/// 매니페스트의 단일 플랫폼 항목.
public struct KSPlatformAsset: Codable, Sendable {
    public let url: String
    public let size: Int
    public let sha256: String
    public let signature: String
    public let installerType: KSInstallerType
}

// MARK: - 타겟 검색

extension KSRemoteRelease {
    /// 현재 플랫폼+아키텍처+인스톨러 타입에 맞는 에셋을 찾는다.
    ///
    /// 검색 순서 (RFC-003 §3.3.2):
    /// 1. `{os}-{arch}-{installerType}` (예: `linux-x86_64-deb`)
    /// 2. `{os}-{arch}` (예: `linux-x86_64`)
    /// 3. 없으면 `nil` 반환
    ///
    /// - Parameters:
    ///   - os: 운영 체제 키 (`"windows"`, `"macos"`, `"linux"`)
    ///   - arch: 아키텍처 키 (`"x86_64"`, `"aarch64"`)
    ///   - installerType: 현재 번들의 인스톨러 타입
    public func asset(
        os: String,
        arch: String,
        installerType: KSInstallerType
    ) -> KSPlatformAsset? {
        // 1차: 구체 키
        let specificKey = "\(os)-\(arch)-\(installerType.rawValue)"
        if let asset = platforms[specificKey] { return asset }
        // 2차: 기본 키
        let baseKey = "\(os)-\(arch)"
        return platforms[baseKey]
    }
}
```

**매니페스트의 `version` 비교:**

RFC-001 §9.5에 따라 다운그레이드를 방지한다. 비교 대상은
`KSConfig.app.version` (`Sources/KalsaeCore/Config/KSConfig.swift` 71행)이다.
`KSVersion.current`(`Sources/KalsaeCore/KSVersion.swift`)는 프레임워크 자체
버전이므로 사용하지 않는다.

```swift
// KSUpdaterPlugin.swift 내부 (check 명령 핸들러)
let currentVersion = ctx.platform.config.app.version   // "1.0.0"
let remoteVersion  = manifest.version                  // "1.2.0"
guard remoteVersion.compare(currentVersion, options: .numeric) == .orderedDescending else {
    return nil  // 업데이트 없음 (같거나 낮음 = 다운그레이드 거부)
}
```

#### B-3. `KSUpdateTempDir.swift` (신규)

```swift
// Sources/KalsaePluginUpdater/KSUpdateTempDir.swift
import Foundation
public import KalsaeCore

#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#elseif os(Windows)
import WinSDK
#endif

/// RFC-003 §3.4 / §6.2.1 — 임시 다운로드 디렉터리를 확보한다.
///
/// Linux에서 3단계 폴백을 수행하며, 모든 플랫폼에서 랜덤 서브디렉터리 +
/// 0700 퍼미션 + same-device 체크를 적용한다.
///
/// - Parameter installTarget: 설치 대상 파일 경로 (AppImage 현재 위치,
///   또는 deb/rpm은 `/usr/bin/{app}`).
///   same-device 체크에 사용된다.
/// - Returns: 생성된 임시 디렉터리 URL (caller가 정리 책임).
/// - Throws: `KSError(.ioFailed)` — 모든 후보에서 디렉터리 생성 실패.
func acquireTempDir(near installTarget: URL) throws(KSError) -> URL {
    let fm = FileManager.default
    let candidates = buildCandidates()

    for base in candidates {
        let randomName = "kalsae_update_\(UUID().uuidString)"
        let dir = base.appendingPathComponent(randomName, isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            #if !os(Windows)
            // 0700 퍼미션: 소유자만 접근 (symlink attack 방지)
            try fm.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: dir.path)
            #endif
            // same-device 체크
            if isSameDevice(dir, installTarget) {
                return dir
            }
            // 다른 device — 생성한 디렉 삭제 후 다음 후보
            try? fm.removeItem(at: dir)
        } catch {
            continue
        }
    }

    throw KSError(
        code: .ioFailed,
        message: "Failed to create temp directory on same device as '\(installTarget.path)'. "
            + "Tried \(candidates.count) candidates.")
}

/// 플랫폼별 후보 디렉터리 목록을 반환한다.
private func buildCandidates() -> [URL] {
    var results: [URL] = []
    let fm = FileManager.default

    #if os(Linux)
    // 1. $TMPDIR 또는 /tmp
    results.append(fm.temporaryDirectory)
    // 2. XDG_CACHE_HOME 또는 ~/.cache
    if let xdg = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"] {
        results.append(URL(fileURLWithPath: xdg, isDirectory: true))
    } else {
        results.append(fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache", isDirectory: true))
    }
    // 3. 현재 실행 파일의 부모 디렉터리
    let execPath = ProcessInfo.processInfo.arguments[0]
    results.append(
        URL(fileURLWithPath: execPath).deletingLastPathComponent())
    #elseif os(macOS)
    // $TMPDIR (이미 per-user)
    results.append(fm.temporaryDirectory)
    #elseif os(Windows)
    // %TEMP% (이미 per-user)
    results.append(fm.temporaryDirectory)
    #endif

    return results
}

/// 두 URL이 같은 파일시스템 디바이스에 있는지 확인한다.
/// atomic rename을 보장하려면 같은 device여야 한다.
private func isSameDevice(_ a: URL, _ b: URL) -> Bool {
    #if os(Linux) || os(macOS)
    var statA = stat()
    var statB = stat()
    guard stat(a.path, &statA) == 0,
          stat(b.path, &statB) == 0
    else { return false }
    return statA.st_dev == statB.st_dev
    #elseif os(Windows)
    // Windows에서는 %TEMP%가 항상 같은 드라이브 → true 반환.
    // 크로스 드라이브 설치는 지원 범위 밖.
    return true
    #else
    return true
    #endif
}
```

**same-device 체크 상세:**

| 시나리오 | `statA.st_dev` | `statB.st_dev` | 결과 | 동작 |
|----------|---------------|---------------|------|------|
| `/tmp` + AppImage at `/home/user/app` (같은 `/` 파티션) | 0x801 | 0x801 | ✅ 같음 | 이 디렉 사용 |
| `/tmp` (tmpfs) + AppImage at `/home/user/app` (ext4) | 0x1e | 0x801 | ❌ 다름 | 다음 후보 |
| `~/.cache` + AppImage at `/home/user/app` (ext4) | 0x801 | 0x801 | ✅ 같음 | 이 디렉 사용 |
| 모든 후보 실패 | — | — | ❌ | `KSError(.ioFailed)` |

#### B-4. `KSUpdateInstaller.swift` (신규)

```swift
// Sources/KalsaePluginUpdater/KSUpdateInstaller.swift
import Foundation
public import KalsaeCore

/// 플랫폼별 설치 로직의 공통 인터페이스.
/// RFC-001 §7의 각 플랫폼 서브섹션이 하나의 구현체에 대응한다.
protocol KSUpdateInstaller: Sendable {
    /// 다운로드 완료 + 서명 검증 완료된 패키지를 설치한다.
    ///
    /// - Parameters:
    ///   - package: 검증된 패키지 파일 URL
    ///   - installMode: 설치 완료 후 동작 (.quitAndInstall / .installOnNextLaunch)
    ///   - ctx: 플러그인 컨텍스트 (quit() 호출에 사용)
    func install(
        package: URL,
        installMode: KSInstallMode,
        ctx: any KSPluginContext
    ) async throws(KSError)
}

/// 현재 플랫폼 + 인스톨러 타입에 맞는 KSUpdateInstaller를 반환한다.
func makeInstaller(for type: KSInstallerType) throws(KSError) -> any KSUpdateInstaller {
    switch type {
    #if os(Linux)
    case .appimage: return KSAppImageInstaller()
    case .deb:      return KSDebInstaller()
    case .rpm:      return KSRpmInstaller()
    #elseif os(Windows)
    case .nsis:     return KSNSISInstaller()
    case .msi:      return KSMSIInstaller()
    #elseif os(macOS)
    case .dmg:      return KSDMGInstaller()
    #endif
    default:
        throw KSError(
            code: .invalidArgument,
            message: "Installer type '\(type.rawValue)' is not supported on this platform")
    }
}
```

**KSProcessPlugin과의 구조 비교 (패턴 참조):**

| 패턴 | KSProcessPlugin | KSUpdaterPlugin |
|------|----------------|-----------------|
| Config 타입 | `KSProcessPluginConfig` (allowlist) | `KSUpdaterConfig` (manifestURL, publicKey, ...) |
| 네임스페이스 | `"kalsae.process"` | `"kalsae.updater"` |
| 등록 헬퍼 | `ksProcessRegister` | `ksUpdaterRegister` (동일 패턴) |
| 액터 | `KSProcessManager` | `KSUpdaterManager` (상태: 다운로드 Task, 캐시된 매니페스트) |
| 플랫폼 분기 | Process 실행은 플랫폼 무관 | `KSUpdateInstaller` 프로토콜로 분기 |

#### B-5. `KSPrivilegeEscalation.swift` (신규 — Linux 전용)

`Process` 래퍼 프로토콜을 두어 테스트에서 모의 주입이 가능하도록 한다.

```swift
// Sources/KalsaePluginUpdater/KSPrivilegeEscalation.swift
import Foundation
public import KalsaeCore
internal import Logging

#if os(Linux)

// MARK: - Process 래퍼 프로토콜 (테스트 주입용)

/// Foundation.Process의 최소 표면을 추상화한다.
/// 테스트에서 실제 pkexec/sudo를 호출하지 않고 모의 구현을 주입할 수 있다.
protocol KSProcessLauncher: Sendable {
    /// 바이너리가 $PATH에 존재하는지 확인한다.
    func executableExists(_ name: String) -> Bool
    /// 명령을 실행하고 종료 코드를 반환한다.
    /// stdin에 데이터를 파이프할 수 있다 (sudo -S용).
    func run(
        executablePath: String,
        arguments: [String],
        stdinData: Data?
    ) throws -> Int32
}

/// 기본 구현: Foundation.Process를 직접 사용한다.
struct DefaultProcessLauncher: KSProcessLauncher {
    func executableExists(_ name: String) -> Bool {
        let whichProcess = Foundation.Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = [name]
        whichProcess.standardOutput = FileHandle.nullDevice
        whichProcess.standardError = FileHandle.nullDevice
        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()
            return whichProcess.terminationStatus == 0
        } catch {
            return false
        }
    }

    func run(
        executablePath: String,
        arguments: [String],
        stdinData: Data?
    ) throws -> Int32 {
        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let data = stdinData {
            let pipe = Pipe()
            process.standardInput = pipe
            try process.run()
            pipe.fileHandleForWriting.write(data)
            pipe.fileHandleForWriting.closeFile()
        } else {
            try process.run()
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

// MARK: - 권한 상승 체인

/// Tauri `try_install_with_privileges` 패턴의 Swift 구현.
///
/// 3단계 폴백:
/// 1. pkexec (Polkit 그래픽 인증)
/// 2. zenity --password / kdialog --password → sudo -S
/// 3. sudo (터미널 TTY)
///
/// - Parameters:
///   - command: 실행할 명령어 (예: `"/usr/bin/dpkg"`)
///   - args: 명령 인수 (예: `["-i", "/tmp/.../foo.deb"]`)
///   - launcher: Process 래퍼 (기본: `DefaultProcessLauncher()`, 테스트 시 주입)
/// - Throws: `KSError(.authenticationFailed)` — 모든 단계 실패.
///           `KSError(.packageInstallFailed)` — 권한 상승 성공했으나 설치 실패.
func runWithPrivileges(
    command: String,
    args: [String],
    launcher: some KSProcessLauncher = DefaultProcessLauncher()
) throws(KSError) {
    let log = Logger(label: "kalsae.updater.privileges")

    // ── 1단계: pkexec ──
    if launcher.executableExists("pkexec") {
        log.debug("Attempting pkexec...")
        do {
            let code = try launcher.run(
                executablePath: "/usr/bin/pkexec",
                arguments: [command] + args,
                stdinData: nil)
            if code == 0 { return }
            log.debug("pkexec exited with code \(code)")
        } catch {
            log.debug("pkexec failed: \(error)")
        }
    }

    // ── 2단계: zenity/kdialog → sudo -S ──
    let password = collectPassword(launcher: launcher, log: log)
    if let password {
        log.debug("Attempting sudo -S with collected password...")
        do {
            let passwordData = Data((password + "\n").utf8)
            let code = try launcher.run(
                executablePath: "/usr/bin/sudo",
                arguments: ["-S", command] + args,
                stdinData: passwordData)
            if code == 0 { return }
            log.debug("sudo -S exited with code \(code)")
            throw KSError(
                code: .packageInstallFailed,
                message: "\(command) failed with exit code \(code) "
                    + "(privilege escalation via sudo -S succeeded)")
        } catch let e as KSError {
            throw e
        } catch {
            log.debug("sudo -S failed: \(error)")
        }
    }

    // ── 3단계: 터미널 sudo ──
    if launcher.executableExists("sudo") {
        log.debug("Attempting terminal sudo...")
        do {
            let code = try launcher.run(
                executablePath: "/usr/bin/sudo",
                arguments: [command] + args,
                stdinData: nil)
            if code == 0 { return }
            throw KSError(
                code: .packageInstallFailed,
                message: "\(command) failed with exit code \(code) "
                    + "(privilege escalation via sudo succeeded)")
        } catch let e as KSError {
            throw e
        } catch {
            log.debug("terminal sudo failed: \(error)")
        }
    }

    // ── 모든 단계 실패 ──
    throw KSError(
        code: .authenticationFailed,
        message: "All privilege escalation methods failed "
            + "(pkexec, zenity/kdialog, sudo). "
            + "Install the package manually: sudo \(command) \(args.joined(separator: " "))")
}

/// zenity 또는 kdialog로 GUI 비밀번호를 수집한다.
private func collectPassword(
    launcher: some KSProcessLauncher,
    log: Logger
) -> String? {
    // zenity 시도
    if launcher.executableExists("zenity") {
        let pipe = Pipe()
        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zenity")
        process.arguments = [
            "--password",
            "--title=Kalsae Update",
        ]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            log.debug("zenity failed: \(error)")
        }
    }

    // kdialog 시도
    if launcher.executableExists("kdialog") {
        let pipe = Pipe()
        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/kdialog")
        process.arguments = [
            "--password",
            "Kalsae requires your password to install the update",
        ]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            log.debug("kdialog failed: \(error)")
        }
    }

    return nil
}

#endif // os(Linux)
```

**권한 상승 체인 흐름도:**

```
┌─────────────┐     성공
│ 1. pkexec   │──────────→ return (설치 완료)
└──────┬──────┘
       │ 실패/미설치
       ▼
┌─────────────┐  비밀번호
│ 2a. zenity  │──────┐
│   / kdialog │      │
└──────┬──────┘      ▼
       │ 실패   ┌─────────┐   성공
       │        │ sudo -S │────→ return
       │        └────┬────┘
       │             │ 실패
       ▼             ▼
┌─────────────┐     성공
│ 3. sudo     │──────────→ return
│  (터미널)   │
└──────┬──────┘
       │ 실패
       ▼
  KSError(.authenticationFailed)
```

#### B-6. `KSError.Code` 확장

`Sources/KalsaeCore/Error/KSError.swift` 115–116행 (`// 외부 프로세스 / 셰트` 주석 부근)에 추가:

**현행 (113–120행):**
```swift
        // 외부 프로세스 / 셰트
        case shellInvocationFailed

        // 일반
        case cancelled
        case invalidArgument
        case `internal`
```

**변경:**
```swift
        // 외부 프로세스 / 셰트
        case shellInvocationFailed

        // 업데이터 (KalsaePluginUpdater)
        case checksumMismatch
        case signatureVerificationFailed
        case insecureURL
        case authenticationFailed
        case packageInstallFailed

        // 일반
        case cancelled
        case invalidArgument
        case `internal`
```

> 기존 3개 (`checksumMismatch`, `signatureVerificationFailed`, `insecureURL`)는
> RFC-001 §5, §9에서 이미 정의된 것이고, RFC-003에서 추가하는 것은
> `authenticationFailed`와 `packageInstallFailed` 2건이다.

---

### 6.3 Phase C — 플랫폼별 설치 로직 구현

#### C-1. `KSUpdateInstaller+AppImage.swift` (신규 — Linux)

```swift
// Sources/KalsaePluginUpdater/KSUpdateInstaller+AppImage.swift
import Foundation
public import KalsaeCore
internal import Logging

#if os(Linux)

struct KSAppImageInstaller: KSUpdateInstaller {
    func install(
        package: URL,
        installMode: KSInstallMode,
        ctx: any KSPluginContext
    ) async throws(KSError) {
        let log = Logger(label: "kalsae.updater.appimage")
        let fm = FileManager.default

        // 1. 현재 AppImage 경로 결정
        let currentPath = resolveCurrentAppImagePath()

        // 2. 임시 디렉터리 확보 (same-device 보장)
        let tempDir = try acquireTempDir(near: URL(fileURLWithPath: currentPath))
        defer { try? fm.removeItem(at: tempDir) }

        // 3. 현재 AppImage를 백업
        let backupPath = tempDir.appendingPathComponent("current.bak")
        do {
            try fm.moveItem(
                atPath: currentPath,
                toPath: backupPath.path)
        } catch {
            throw KSError(
                code: .ioFailed,
                message: "Failed to backup current AppImage: \(error)")
        }

        // 4. 새 AppImage를 현재 경로에 복사
        do {
            try fm.copyItem(at: package, to: URL(fileURLWithPath: currentPath))
            // chmod +x
            try fm.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: currentPath)
        } catch {
            // ── 5. 실패 시 백업 복원 ──
            log.error("Failed to install new AppImage, restoring backup: \(error)")
            try? fm.moveItem(
                atPath: backupPath.path,
                toPath: currentPath)
            throw KSError(
                code: .ioFailed,
                message: "Failed to write new AppImage: \(error)")
        }

        log.info("AppImage updated: \(currentPath)")

        // 6. 재실행 또는 종료
        switch installMode {
        case .quitAndInstall:
            launchDetached(currentPath)
            ctx.platform.quit()
        case .installOnNextLaunch:
            ctx.platform.quit()
        }
    }
}

/// APPIMAGE 환경변수 → arguments[0] 순서로 현재 AppImage 경로를 결정한다.
private func resolveCurrentAppImagePath() -> String {
    if let appimage = ProcessInfo.processInfo.environment["APPIMAGE"],
       !appimage.isEmpty
    {
        return appimage
    }
    return ProcessInfo.processInfo.arguments[0]
}

/// 새 AppImage를 분리된 프로세스로 재실행한다.
private func launchDetached(_ path: String) {
    let process = Foundation.Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = []
    // 부모 종료 후에도 자식이 살아남도록 표준 IO를 닫는다
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    try? process.run()
}

#endif // os(Linux)
```

#### C-2. `KSUpdateInstaller+Deb.swift` (신규 — Linux)

```swift
// Sources/KalsaePluginUpdater/KSUpdateInstaller+Deb.swift
import Foundation
public import KalsaeCore

#if os(Linux)

struct KSDebInstaller: KSUpdateInstaller {
    func install(
        package: URL,
        installMode: KSInstallMode,
        ctx: any KSPluginContext
    ) async throws(KSError) {
        try runWithPrivileges(
            command: "/usr/bin/dpkg",
            args: ["-i", package.path])

        switch installMode {
        case .quitAndInstall:
            // dpkg -L {패키지명}으로 실행 파일 경로 질의
            if let execPath = queryInstalledExecutable(debPath: package) {
                launchDetached(execPath)
            }
            ctx.platform.quit()
        case .installOnNextLaunch:
            ctx.platform.quit()
        }
    }
}

/// deb 패키지에서 설치된 실행 파일 경로를 dpkg -L로 질의한다.
private func queryInstalledExecutable(debPath: URL) -> String? {
    // dpkg-deb --field {path} Package → 패키지명
    let nameProc = Foundation.Process()
    nameProc.executableURL = URL(fileURLWithPath: "/usr/bin/dpkg-deb")
    nameProc.arguments = ["--field", debPath.path, "Package"]
    let namePipe = Pipe()
    nameProc.standardOutput = namePipe
    nameProc.standardError = FileHandle.nullDevice
    do { try nameProc.run() } catch { return nil }
    nameProc.waitUntilExit()
    guard nameProc.terminationStatus == 0 else { return nil }
    let nameData = namePipe.fileHandleForReading.readDataToEndOfFile()
    guard let pkgName = String(data: nameData, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
          !pkgName.isEmpty
    else { return nil }

    // dpkg -L {pkgName} → /usr/bin/{app} 경로를 찾는다
    let listProc = Foundation.Process()
    listProc.executableURL = URL(fileURLWithPath: "/usr/bin/dpkg")
    listProc.arguments = ["-L", pkgName]
    let listPipe = Pipe()
    listProc.standardOutput = listPipe
    listProc.standardError = FileHandle.nullDevice
    do { try listProc.run() } catch { return nil }
    listProc.waitUntilExit()
    guard listProc.terminationStatus == 0 else { return nil }
    let listData = listPipe.fileHandleForReading.readDataToEndOfFile()
    let files = String(data: listData, encoding: .utf8)?
        .split(separator: "\n")
        .map(String.init) ?? []
    return files.first(where: { $0.hasPrefix("/usr/bin/") || $0.hasPrefix("/usr/local/bin/") })
}

#endif // os(Linux)
```

#### C-3. `KSUpdateInstaller+Rpm.swift` (신규 — Linux)

```swift
// Sources/KalsaePluginUpdater/KSUpdateInstaller+Rpm.swift
import Foundation
public import KalsaeCore

#if os(Linux)

struct KSRpmInstaller: KSUpdateInstaller {
    func install(
        package: URL,
        installMode: KSInstallMode,
        ctx: any KSPluginContext
    ) async throws(KSError) {
        try runWithPrivileges(
            command: "/usr/bin/rpm",
            args: ["-U", package.path])

        switch installMode {
        case .quitAndInstall:
            if let execPath = queryInstalledExecutable(rpmPath: package) {
                launchDetached(execPath)
            }
            ctx.platform.quit()
        case .installOnNextLaunch:
            ctx.platform.quit()
        }
    }
}

/// rpm 패키지에서 설치된 실행 파일 경로를 rpm -ql로 질의한다.
private func queryInstalledExecutable(rpmPath: URL) -> String? {
    // rpm -qp --queryformat '%{NAME}' {path} → 패키지명
    let nameProc = Foundation.Process()
    nameProc.executableURL = URL(fileURLWithPath: "/usr/bin/rpm")
    nameProc.arguments = ["-qp", "--queryformat", "%{NAME}", rpmPath.path]
    let namePipe = Pipe()
    nameProc.standardOutput = namePipe
    nameProc.standardError = FileHandle.nullDevice
    do { try nameProc.run() } catch { return nil }
    nameProc.waitUntilExit()
    guard nameProc.terminationStatus == 0 else { return nil }
    let nameData = namePipe.fileHandleForReading.readDataToEndOfFile()
    guard let pkgName = String(data: nameData, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
          !pkgName.isEmpty
    else { return nil }

    // rpm -ql {pkgName} → /usr/bin/{app} 경로를 찾는다
    let listProc = Foundation.Process()
    listProc.executableURL = URL(fileURLWithPath: "/usr/bin/rpm")
    listProc.arguments = ["-ql", pkgName]
    let listPipe = Pipe()
    listProc.standardOutput = listPipe
    listProc.standardError = FileHandle.nullDevice
    do { try listProc.run() } catch { return nil }
    listProc.waitUntilExit()
    guard listProc.terminationStatus == 0 else { return nil }
    let listData = listPipe.fileHandleForReading.readDataToEndOfFile()
    let files = String(data: listData, encoding: .utf8)?
        .split(separator: "\n")
        .map(String.init) ?? []
    return files.first(where: { $0.hasPrefix("/usr/bin/") || $0.hasPrefix("/usr/local/bin/") })
}

#endif // os(Linux)
```

#### C-4 / C-5. Windows·macOS 인스톨러 변경 사항

기존 RFC-001 §7의 Windows(NSIS/MSI)·macOS(DMG) 로직은 그대로 유지한다.
변경점은 `KSUpdateInstaller` 프로토콜 채택으로 시그니처를 통일하는 것뿐이다:

```swift
// 변경 전 (RFC-001 기존 설계):
func installNSIS(path: URL, ctx: ...) { ... }
func installMSI(path: URL, ctx: ...) { ... }
func installDMG(path: URL, ctx: ...) { ... }

// 변경 후:
struct KSNSISInstaller: KSUpdateInstaller { func install(package:installMode:ctx:) ... }
struct KSMSIInstaller:  KSUpdateInstaller { func install(package:installMode:ctx:) ... }
struct KSDMGInstaller:  KSUpdateInstaller { func install(package:installMode:ctx:) ... }
```

내부 로직은 RFC-001 §7 코드 블록과 동일하다. 본 RFC에서 변경하지 않는다.

---

### 6.4 Phase D — 다운로더 및 매니페스트 연동

#### D-1. `KSUpdateDownloader.swift` 임시 디렉터리 교체

RFC-001 §6.2의 고정 경로를 `acquireTempDir(near:)` 호출로 교체한다.

**현행 (RFC-001 설계):**
```swift
let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("kalsae-updates/\(version)")
```

**변경:**
```swift
let installTarget: URL = ... // 플랫폼별 설치 대상 (§D-3에서 결정)
let tempDir = try acquireTempDir(near: installTarget)
defer { try? FileManager.default.removeItem(at: tempDir) }
```

#### D-2. `KSUpdaterPlugin.swift` 인스톨러 선택 로직

RFC-001 §3.1의 `setup(_:)` 내부에서 번들 타입을 감지하고 적절한 인스톨러를 선택한다.

```swift
// KSUpdaterPlugin.setup(_:) 내부 — install 명령 핸들러
await ksUpdaterRegister(ctx.registry, "kalsae.updater.install") {
    (_: KSEmpty) async throws(KSError) -> KSEmpty in

    guard let pendingAsset = manager.pendingAsset,
          let pendingPackage = manager.downloadedPackage
    else {
        throw KSError(
            code: .invalidArgument,
            message: "No downloaded package. Call kalsae.updater.download first.")
    }

    let installer = try makeInstaller(for: pendingAsset.installerType)
    try await installer.install(
        package: pendingPackage,
        installMode: config.installMode,
        ctx: ctx)

    return KSEmpty()
}
```

#### D-3. `KSBundleDetector.swift` — Linux 번들 타입 감지

```swift
// Sources/KalsaePluginUpdater/KSBundleDetector.swift
import Foundation

/// 현재 프로세스의 인스톨러 타입(Linux에서 AppImage/deb/rpm 중 하나)을 감지한다.
///
/// 감지 순서:
/// 1. `APPIMAGE` 환경변수 존재 → `.appimage`
/// 2. 실행 파일 경로가 `/usr/bin/` 또는 `/usr/local/bin/` → `.deb` 또는 `.rpm`
///    (dpkg/rpm 중 어느 패키지 관리자에 속하는지 `dpkg -S` → `rpm -qf` 순서로 확인)
/// 3. 폴백 → `.appimage`
func detectLinuxBundleType() -> KSInstallerType {
    #if os(Linux)
    // 1. APPIMAGE 환경변수
    if let appimage = ProcessInfo.processInfo.environment["APPIMAGE"],
       !appimage.isEmpty
    {
        return .appimage
    }

    // 2. 시스템 경로에서 실행 중 → 패키지 관리자 확인
    let execPath = ProcessInfo.processInfo.arguments[0]
    let systemPaths = ["/usr/bin/", "/usr/local/bin/", "/usr/sbin/"]
    if systemPaths.contains(where: { execPath.hasPrefix($0) }) {
        // dpkg -S 먼저 시도
        if processExitCode("/usr/bin/dpkg", args: ["-S", execPath]) == 0 {
            return .deb
        }
        // rpm -qf 시도
        if processExitCode("/usr/bin/rpm", args: ["-qf", execPath]) == 0 {
            return .rpm
        }
    }

    // 3. 폴백
    return .appimage
    #else
    fatalError("detectLinuxBundleType() called on non-Linux platform")
    #endif
}

#if os(Linux)
/// 프로세스를 실행하고 종료 코드만 반환한다.
private func processExitCode(_ path: String, args: [String]) -> Int32 {
    let proc = Foundation.Process()
    proc.executableURL = URL(fileURLWithPath: path)
    proc.arguments = args
    proc.standardOutput = FileHandle.nullDevice
    proc.standardError = FileHandle.nullDevice
    do {
        try proc.run()
        proc.waitUntilExit()
        return proc.terminationStatus
    } catch {
        return -1
    }
}
#endif
```

**번들 감지 결정 테이블:**

| 환경 | `APPIMAGE` 설정? | 실행 경로 | `dpkg -S` | `rpm -qf` | 결과 |
|------|----------------|----------|-----------|-----------|------|
| AppImage 실행 | ✅ `/home/user/app.AppImage` | `/tmp/.mount_*/bin/app` | — | — | `.appimage` |
| deb 설치 | ❌ | `/usr/bin/myapp` | 0 (성공) | — | `.deb` |
| rpm 설치 | ❌ | `/usr/bin/myapp` | 비-0 | 0 (성공) | `.rpm` |
| 수동 빌드 | ❌ | `/home/user/build/myapp` | — | — | `.appimage` (폴백) |
| Flatpak/Snap | ❌ | `/app/bin/myapp` | 비-0 | 비-0 | `.appimage` (폴백) |

---

### 6.5 Phase E — 테스트

테스트는 swift-testing (`@Test`, `@Suite`, `#expect`)을 사용한다. XCTest 금지.
모든 테스트 파일은 `Tests/KalsaePluginUpdaterTests/`에 위치한다.

#### E-1. `KSUpdateManifestTests.swift`

```swift
@Suite("매니페스트 파싱 및 타겟 검색")
struct KSUpdateManifestTests {
    @Test("linux-x86_64-deb 키로 deb 에셋 직접 검색")
    func findDebAssetBySpecificKey() { ... }

    @Test("linux-x86_64-deb 없으면 linux-x86_64로 폴백")
    func fallbackToBaseKey() { ... }

    @Test("존재하지 않는 플랫폼 키 → nil")
    func missingPlatformReturnsNil() { ... }

    @Test("유효하지 않은 installerType → DecodingError")
    func invalidInstallerTypeThrows() { ... }

    @Test("schemaVersion 이상한 값 → 파싱 성공 (forward compat)")
    func unknownSchemaVersionStillDecodes() { ... }
}
```

#### E-2. `KSUpdateTempDirTests.swift`

```swift
@Suite("임시 디렉터리 폴백")
struct KSUpdateTempDirTests {
    @Test("같은 device에서 디렉터리 생성 성공")
    func sameDeviceSuccess() throws { ... }

    @Test("0700 퍼미션 검증")
    func permissionsAre0700() throws { ... }

    @Test("UUID 기반 랜덤 디렉터리 이름")
    func directoryNameContainsUUID() throws { ... }

    @Test("모든 후보 실패 시 ioFailed 에러")
    func allCandidatesFailThrows() throws { ... }
}
```

> **참고:** same-device 체크 테스트 시, CI에서 `/tmp`와 프로젝트 디렉터리가
> 같은 device인 경우가 대부분이므로, 모의 `stat.st_dev` 비교를 프로토콜화하여
> 테스트에서 주입하는 방식 대신, 실제 디렉터리에서 같은-device 경우만 검증한다.
> 다른-device 경우는 `isSameDevice`의 유닛 테스트로 별도 검증한다.

#### E-3. `KSPrivilegeEscalationTests.swift`

```swift
@Suite("권한 상승 체인")
struct KSPrivilegeEscalationTests {
    // 모의 KSProcessLauncher
    struct MockLauncher: KSProcessLauncher {
        var availableExecutables: Set<String> = []
        var exitCodes: [String: Int32] = [:]  // executablePath → exit code

        func executableExists(_ name: String) -> Bool {
            availableExecutables.contains(name)
        }

        func run(executablePath: String, arguments: [String], stdinData: Data?) throws -> Int32 {
            exitCodes[executablePath] ?? 1
        }
    }

    @Test("pkexec 성공 → 즉시 반환")
    func pkexecSuccess() throws {
        var mock = MockLauncher()
        mock.availableExecutables = ["pkexec"]
        mock.exitCodes = ["/usr/bin/pkexec": 0]
        try runWithPrivileges(command: "/usr/bin/dpkg", args: ["-i", "/tmp/a.deb"], launcher: mock)
        // 에러 없이 반환되면 성공
    }

    @Test("pkexec 실패 → sudo 폴백 성공")
    func pkexecFailSudoSuccess() throws {
        var mock = MockLauncher()
        mock.availableExecutables = ["pkexec", "sudo"]
        mock.exitCodes = ["/usr/bin/pkexec": 1, "/usr/bin/sudo": 0]
        try runWithPrivileges(command: "/usr/bin/dpkg", args: ["-i", "/tmp/a.deb"], launcher: mock)
    }

    @Test("모두 실패 → authenticationFailed")
    func allFail() {
        let mock = MockLauncher()  // 아무것도 없음
        #expect(throws: KSError.self) {
            try runWithPrivileges(command: "/usr/bin/dpkg", args: ["-i", "/tmp/a.deb"], launcher: mock)
        }
    }

    @Test("권한 상승 성공 + 설치 실패 → packageInstallFailed")
    func privilegeOkButInstallFails() {
        var mock = MockLauncher()
        mock.availableExecutables = ["pkexec"]
        mock.exitCodes = ["/usr/bin/pkexec": 42]  // 설치 실패
        // pkexec 종료 코드 비-0이면 다음 단계로 넘어감
        // ... 최종적으로 모두 실패하면 authenticationFailed
    }
}
```

#### E-4. `KSUpdateInstallerAppImageTests.swift`

```swift
@Suite("AppImage 설치")
struct KSUpdateInstallerAppImageTests {
    @Test("백업 → 교체 → chmod 0755 검증")
    func successfulInstallation() async throws { ... }

    @Test("교체 실패 시 백업 복원")
    func failedInstallationRestoresBackup() async throws { ... }

    @Test("APPIMAGE 환경변수 우선 사용")
    func appimageEnvVarTakesPrecedence() { ... }
}
```

#### E-5 / E-6. deb/rpm 설치 테스트

```swift
@Suite("deb 설치")
struct KSUpdateInstallerDebTests {
    @Test("권한 상승 체인 호출 + dpkg -i 실행 확인")
    func debInstallCallsPrivileges() async throws { ... }

    @Test("dpkg -L로 실행 파일 경로 질의")
    func queriesInstalledExecutable() { ... }
}

@Suite("rpm 설치")
struct KSUpdateInstallerRpmTests {
    @Test("권한 상승 체인 호출 + rpm -U 실행 확인")
    func rpmInstallCallsPrivileges() async throws { ... }

    @Test("rpm -ql로 실행 파일 경로 질의")
    func queriesInstalledExecutable() { ... }
}
```

#### E-7 / E-8. Windows·macOS 회귀 테스트

기존 테스트가 `KSUpdateInstaller` 프로토콜 채택 후에도 통과하는지 확인한다.
로직 변경이 없으므로 시그니처 호환성만 검증하면 충분하다.

#### E-9. 통합 테스트

```swift
@Suite("업데이트 파이프라인 통합 — Linux")
struct KSUpdaterPipelineLinuxTests {
    @Test("매니페스트 → 에셋 선택(deb) → 다운로드(모의) → 서명 검증 → 인스톨러 선택 → 설치(모의)")
    func fullPipelineDeb() async throws {
        // 1. 로컬 JSON 파일에서 매니페스트 디코딩
        // 2. asset(os: "linux", arch: "x86_64", installerType: .deb) 호출
        // 3. 모의 다운로더가 검증 완료된 파일 반환
        // 4. makeInstaller(for: .deb) → KSDebInstaller
        // 5. KSDebInstaller.install() → runWithPrivileges(MockLauncher)
    }
}
```

**테스트 규칙:**
- swift-testing (`@Test`, `@Suite`, `#expect`) 사용. XCTest 금지.
- 모의 `Process` 실행: `KSProcessLauncher` 프로토콜을 주입. 실제 pkexec/dpkg/rpm을 호출하지 않는다.
- CI에서 `swift test --no-parallel` 권장 (임시 디렉터리 충돌 방지).
- 성능 단언은 `CI` 환경변수로 완화.

---

### 6.6 Phase F — Package.swift 및 CI 연동

#### F-0. `Package.swift` 변경

`Package.swift` 19행(products)과 282행(targets) 부근에 추가한다.
`KalsaePluginProcess` 패턴을 따른다.

**products 추가 (19행 부근):**
```swift
        .library(name: "KalsaePluginProcess", targets: ["KalsaePluginProcess"]),
        .library(name: "KalsaePluginUpdater", targets: ["KalsaePluginUpdater"]),  // ← 추가
```

**dependencies 추가 (24행 부근):**
```swift
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),  // ← 추가
```

> **조건부 의존:** `swift-crypto`는 macOS/iOS에서는 `CryptoKit`으로 대체되므로
> 타겟 의존성에서 `.when(platforms: [.windows, .linux])`을 사용한다.

**targets 추가 (288행, `KalsaePluginProcess` 직후):**
```swift
        .target(
            name: "KalsaePluginUpdater",
            dependencies: [
                "KalsaeCore",
                .product(name: "Crypto", package: "swift-crypto",
                         condition: .when(platforms: [.windows, .linux])),
            ],
            path: "Sources/KalsaePluginUpdater",
            swiftSettings: commonSwiftSettings
        ),
        .testTarget(
            name: "KalsaePluginUpdaterTests",
            dependencies: ["KalsaePluginUpdater", "KalsaeCore"],
            path: "Tests/KalsaePluginUpdaterTests",
            swiftSettings: commonSwiftSettings
        ),
```

#### F-1 ~ F-3. CI 워크플로 변경

| 파일 | 변경 |
|------|------|
| `.github/workflows/phase10-linux-e2e.yml` | `swift test --filter KalsaePluginUpdaterTests` 스텝 추가 |
| `.github/workflows/phase-windows-build.yml` | `swift test` 전체 실행이므로 별도 추가 불필요 (회귀 자동 확인) |
| `.github/workflows/phase9-macos-e2e.yml` | `swift test` 전체 실행이므로 별도 추가 불필요 (회귀 자동 확인) |

---

### 6.7 Phase G — `KSPluginContext` 확장 (`quit()`)

RFC-001 §10 #3에서 요구하는 `quit()` 메서드를 `KSPluginContext`에 추가한다.

**현행** (`Sources/KalsaeCore/Plugin/KSPlugin.swift` 1–10행):
```swift
public protocol KSPluginContext: Sendable {
    var registry: KSCommandRegistry { get }
    var platform: any KSPlatform { get }
    func emit(_ event: String, payload: sending any Encodable) async throws(KSError)
}
```

**변경:**
```swift
public protocol KSPluginContext: Sendable {
    var registry: KSCommandRegistry { get }
    var platform: any KSPlatform { get }
    func emit(_ event: String, payload: sending any Encodable) async throws(KSError)
    /// 애플리케이션의 정리된 종료를 요청한다. 업데이터 등 플러그인이 설치 완료 후 호출한다.
    func quit()
}
```

**`DefaultPluginContext` 구현 추가** (`Sources/Kalsae/KSApp+Plugins.swift` 87행 부근):
```swift
internal struct DefaultPluginContext: KSPluginContext {
    private let app: KSApp

    init(app: KSApp) { self.app = app }

    var registry: KSCommandRegistry { app.registry }
    var platform: any KSPlatform { app.platform }

    func emit(_ event: String, payload: sending any Encodable) async throws(KSError) { ... }

    func quit() {   // ← 추가
        app.quit()
    }
}
```

> `KSApp.quit()`는 이미 `Sources/Kalsae/KSApp.swift` 606행에 `nonisolated public func quit()`로
> 구현되어 있으므로 단순 위임만 하면 된다.

---

### 6.8 Phase 간 의존성 요약

```
Phase A (RFC-001 문서 수정)
    ↓
Phase G (KSPluginContext.quit())        ← 독립적, 어느 Phase에서든 가능
    ↓
Phase B (타입 설계: B-1 → B-2 → B-3, B-4, B-5 → B-6)
    ↓
Phase C (설치 로직: C-1,C-2,C-3 병렬 가능) ←─ Phase D (다운로더: D-1,D-2,D-3 병렬)
    ↓                                            ↓
    └────────────────┬───────────────────────────┘
                     ↓
Phase F (Package.swift + CI)
                     ↓
Phase E (테스트: E-1~E-9)
```

Phase A 독립 → 승인 즉시 실행.  
Phase G 독립 → B 이전 아무 때나 실행.  
Phase B~D → RFC-001 구현 사이클 일부.  
Phase F → 코드 작성 완료 후.  
Phase E → F 이후 (CI에서 테스트 실행 가능해진 후).

---

## 7. 리스크 및 완화

| 리스크 | 영향 | 완화 |
|--------|------|------|
| pkexec가 설치되지 않은 미니멀 Linux 배포판 | deb/rpm 설치 첫 단계 건너뜀 | 폴백 체인이 zenity/kdialog/sudo로 계속 시도. 모두 없으면 `authenticationFailed` 반환하고 JS 프론트엔드에서 안내 |
| zenity/kdialog 모두 없는 서버 환경 | GUI 비밀번호 수집 불가 | 터미널 sudo 폴백. 완전 헤드리스(TTY 없음)이면 에러 반환 + 수동 설치 안내 |
| same-device 체크에서 모든 후보 디렉터리 실패 | 임시 파일 생성 불가 | `KSError(.ioFailed)` 반환 (에러 메시지에 시도한 후보 수 포함). Tauri와 동일 패턴 |
| AppImage가 아닌 바이너리에서 `APPIMAGE` 미설정 | 번들 타입 감지 실패 | `dpkg -S` → `rpm -qf` 순서 확인. 미확인 시 `.appimage` 폴백 (§6.4 D-3 결정 테이블 참조) |
| deb/rpm 설치 후 재실행 경로 불명확 | 새 바이너리 경로가 이전과 다를 수 있음 | `dpkg -L`/`rpm -ql`로 `/usr/bin/*` 경로 질의. `quitAndInstall` 시만 사용. `installOnNextLaunch`는 경로 불필요 |
| `collectPassword` 함수가 저장 없이 비밀번호를 stdin 파이프로 전달 | 메모리 잔류 가능 | 비밀번호를 `String`으로 처리하되 사용 직후 `Data`로 변환. 장기 저장 금지. 로그에 비밀번호 출력 금지 |
| swift-crypto 의존성 추가로 빌드 시간 증가 | 전체 프로젝트 빌드 | `KalsaePluginUpdater`는 opt-in 타겟이므로 앱이 의존하지 않으면 빌드에 포함되지 않음 |

---

## 8. 엣지 케이스 테이블

| # | 시나리오 | 예상 동작 | 에러 코드 |
|---|---------|----------|----------|
| 1 | 매니페스트 `linux-x86_64-deb` 키 없음, `linux-x86_64` 있음 | 기본 키로 폴백, 해당 에셋 사용 | — |
| 2 | 매니페스트에 현재 플랫폼 키 전혀 없음 | `check` 명령에서 `null` 반환 | — |
| 3 | `APPIMAGE` 설정 + 실행 경로 `/usr/bin/*` | `APPIMAGE` 우선 → `.appimage` | — |
| 4 | tmpfs `/tmp` + ext4 `/home` (다른 device) | `/tmp` 건너뜀 → `~/.cache` 시도 | — |
| 5 | 모든 임시 디렉터리 후보에서 same-device 실패 | `acquireTempDir` threw | `.ioFailed` |
| 6 | pkexec만 있고 Polkit agent 없음 (headless) | pkexec 에러 → sudo 폴백 | — |
| 7 | pkexec, zenity, kdialog, sudo 모두 미설치 | 체인 전체 실패 | `.authenticationFailed` |
| 8 | pkexec 성공 + dpkg 실패 (의존성 문제) | `dpkg` 종료 코드 비-0 | `.packageInstallFailed` |
| 9 | 다운그레이드 시도 (remote version ≤ current) | `check` 명령에서 `null` 반환 | — |
| 10 | deb 설치 후 `dpkg -L` 결과에 `/usr/bin/*` 없음 | 재실행 경로 `nil` → `quitAndInstall`에서 재실행 생략, 종료만 | — |
| 11 | AppImage 교체 중 디스크 부족으로 쓰기 실패 | 백업에서 복원 (rename back) | `.ioFailed` |
| 12 | `mandatory: true` + 사용자가 취소 | 프론트엔드 정책 (앱 레벨) — 플러그인은 강제하지 않음 | — |

---

## 9. 검증 시나리오 (구현 완료 후)

| # | 시나리오 | 검증 방법 | 플랫폼 |
|---|---------|----------|--------|
| V-1 | AppImage 업데이트: 기존 → 신규 교체 | 모의 다운로드 + 실제 파일 교체 + chmod 확인 | Linux CI |
| V-2 | AppImage 교체 실패 → 백업 복원 | 쓰기 불가 경로에서 교체 시도 | Linux CI |
| V-3 | deb 설치: pkexec 성공 경로 | MockLauncher(pkexec: 0) | Linux CI |
| V-4 | deb 설치: pkexec 실패 → sudo 성공 | MockLauncher(pkexec: 1, sudo: 0) | Linux CI |
| V-5 | deb 설치: 모두 실패 → authenticationFailed | MockLauncher(전부 실패) | Linux CI |
| V-6 | rpm 설치: pkexec 성공 경로 | MockLauncher(pkexec: 0) | Linux CI |
| V-7 | rpm 설치: 모두 실패 → authenticationFailed | MockLauncher(전부 실패) | Linux CI |
| V-8 | 매니페스트 `linux-x86_64-deb` → deb 에셋 직접 찾기 | 디코딩 + asset() 호출 | 전 플랫폼 |
| V-9 | 매니페스트 `linux-x86_64` 폴백 | deb 키 없는 매니페스트 + asset() 호출 | 전 플랫폼 |
| V-10 | 임시 디렉터리 같은 device 성공 | acquireTempDir + stat 비교 | Linux CI |
| V-11 | 번들 감지: APPIMAGE 설정 → .appimage | 환경변수 설정 후 detectLinuxBundleType() | Linux CI |
| V-12 | 번들 감지: /usr/bin 경로 + dpkg -S 성공 → .deb | MockProcess | Linux CI |
| V-13 | `KSPluginContext.quit()` 호출 → `KSApp.quit()` 위임 | DefaultPluginContext 테스트 | 전 플랫폼 |
| V-14 | 다운그레이드 거부 (remote "1.0.0" ≤ current "1.2.0") | check 명령에서 nil 반환 확인 | 전 플랫폼 |
| V-15 | 에러 코드 5개 존재 확인 | `KSError.Code.allCases` 검증 | 전 플랫폼 |
| V-16 | Package.swift 컴파일 | `swift build --target KalsaePluginUpdater` | 전 플랫폼 |

---

## 10. 검증 체크리스트 (RFC-003 승인 전)

RFC-003 자체의 완성도를 검증하는 체크리스트.

- [ ] §3.1~§3.7의 모든 현행/변경 쌍이 RFC-001 원문과 정확히 일치하는지 확인
- [ ] §3.3 매니페스트 JSON이 파싱 가능한 유효한 JSON인지 확인
- [ ] §3.5 설치 흐름의 모든 코드 블록이 Swift 주석 형태로 문법적으로 유효
- [ ] §6 구현 상세의 Phase 간 의존성에 순환이 없는지 확인
- [ ] §7 리스크의 각 완화책이 구현 가능한지 (Tauri 소스에서 선례 존재)
- [ ] Tauri 참조 모델(§5)의 인용이 실제 `updater.rs` 소스와 일치하는지 확인
- [ ] 에러 코드(`authenticationFailed`, `packageInstallFailed`)가 기존 `KSError.Code`와 네이밍 컨벤션이 일관적인지 확인 (camelCase, 동사(ed/failed) 접미어)
- [ ] 모든 신규 타입이 `Sendable` + `Codable` (와이어 전송 타입) 또는 `Sendable` (내부 전용) 준수
- [ ] `KSProcessLauncher` 프로토콜이 테스트 주입을 위한 최소 표면만 노출하는지 확인
- [ ] `KSPluginContext.quit()` 추가가 기존 플러그인(`KSProcessPlugin` 등)의 컴파일을 깨지 않는지 확인 (프로토콜 default 구현 여부)
- [ ] `Package.swift` 변경이 기존 타겟 의존성 그래프와 충돌하지 않는지 확인
