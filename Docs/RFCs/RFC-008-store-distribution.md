# RFC-008 — Store 배포 (Microsoft Store / Apple Stores)

| 항목 | 내용 |
|------|------|
| 상태 | 구현 완료 (Implemented) |
| 날짜 | 2026-05-11 |
| 영향 범위 | `KalsaeCore` (Config, Distribution), `KalsaeCLI` (BuildCommand, Packager*), `KalsaePlatformWindows`, `KalsaePlatformMac` PAL, `.github/workflows/` |
| 관련 | RFC-006 (iOS release) — P4 에 흡수, RFC-007 (Android release) — 본 RFC 비대상 |

---

## 1. 동기 (Motivation)

Kalsae 의 기존 `kalsae build` 는 개발자용 산출물(NSIS / `.app` / `.AppImage`)만
생성한다. 실제 사용자에게 배포하려면 다음 3대 스토어 채널에 맞춘 코드사이닝,
공증, 매니페스트, sandbox entitlement 가 필요하다:

1. **Apple Developer ID + notarize** — 직접 배포(`.app` + Gatekeeper 통과)
2. **Mac App Store** — `.pkg` (App Sandbox + provisioning profile)
3. **Microsoft Store** — `.msix` (Partner Center Publisher + WACK)
4. **iOS App Store** — `.ipa` (xcodebuild archive + altool)

본 RFC 는 이 4개 채널을 단일 CLI 플래그(`--store`) 와 단일 `Kalsae.json`
스키마(`distribution` + `permissions`) 로 통합한다.

---

## 2. 목표 / 비목표

### 목표

- `--store <target>` 한 줄로 모든 스토어 산출물을 생성 (CI 친화적)
- `Kalsae.json` 의 `distribution`/`permissions` 가 단일 진실 공급원(SoT) —
  entitlements, Info.plist `NS*UsageDescription`, MSIX `<Capabilities>`,
  `AppxManifest` 식별자가 모두 여기서 파생
- 스토어 정책 위반 가능 PAL API 는 sandbox/MSIX 모드에서 **no-op + 경고**
  (앱이 throw 처리에 신경쓰지 않아도 됨)
- 모든 패키저는 **순수 plan 함수 + 실행자** 구조 — 명령 시퀀스를 테스트로
  검증 가능

### 비목표

- WACK / Transporter 자동 실행 (수동 또는 별도 워크플로)
- Partner Center / App Store Connect 메타데이터 자동 입력
- Android Play Store (별도 RFC-007)
- 인증서 자동 발급 / 갱신

---

## 3. 설계 개요

### 3.1 CLI

```
kalsae build --store <developer|developer-id|mac-app-store|microsoft-store|ios-app-store>
                    (또는 단축: dev|devid|mas|win-store|ios-appstore)
```

- 미지정 시 `Kalsae.json` 의 `distribution.target`, 그것도 없으면 `developer`
- 추가 스토어별 플래그는 §3.5

### 3.2 Kalsae.json 스키마 추가

```jsonc
{
  "distribution": {
    "target": "developer",
    "appleTeamID": "ABCDE12345",
    "windowsPublisher": "CN=Acme Corp, O=Acme Corp, C=KR",
    "bundleIdentifier": "dev.kalsae.demo"
  },
  "permissions": {
    "camera": { "enabled": true, "reason": "Scan QR codes." },
    "microphone": false,
    "photoLibrary": false,
    "location": false,
    "networkServer": false
  }
}
```

- 두 섹션 모두 생략 가능 — 기본값(`developer` / 모두 거부)
- `permissions.camera` 등은 `bool` 또는 `{enabled, reason}` 객체 둘 다 허용

### 3.3 런타임 노출

`KSApp.distributionTarget: KSDistributionTarget` — PAL 가 sandbox/MSIX
no-op 분기를 결정하는 데 사용.

### 3.4 패키저 아키텍처

각 스토어 패키저는 **순수 plan 함수 + 실행자** 패턴:

```swift
public static func planXxxPipeline(_ input: XxxInput) -> [MacSignStep]
public static func executeXxxSteps(_ steps:, dryRun: Bool, warnings: inout [String]) throws
```

- `plan*` 은 부수효과 없음 → 단위 테스트로 명령어 시퀀스 검증
- `execute*` 는 macOS / Windows 만 실제 `Process` 호출, 다른 호스트에서는
  print + warning

| 패키저 | 파일 | 단계 |
|---|---|---|
| Developer ID | [PackagerMacSigning.swift](../../Sources/KalsaeCLI/Support/PackagerMacSigning.swift) | codesign → ditto → notarytool → staple |
| Mac App Store | [PackagerMacAppStore.swift](../../Sources/KalsaeCLI/Support/PackagerMacAppStore.swift) | copy-provisioning → codesign → productbuild |
| MSIX | [PackagerMSIX.swift](../../Sources/KalsaeCLI/Support/PackagerMSIX.swift) | manifest → MakeAppx → signtool |
| iOS App Store | [PackagerIOS.swift](../../Sources/KalsaeCLI/Support/PackagerIOS.swift) | xcodebuild archive → exportArchive → altool (옵션) |

### 3.5 스토어별 CLI 플래그

```
--codesign-identity <id>     공통: codesign / xcodebuild CODE_SIGN_IDENTITY
--notarytool-profile <name>  devid: notarytool keychain profile
--entitlements <path>        devid/mas: entitlements.plist override
--installer-identity <id>    mas: productbuild --sign
--provision-profile <path>   mas/ios: embedded.provisionprofile
--msix-signtool-cmd "<tpl>"  win-store: signtool 템플릿 ({file} 치환)
--ios-project <path>         ios: .xcodeproj 또는 .xcworkspace
--ios-scheme <name>          ios: xcodebuild scheme
--ios-export-method <m>      ios: app-store-connect|app-store|ad-hoc|enterprise|development
--asc-key <id>               ios: App Store Connect API Key ID (upload 시)
--asc-issuer <uuid>          ios: App Store Connect API Issuer UUID (upload 시)
--dryrun                     모든 패키저: 명령어만 출력
```

---

## 4. PAL 분기 (no-op + 경고)

스토어 정책상 비호환인 PAL API 는 런타임에 `distributionTarget` 또는
sandbox 컨텍스트를 감지해 no-op 분기.

### 4.1 Windows MSIX

`KSWindowsAppPackageContext.isMSIXPackaged()` 가
`GetCurrentPackageFullName()` 또는 `KALSAE_MSIX_CONTEXT` 환경변수로 판단.

- [KSWindowsAutostartBackend](../../Sources/KalsaePlatformWindows/PAL/KSWindowsAutostartBackend.swift) `enable/disable/isEnabled` →
  매니페스트 `<windows.startupTask>` 가 처리, PAL 은 no-op + 경고
- [KSWindowsDeepLinkBackend](../../Sources/KalsaePlatformWindows/PAL/KSWindowsDeepLinkBackend.swift) `register/unregister/isRegistered` →
  매니페스트 `<uap:Extension Category="windows.protocol">` 가 처리, PAL no-op

### 4.2 macOS App Sandbox (MAS)

`KSMacAppPackageContext.isSandboxed()` 가 `KALSAE_MAS_CONTEXT` 또는
`APP_SANDBOX_CONTAINER_ID` 환경변수로 판단.

- [KSMacDeepLinkBackend](../../Sources/KalsaePlatformMac/PAL/KSMacDeepLinkBackend.swift) `register/unregister/isRegistered` →
  Launch Services 에 의해 Info.plist `CFBundleURLTypes` 자동 처리, no-op
- [KSMacAcceleratorBackend](../../Sources/KalsaePlatformMac/PAL/KSMacAcceleratorBackend.swift) → sandbox 에서 global `NSEvent` monitor
  skip (local-only)
- 기타 (Tray, Notification, Dialog, Clipboard, Window, Menu, Autostart) → 변경 없음

### 4.3 iOS

iOS PAL 은 `runOnMain` 부재로 별도 host UIKit 앱에 위임.
[KSiOSDialogBackend](../../Sources/KalsaePlatformIOS/PAL/KSiOSDialogBackend.swift) 는
injectable 핸들러 패턴 — host 앱이 `UIAlertController` 구체 구현을 주입.
[KSiOSMenuBackend](../../Sources/KalsaePlatformIOS/PAL/KSiOSMenuBackend.swift) 는
RFC-004 §4 의 의도된 `unsupportedPlatform` 유지 (iOS 는 persistent menu bar 없음).

---

## 5. Entitlements / Capabilities 자동 매핑

`EntitlementsGenerator.swift` 가 `Kalsae.json` → MAS entitlements.plist
렌더링을 담당. 매핑표:

| Kalsae 설정 | macOS entitlement | MSIX capability |
|---|---|---|
| (항상, MAS) | `app-sandbox=true`, `cs.allow-jit=true`, `application-identifier`, `team-identifier` | `runFullTrust` (desktop bridge) |
| Dialog 사용 | `files.user-selected.read-write` | — |
| `security.http.allow` 비어있지 않음 | `network.client` | `internetClient` |
| `permissions.networkServer=true` | `network.server` | `internetClientServer` |
| `permissions.camera=true` | `device.camera` + `NSCameraUsageDescription` | `webcam` |
| `permissions.microphone=true` | `device.audio-input` + `NSMicrophoneUsageDescription` | `microphone` |
| `permissions.photoLibrary=true` | `NSPhotoLibraryUsageDescription` (iOS) | `picturesLibrary` |
| `permissions.location=true` | `personal-information.location` + `NSLocationWhenInUseUsageDescription` | `location` |

`--entitlements <path>` 로 사용자 plist 전체 override 가능.

---

## 6. CI 워크플로

수동 dispatch 전용 4개 워크플로. 인증서/프로필은 GitHub Secrets 로 주입.

- [.github/workflows/store-macos-devid.yml](../../.github/workflows/store-macos-devid.yml)
- [.github/workflows/store-macos-mas.yml](../../.github/workflows/store-macos-mas.yml)
- [.github/workflows/store-windows-msix.yml](../../.github/workflows/store-windows-msix.yml)
- [.github/workflows/store-ios-appstore.yml](../../.github/workflows/store-ios-appstore.yml)

각 워크플로는 `dry-run` 입력을 지원 — 인증서 없이도 plan 검증 가능.

---

## 7. 구현 결과 요약

| 단계 | 산출물 | 테스트 |
|---|---|---|
| P0 — 스키마 + CLI + Doctor | KSDistributionTarget, KSPermissionsConfig, KSDistributionConfig, BuildCommand `--store`, Doctor `--store` | 8 |
| P1 — Developer ID notarize | PackagerMacSigning + BuildCommand 통합 | 8 |
| P2 — Microsoft Store MSIX | PackagerMSIX + Windows PAL no-op + AppPackageContext | 20 |
| P3 — Mac App Store | EntitlementsGenerator + PackagerMacAppStore + Mac PAL MAS no-op | 18 |
| P4 — iOS App Store | PackagerIOS + BuildCommand 5개 신규 플래그 | 15 |
| P5 — CI workflows | 4개 store-*.yml | (YAML lint) |

**총 69 store-test 통과 + 전체 회귀 무사고.**

---

## 8. 사용 예시

### 8.1 Developer ID (notarize)

```bash
# Kalsae.json: distribution.target = "developer-id", appleTeamID = "ABCDE12345"
kalsae build --store devid \
  --codesign-identity "Developer ID Application: Acme (ABCDE12345)" \
  --notarytool-profile kalsae-notarytool
```

### 8.2 Mac App Store

```bash
kalsae build --store mas \
  --codesign-identity "3rd Party Mac Developer Application: Acme (ABCDE12345)" \
  --installer-identity "3rd Party Mac Developer Installer: Acme (ABCDE12345)" \
  --provision-profile ./mas/embedded.provisionprofile
```

### 8.3 Microsoft Store

```bash
kalsae build --store win-store \
  --msix-signtool-cmd 'signtool.exe sign /fd SHA256 /f cert.pfx /p $env:PFX_PASSWORD {file}'
```

### 8.4 iOS App Store

```bash
kalsae build --store ios-appstore \
  --ios-project ./ios/Demo.xcworkspace \
  --ios-scheme Demo \
  --ios-export-method app-store-connect \
  --asc-key KEY123 --asc-issuer 11111111-2222-3333-4444-555555555555
```

---

## 9. 향후 확장

- WACK 자동화 (Windows-latest 이미지에 Windows App Cert Kit 설치)
- App Store Connect 메타데이터/스크린샷 자동 업로드 (Fastlane 통합)
- Linux Flatpak / Snap 배포 (별도 RFC)
- Android Play Store (RFC-007)
