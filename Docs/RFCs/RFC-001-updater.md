# RFC-001 — KalsaePluginUpdater: 앱 자동 업데이터 플러그인

| 항목 | 내용 |
|------|------|
| 상태 | 초안 (Draft) |
| 날짜 | 2026-05-03 |
| 영향 범위 | 새 SwiftPM 모듈 `KalsaePluginUpdater` (선택적 의존) |
| 관련 | Phase 2 로드맵, `KSPlugin` API, `KalsaePluginProcess` |

---

## 1. 동기(Motivation)

Tauri는 `tauri-plugin-updater`를 통해 GitHub Releases / 임의 URL에서 서명된 패키지를
다운로드·검증·설치하는 경험을 제공한다. Kalsae는 현재 이에 상응하는 기능이 없다.

자동 업데이트는 **핵심 PAL(플랫폼 추상화 레이어) 바깥의 관심사**이므로 선택적 플러그인으로
분리한다. 앱이 의존하지 않으면 이 기능은 빌드·링크 과정에서 완전히 제거된다.

---

## 2. 목표 / 비목표

### 목표
- **서명 검증**: 다운로드된 패키지의 무결성을 공개 키 서명으로 보장한다.
- **플랫폼 지원**: Windows(NSIS/MSI 인스톨러), macOS(`.app` DMG), Linux(AppImage / `.deb`)
- **채널 지원**: 고정 URL, GitHub Releases, 임의 JSON 매니페스트 엔드포인트
- **IPC 통합**: JS frontend가 진행률 이벤트를 받고 업데이트를 시작·취소할 수 있다.
- **자동/수동 모드**: 백그라운드 polling 또는 앱이 직접 호출하는 명시적 검사

### 비목표
- **코드 서명 발급**: 인증서/키 발급은 범위 밖. 개발자가 서명 인프라를 제공한다.
- **macOS Sparkle 통합**: 네이티브 Sparkle 라이브러리 래핑은 v2에서 별도 고려.
- **인앱 패치(binary diff)**: 차분 패치는 v2 RFC에서 다룬다 (§8 참조).
- **루트 권한 설치**: per-user 설치 경로(AppData, ~/Applications)만 지원.

---

## 3. API 설계

### 3.1 플러그인 구성

```swift
import KalsaePluginUpdater

let updater = KSUpdaterPlugin(config: KSUpdaterConfig(
    manifestURL: URL(string: "https://example.com/releases/latest.json")!,
    publicKey: "BASE64_ENCODED_ED25519_PUBLIC_KEY",
    channel: .stable,
    checkInterval: 3600,          // 초 단위. nil → 자동 폴링 비활성화
    downloadTimeout: 120,         // 초 단위
    installMode: .quitAndInstall  // 또는 .installOnNextLaunch
))

try await KSApp.shared.install([updater])
```

### 3.2 KSUpdaterConfig

```swift
public struct KSUpdaterConfig: Sendable {
    /// 매니페스트 JSON을 반환하는 URL (§4 형식 참조)
    public var manifestURL: URL
    /// Base64 인코딩된 Ed25519 공개 키 (서명 검증에 사용)
    public var publicKey: String
    /// 릴리스 채널 ("stable" | "beta" | "nightly" | 커스텀 문자열)
    public var channel: KSReleaseChannel
    /// 자동 폴링 간격(초). nil = 수동 전용
    public var checkInterval: TimeInterval?
    /// 개별 HTTP 요청 타임아웃(초). 기본값 60
    public var downloadTimeout: TimeInterval
    /// 설치 완료 후 동작
    public var installMode: KSInstallMode
    /// 프록시 URL (nil = 시스템 설정 사용)
    public var proxyURL: URL?
}

public enum KSInstallMode: Sendable {
    /// 다운로드 완료 즉시 앱 종료 후 인스톨러 실행
    case quitAndInstall
    /// 다음 실행 시 인스톨러 대기
    case installOnNextLaunch
}
```

### 3.3 등록되는 IPC 명령

플러그인 namespace: `kalsae.updater`

| 명령 | 입력 | 반환 | 설명 |
|------|------|------|------|
| `kalsae.updater.check` | `{ channel?: string }` | `KSUpdateInfo \| null` | 업데이트 확인 |
| `kalsae.updater.download` | `{ version: string }` | `void` | 다운로드 시작 |
| `kalsae.updater.install` | `{}` | `void` | 다운로드된 패키지 설치 |
| `kalsae.updater.cancel` | `{}` | `void` | 진행 중인 다운로드 취소 |

### 3.4 이벤트 (Swift → JS)

| 이벤트 | 페이로드 | 설명 |
|--------|----------|------|
| `kalsae.updater.updateAvailable` | `KSUpdateInfo` | 새 버전 발견 |
| `kalsae.updater.downloadProgress` | `{ downloaded: number, total: number }` | 바이트 단위 |
| `kalsae.updater.downloadComplete` | `{ version: string, path: string }` | 검증 완료 후 |
| `kalsae.updater.error` | `{ code: string, message: string }` | 모든 오류 |

### 3.5 KSUpdateInfo

```typescript
interface KSUpdateInfo {
  version: string;         // 새 버전 (예: "1.2.0")
  releaseDate: string;     // ISO 8601
  releaseNotes?: string;   // 마크다운 또는 HTML
  channel: string;
  signature: string;       // Base64 Ed25519 서명 (파일 전체에 대해)
  downloadURL: string;
  downloadSize: number;    // 바이트
  mandatory: boolean;      // true → 건너뛰기 버튼 제공 안 함
}
```

---

## 4. 매니페스트 형식

서버가 반환하는 JSON 엔드포인트 형식. 플랫폼별 항목을 포함한다.

```json
{
  "schemaVersion": 1,
  "channel": "stable",
  "version": "1.2.0",
  "releaseDate": "2026-03-15T09:00:00Z",
  "releaseNotes": "### 변경사항\n- 버그 수정\n- 성능 개선",
  "mandatory": false,
  "platforms": {
    "windows-x86_64": {
      "url": "https://example.com/releases/1.2.0/myapp-1.2.0-setup.exe",
      "size": 12345678,
      "sha256": "abc123...",
      "signature": "BASE64_ED25519_SIG",
      "installerType": "nsis"
    },
    "macos-aarch64": {
      "url": "https://example.com/releases/1.2.0/myapp-1.2.0-arm64.dmg",
      "size": 9876543,
      "sha256": "def456...",
      "signature": "BASE64_ED25519_SIG",
      "installerType": "dmg"
    },
    "macos-x86_64": {
      "url": "https://example.com/releases/1.2.0/myapp-1.2.0-x64.dmg",
      "size": 10234567,
      "sha256": "ghi789...",
      "signature": "BASE64_ED25519_SIG",
      "installerType": "dmg"
    },
    "linux-x86_64": {
      "url": "https://example.com/releases/1.2.0/myapp-1.2.0-x86_64.AppImage",
      "size": 11000000,
      "sha256": "jkl012...",
      "signature": "BASE64_ED25519_SIG",
      "installerType": "appimage"
    }
  }
}
```

### 플랫폼 키 규칙
`{os}-{arch}` 형식. `os`: `windows` / `macos` / `linux`. `arch`: `x86_64` / `aarch64`.

### GitHub Releases 어댑터
`manifestURL`이 `https://api.github.com/repos/{owner}/{repo}/releases/latest` 형태이면
플러그인이 GitHub 응답을 위 형식으로 자동 변환한다. `releaseNotes`는 `body` 필드 사용.

---

## 5. 서명 스키마

### 알고리즘: Ed25519

Tauri와 동일한 알고리즘을 채택한다. 이유:
- 키 크기 작음 (32바이트 공개 키 → Base64 44자)
- 빠른 검증 (RSA 대비 현저히 빠름)
- 결정론적 서명 (랜덤 nonce 없음 → 재현 가능)
- Swift의 `CryptoKit.Curve25519.Signing` API로 구현 가능

### 서명 대상
배포 파일 전체의 SHA-256 해시값(32바이트)에 대해 Ed25519 서명을 생성한다.

```
signature = Ed25519.sign(
    message: SHA256(downloadedBytes),
    privateKey: developerPrivateKey
)
```

### 키 쌍 생성 (kalsae CLI 통합, 향후)

```bash
kalsae updater keygen
# → Outputs:
#   Private key: BASE64_PRIVATE_KEY  (개발자 로컬 보관)
#   Public key:  BASE64_PUBLIC_KEY   (Kalsae.json 또는 코드에 삽입)
```

### 검증 흐름

```
다운로드 완료
    ↓
SHA-256(파일 바이트) 계산
    ↓
매니페스트의 sha256 필드와 비교 → 불일치 시 즉시 삭제 + KSError(.checksumMismatch)
    ↓
Ed25519.verify(signature, SHA256(파일), publicKey)
    ↓
실패 시 삭제 + KSError(.signatureVerificationFailed)
    ↓
설치 진행
```

---

## 6. 다운로드 구현

### 6.1 스트리밍 다운로드
`URLSession.bytes(from:)` 비동기 스트림으로 다운로드. 청크 단위 `kalsae.updater.downloadProgress`
이벤트 emit (최소 1초 간격 또는 1% 간격 throttle).

### 6.2 임시 저장 경로
```
Windows: %TEMP%\kalsae-updates\{version}\{filename}
macOS:   $TMPDIR/kalsae-updates/{version}/{filename}
Linux:   /tmp/kalsae-updates/{version}/{filename}
```
설치 완료 또는 취소 후 디렉터리 삭제.

### 6.3 재개(Resume) — v2
현재 RFC에서는 단순 전체 재다운로드. `Range` HTTP 헤더를 이용한 재개는 v2에서 고려.

---

## 7. 설치 흐름 (플랫폼별)

### Windows (NSIS / MSI)
```swift
// installMode == .quitAndInstall
let installer = downloadedPath
// /S = 자동 무인 설치, /D=설치경로 (NSIS)
Process.launchDetached(installer, args: ["/S"])
// 앱 종료
KSApp.shared.quit()
```
- **NSIS**: `/S` 무인 플래그. 인스톨러가 같은 경로에 덮어쓴다.
- **MSI**: `msiexec /i {path} /qn REINSTALL=ALL REINSTALLMODE=vomus`

### macOS (DMG)
```swift
// 1. hdiutil attach {dmg} -mountpoint /Volumes/KalsaeUpdate
// 2. ditto /Volumes/KalsaeUpdate/{App.app} /Applications/{App.app}
// 3. hdiutil detach /Volumes/KalsaeUpdate
// 4. KSApp.shared.quit()
//    → 재실행은 NSWorkspace.shared.open 또는 LaunchServices
```
코드 서명 체크: macOS Gatekeeper가 `ditto` 후 첫 실행 시 자동 수행.

### Linux (AppImage)
```swift
// 1. 현재 AppImage 경로: ProcessInfo.processInfo.arguments[0] 또는 APPIMAGE 환경변수
// 2. 새 AppImage를 {현재경로}.new로 저장
// 3. chmod +x {새경로}
// 4. rename({새경로}, {현재경로})  — 원자적 교체
// 5. KSApp.shared.quit()
```

---

## 8. 미결 사항

아래 항목은 구현 전에 별도 결정이 필요하다.

| # | 항목 | 옵션 | 권장 |
|---|------|------|------|
| 1 | **차분 패치(binary diff)** | 전체 재다운로드 vs bsdiff/zstd-patch | v2로 연기. 현재 RFC = 전체 다운로드 |
| 2 | **롤백 전략** | 이전 버전 보존 여부, 수동 롤백 API | 이전 설치 파일 하나 보관(`{path}.bak`). 롤백 명령 `kalsae.updater.rollback` v2에 추가 |
| 3 | **매니페스트 캐싱** | TTL, 오프라인 처리 | 마지막 성공 응답을 UserDefaults/JSON 파일에 캐시. TTL = checkInterval |
| 4 | **macOS Sparkle 통합** | 자체 구현 vs Sparkle 라이브러리 의존 | v2. 현재 RFC = 자체 구현 (Sparkle 의존 없음) |
| 5 | **Windows 관리자 권한** | per-user NSIS vs system-wide MSI | per-user만 지원. MSI system-wide는 별도 entitlement 문서 필요 |
| 6 | **CLI keygen 통합** | 독립 CLI 도구 vs `kalsae updater keygen` | `kalsae updater keygen` — 기존 KalsaeCLI 확장 |
| 7 | **채널 전환** | stable→beta 강제 업그레이드 방지 | `installMode` 설정값 우선. 채널 낮추기 다운그레이드는 항상 거부 |

---

## 9. 보안 고려사항

1. **HTTPS 강제**: `manifestURL`과 모든 `downloadURL`이 `https://` 스킴이 아니면
   `KSError(.insecureURL)`로 즉시 거부한다. 개발/테스트 환경은 `allowInsecure: true`
   플래그로 명시적으로 해제 (릴리스 빌드에서는 컴파일 타임 불가).

2. **서명 없음 = 설치 불가**: 매니페스트에 `signature` 필드가 없거나 공개 키가
   설정되지 않으면 다운로드 자체를 시작하지 않는다. "서명 건너뛰기" 옵션을 제공하지
   않는다.

3. **임시 파일 권한**: 다운로드 디렉터리는 `0700` (소유자만 접근). 검증 전 파일을
   실행 경로에 두지 않는다.

4. **TOCTOU 방지**: 검증(SHA-256 + Ed25519) 직후 파일 경로를 고정하고, 설치 호출
   전까지 파일을 이동하지 않는다.

5. **중단 공격(downgrade attack) 방지**: 매니페스트의 버전이 현재 실행 중인 버전보다
   낮거나 같으면 업데이트를 제공하지 않는다. `mandatory: false`여도 동일.

6. **네트워크 오류 처리**: 타임아웃, DNS 실패, 비-2xx HTTP 응답 모두 `KSError`로
   래핑. 기존 설치 파일에는 영향을 주지 않는다.

---

## 10. 구현 단계 (참고)

RFC 승인 후 별도 사이클에서 구현한다.

1. `Sources/KalsaePluginUpdater/` 모듈 신설
   - `KSUpdaterConfig.swift`, `KSUpdaterPlugin.swift`, `KSUpdateDownloader.swift`
   - `KSUpdateInstaller+Windows.swift`, `KSUpdateInstaller+Mac.swift`, `KSUpdateInstaller+Linux.swift`
   - `KSUpdateSignatureVerifier.swift` (CryptoKit.Curve25519 사용)
2. `Package.swift` 타겟/제품 추가
3. `KalsaeCLI`에 `kalsae updater keygen` 서브커맨드 추가
4. 테스트: `Tests/KalsaePluginUpdaterTests/`
   - 매니페스트 파싱 + 버전 비교 단위 테스트
   - 서명 검증 단위 테스트 (알려진 키 쌍으로 픽스처 사용)
   - 모의 HTTP 서버로 다운로드 흐름 통합 테스트

---

## 결정 필요 항목 요약

RFC 진행 전에 다음 세 가지를 결정하면 구현이 단순해진다.

1. **차분 패치 지원**: v1에서 전체 재다운로드만 지원하고 v2로 연기?  
   _현재 권장: 연기_

2. **롤백 지원**: v1에서 단순 `.bak` 보관만? 또는 명시적 롤백 API 포함?  
   _현재 권장: `.bak` 보관, `rollback` API는 v2_

3. **macOS Sparkle**: 자체 구현 vs Sparkle 의존?  
   _현재 권장: 자체 구현(외부 의존 최소화)_
