# RFC-005 — iOS 플랫폼 Release 상태 전환

| 항목 | 내용 |
|------|------|
| 상태 | 초안 (Draft) |
| 날짜 | 2026-05-09 |
| 영향 범위 | `KalsaePlatformIOS`, `KalsaeCLI` (PackagerIOS, BuildCommand), `Kalsae` (KSApp) |
| 관련 | RFC-002 (build-perf), `PackagerMac.swift`, `BuildCommand.swift` |

---

## 1. 동기 (Motivation)

Kalsae의 iOS PAL(Platform Abstraction Layer)은 현재 **preview** 상태다. 모든 PAL 백엔드
인터페이스가 구현되어 있고 `KSApp.boot` 통합도 완료되었으나, 다음 항목이 부족해
실제 앱 배포에 사용할 수 없다:

1. **iOS `.app` 번들 패키저**가 없어 `kalsae build`가 iOS 산출물을 생성하지 못함
2. **일부 PAL 백엔드가 stub/no-op**으로만 구현되어 실제 UIKit 동작을 하지 않음
   (`KSiOSDialogBackend`, `KSiOSMenuBackend`)
3. **시뮬레이터 통합 테스트**가 부족함
4. **문서화**가 미흡함

본 RFC는 iOS 플랫폼을 preview → stable로 전환하기 위한 구체적인 작업 항목을 정의한다.

---

## 2. 목표 / 비목표

### 목표

- `kalsae build`가 macOS 호스트에서 iOS `.app` 번들을 생성할 수 있다
- iOS PAL 백엔드가 기본 UIKit 구현을 제공한다 (Dialog, Menu)
- 시뮬레이터에서 통합 테스트를 실행할 수 있다
- 문서화가 완료된다

### 비목표

- iOS 코드사이닝 자동화 (Xcode 수동 설정 필요)
- App Store Connect 업로드 자동화
- iOS 전용 플러그인 (예: HealthKit, ARKit)
- Android 플랫폼 release (별도 RFC)

---

## 3. 설계

### 3.1 iOS 패키저 (`PackagerIOS.swift`)

macOS의 `PackagerMac.swift`를 모델로 iOS `.app` 번들 패키저를 구현한다.

#### 3.1.1 iOS `.app` 번들 구조

```
<App>.app/
  Info.plist                    # CFBundleIdentifier, 버전, 디바이스 요구사항 등
  <executable>                  # SwiftPM으로 빌드된 iOS 실행 파일 (arm64)
  Kalsae.json                   # 패키징 시 rewrite (frontendDist=".", devtools=false)
  Assets/
    index.html                  # 프론트엔드 dist 내용 (인라인 복사)
    ...                         # 기타 프론트엔드 자산
  Assets/AppIcon.appiconset/    # 아이콘 세트 (다양한 크기)
    Contents.json
    icon-20.png
    icon-20@2x.png
    icon-20@3x.png
    icon-29.png
    icon-29@2x.png
    icon-29@3x.png
    icon-40.png
    icon-40@2x.png
    icon-40@3x.png
    icon-60@2x.png
    icon-60@3x.png
    icon-1024.png               # App Store 용
  Base.lproj/
    LaunchScreen.storyboard     # 패키저가 생성하는 기본 LaunchScreen
```

#### 3.1.2 `KSPackager.IOSOptions` 구조체

```swift
extension KSPackager {
    public struct IOSOptions: Sendable {
        public var executablePath: URL
        public var configPath: URL
        public var frontendDist: URL?
        public var output: URL
        public var appName: String
        public var version: String
        public var identifier: String
        public var iconPath: URL?          // 1024x1024 PNG 소스
        public var minimumOSVersion: String  // 기본 "16.0"
        public var stripSourceMaps: Bool
        public var stripExtensions: [String]

        public init(
            executablePath: URL,
            configPath: URL,
            frontendDist: URL?,
            output: URL,
            appName: String,
            version: String,
            identifier: String,
            iconPath: URL? = nil,
            minimumOSVersion: String = "16.0",
            stripSourceMaps: Bool = true,
            stripExtensions: [String] = []
        )
    }
}
```

#### 3.1.3 `KSPackager.runIOS(_:)` 구현 단계

1. **출력 디렉터리 준비**: `<output>/<App>.app` 생성 (기존 삭제 후 재생성)
2. **실행 파일 복사**: `.build/release/<executable>` → `<App>.app>/<executable>`
3. **Info.plist 생성**: iOS 메타데이터 포함 (아래 §3.1.4 참조)
4. **Kalsae.json 복사 및 rewrite**:
   - `frontendDist` → `"Assets"` (macOS의 `"."`와 달리 iOS는 Assets/ 사용)
   - `devtools` → `false` (release 강제)
   - `devServerURL` → `"about:blank"` (release 차단)
5. **프론트엔드 dist 복사**: dist 내용 → `<App>.app>/Assets/` (인라인 복사)
6. **Strip 불필요 파일**: 소스맵 등 제거 (`KSBundleAnalyzer.strip`)
7. **아이콘 생성**: 1024x1024 PNG 소스 → 다양한 크기로 리사이즈하여 `Assets/AppIcon.appiconset/` 배치
8. **LaunchScreen 생성**: 기본 `Base.lproj/LaunchScreen.storyboard` 작성
9. **Report 반환**

#### 3.1.4 iOS Info.plist 템플릿

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>{appName}</string>
    <key>CFBundleIdentifier</key>
    <string>{identifier}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>{appName}</string>
    <key>CFBundleDisplayName</key>
    <string>{appName}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>{version}</string>
    <key>CFBundleVersion</key>
    <string>{version}</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>UILaunchStoryboardName</key>
    <string>LaunchScreen</string>
    <key>UIRequiredDeviceCapabilities</key>
    <array>
        <string>arm64</string>
    </array>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
    </array>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
```

#### 3.1.5 아이콘 생성 전략

사용자가 `--icon`으로 1024x1024 PNG를 제공하면, 패키저가 `KSIconResizer` 유틸리티를 통해
다음 크기로 리사이즈하여 `Assets/AppIcon.appiconset/`에 배치한다:

| 파일명 | 크기 | 배수 | 용도 |
|--------|------|------|------|
| `icon-20.png` | 20×20 | 1x | Notification |
| `icon-20@2x.png` | 40×40 | 2x | Notification |
| `icon-20@3x.png` | 60×60 | 3x | Notification |
| `icon-29.png` | 29×29 | 1x | Settings |
| `icon-29@2x.png` | 58×58 | 2x | Settings |
| `icon-29@3x.png` | 87×87 | 3x | Settings |
| `icon-40.png` | 40×40 | 1x | Spotlight |
| `icon-40@2x.png` | 80×80 | 2x | Spotlight |
| `icon-40@3x.png` | 120×120 | 3x | Spotlight |
| `icon-60@2x.png` | 120×120 | 2x | App (iPhone) |
| `icon-60@3x.png` | 180×180 | 3x | App (iPhone) |
| `icon-1024.png` | 1024×1024 | 1x | App Store |

`Contents.json`:
```json
{
  "images": [
    { "size": "20x20", "idiom": "iphone", "filename": "icon-20.png", "scale": "1x" },
    { "size": "20x20", "idiom": "iphone", "filename": "icon-20@2x.png", "scale": "2x" },
    { "size": "20x20", "idiom": "iphone", "filename": "icon-20@3x.png", "scale": "3x" },
    { "size": "29x29", "idiom": "iphone", "filename": "icon-29.png", "scale": "1x" },
    { "size": "29x29", "idiom": "iphone", "filename": "icon-29@2x.png", "scale": "2x" },
    { "size": "29x29", "idiom": "iphone", "filename": "icon-29@3x.png", "scale": "3x" },
    { "size": "40x40", "idiom": "iphone", "filename": "icon-40.png", "scale": "1x" },
    { "size": "40x40", "idiom": "iphone", "filename": "icon-40@2x.png", "scale": "2x" },
    { "size": "40x40", "idiom": "iphone", "filename": "icon-40@3x.png", "scale": "3x" },
    { "size": "60x60", "idiom": "iphone", "filename": "icon-60@2x.png", "scale": "2x" },
    { "size": "60x60", "idiom": "iphone", "filename": "icon-60@3x.png", "scale": "3x" },
    { "size": "1024x1024", "idiom": "ios-marketing", "filename": "icon-1024.png", "scale": "1x" }
  ],
  "info": { "author": "kalsae", "version": 1 }
}
```

#### 3.1.6 LaunchScreen.storyboard 템플릿

```xml
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB"
  version="3.0" toolsVersion="21701" targetRuntime="AppleSDK"
  propertyAccessControl="none" useAutolayout="YES"
  launchScreen="YES" useTraitCollections="YES"
  useSafeAreas="YES" colorMatched="YES">
    <device id="retina6_72" orientation="portrait"
      appearance="light"/>
    <dependencies>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin"
          version="21678"/>
        <capability name="Safe area layout guides"
          minToolsVersion="9.0"/>
        <capability name="documents saved in the Xcode 8 format"
          minToolsVersion="8.0"/>
    </dependencies>
    <scenes>
        <scene sceneID="01J-lp-oVM">
            <objects>
                <viewController id="01J-lp-oVM"
                  sceneMemberID="viewController">
                    <view key="view" contentMode="scaleToFill"
                      id="Ze5-6b-2t3">
                        <rect key="frame" x="0.0" y="0.0"
                          width="393" height="852"/>
                        <autoresizingMask key="autoresizingMask"
                          widthSizable="YES" heightSizable="YES"/>
                        <subviews>
                            <label opaque="NO" userInteractionEnabled="NO"
                              contentMode="left" horizontalHuggingPriority="251"
                              verticalHuggingPriority="251"
                              text="{appName}" textAlignment="center"
                              lineBreakMode="tailTruncation"
                              baselineAdjustment="alignBaselines"
                              adjustsFontSizeToFit="NO"
                              translatesAutoresizingMaskIntoConstraints="NO"
                              font="UICTFontTextStyleTitle1">
                                <color key="textColor"
                                  red="0.0" green="0.0" blue="0.0"
                                  alpha="1" colorSpace="custom"
                                  customColorSpace="sRGB"/>
                            </label>
                        </subviews>
                        <viewLayoutGuide key="safeArea"
                          id="6Tk-OE-BBY"/>
                        <color key="backgroundColor"
                          red="1" green="1" blue="1" alpha="1"
                          colorSpace="custom"
                          customColorSpace="sRGB"/>
                        <constraints>
                            <constraint firstItem="6Tk-OE-BBY"
                              firstAttribute="centerX"
                              secondItem="label" secondAttribute="centerX"/>
                            <constraint firstItem="6Tk-OE-BBY"
                              firstAttribute="centerY"
                              secondItem="label" secondAttribute="centerY"/>
                        </constraints>
                    </view>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder"
                  id="iYj-Kq-Ea1" userLabel="First Responder"
                  sceneMemberID="firstResponder"/>
            </objects>
            <point key="canvasLocation" x="53" y="375"/>
        </scene>
    </scenes>
</document>
```

### 3.2 BuildCommand iOS 분기

#### 3.2.1 `BuildCommand.swift` 수정

`runPackage(configuration:configURL:config:)` 메서드에 iOS 분기 추가:

```swift
private func runPackage(configuration: String, configURL: URL, config: KSConfig) throws {
    let fm = FileManager.default
    let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
    let info = parseAppInfo(config: config)

    #if os(Windows)
        try runPackageWindows(...)
    #elseif os(macOS)
        // macOS 호스트에서 iOS 패키징 지원
        if let target, target.lowercased().contains("ios") {
            try runPackageIOS(...)
        } else {
            try runPackageMacOS(...)
        }
    #else
        print("⚠  Packaging is not supported on this host OS yet.")
    #endif
}
```

#### 3.2.2 `runPackageIOS` 구현

```swift
#if os(macOS)
private func runPackageIOS(
    configuration: String, configURL: URL,
    info: AppInfo, cwd: URL, fm: FileManager
) throws {
    let buildDir = cwd.appendingPathComponent(".build/\(configuration)")
    let exeURL = buildDir.appendingPathComponent(info.executableName)
    guard fm.fileExists(atPath: exeURL.path) else {
        throw ValidationError("Built executable not found at \(exeURL.path).")
    }

    let distURL: URL? = {
        let resolved = KSBuildPlan.resolveDistURL(
            config: config, configURL: configURL, cwd: cwd, distOverride: dist)
        return fm.fileExists(atPath: resolved.path) ? resolved : nil
    }()

    let outputURL: URL = {
        if let o = output {
            return URL(fileURLWithPath: o, relativeTo: cwd)
        }
        return cwd.appendingPathComponent("dist/\(info.appName)-\(info.version)-ios")
    }()
    try fm.createDirectory(at: outputURL, withIntermediateDirectories: true)

    let opts = KSPackager.IOSOptions(
        executablePath: exeURL,
        configPath: configURL,
        frontendDist: distURL,
        output: outputURL,
        appName: info.appName,
        version: info.version,
        identifier: info.identifier,
        iconPath: icon.map { URL(fileURLWithPath: $0, relativeTo: cwd) },
        stripSourceMaps: config.build.stripSourceMaps,
        stripExtensions: config.build.stripExtensions)

    print("📦  Packaging \(info.appName).app v\(info.version) (iOS)")
    let report = try KSPackager.runIOS(opts)
    print(report.description)
}
#endif
```

#### 3.2.3 CLI 옵션 확장

`BuildCommand`에 iOS 관련 옵션 추가:
- `--target KalsaePlatformIOS` (iOS 타겟 지정)
- `--arch arm64` (iOS는 arm64만 허용, 검증 로직 추가)

### 3.3 iOS PAL 안정화

#### 3.3.1 `KSiOSDialogBackend` 기본 UIKit 구현

현재 핸들러 주입형으로만 동작하지만, release를 위해 **기본 UIKit 구현**을 제공한다:

**파일**: `Sources/KalsaePlatformIOS/PAL/KSiOSDialogBackend.swift`

변경 사항:
- `init()`에서 기본 핸들러를 자동 설치
- `onOpenFile` 기본값: `UIDocumentPickerViewController`를 사용한 파일 선택
- `onMessage` 기본값: `UIAlertController`를 사용한 알림 표시
- `onSaveFile` 기본값: `UIDocumentPickerViewController` (export) 사용
- `onSelectFolder` 기본값: `UIDocumentPickerViewController` (folder) 사용

```swift
public init() {
    // 기본 UIKit 핸들러 설치
    self._onOpenFile = { [weak self] options, parent in
        guard let self else { return [] }
        return await self.presentDocumentPicker(
            for: .import, options: options, parent: parent)
    }
    self._onMessage = { [weak self] options, parent in
        guard let self else { return .ok }
        return await self.presentAlert(options: options, parent: parent)
    }
    // ...
}
```

`UIDocumentPickerViewController`와 `UIAlertController`는 `MainActor`에서만
표시할 수 있으므로, `KSiOSDialogBackend` 내부에 `@MainActor` 헬퍼 메서드를 추가한다.

#### 3.3.2 `KSiOSMenuBackend` UIMenu 기반 구현

**파일**: `Sources/KalsaePlatformIOS/PAL/KSiOSMenuBackend.swift`

변경 사항:
- `showContextMenu`: iOS 16+ `UIMenu`를 사용한 팝오버 메뉴 표시
- `installAppMenu`: iOS에는 앱 메뉴 개념이 없으므로 no-op 유지 (문서화)
- `installWindowMenu`: iOS에는 윈도우 메뉴 개념이 없으므로 no-op 유지 (문서화)

```swift
public func showContextMenu(
    _ items: [KSMenuItem],
    at point: KSPoint,
    in handle: KSWindowHandle?
) async throws(KSError) {
    guard #available(iOS 16, *) else {
        throw KSError.unsupportedPlatform(
            "Context menus require iOS 16+")
    }
    // KSiOSHandleRegistry에서 WKWebView를 찾아 UIMenu 표시
    // ...
}
```

### 3.4 테스트 강화

#### 3.4.1 시뮬레이터 통합 테스트

**파일**: `Tests/KalsaePlatformIOSTests/IOSPALIntegrationTests.swift`

추가할 테스트:
- `KSiOSDialogBackend` 기본 핸들러 동작 검증 (시뮬레이터)
- `KSiOSWebViewHost` 실제 탐색 및 IPC 메시지 전송 검증
- `KSiOSPlatform.run()` 부트 시퀀스 검증

#### 3.4.2 CI 파이프라인

`.github/workflows/`에 iOS 시뮬레이터 테스트 단계 추가:

```yaml
- name: Run iOS Simulator Tests
  run: |
    xcodebuild test \
      -scheme Kalsae-Package \
      -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.4' \
      -testPlan KalsaePlatformIOSTests
```

### 3.5 문서화

#### 3.5.1 README.md 업데이트

iOS 플랫폼 상태를 "preview"에서 "stable"로 변경하고, iOS 빌드 요구사항 추가.

#### 3.5.2 CLI.md 업데이트

iOS 빌드 및 패키징 명령어 추가:

```bash
# iOS 빌드 (macOS 호스트)
swift build --target KalsaePlatformIOS -c release

# iOS 패키징
kalsae build --target KalsaePlatformIOS --arch arm64

# iOS 패키징 (아이콘 포함)
kalsae build --target KalsaePlatformIOS --arch arm64 --icon ./AppIcon.png
```

---


## 4. 구현 계획 (2026-05-09 보완)

### Phase 0: 설계/문서 보완 (병렬)
| 작업 | 파일 | 설명 |
|------|------|------|
| 0.1 | `Docs/RFCs/RFC-006-ios-release.md` | ATS(네트워크 보안), 아이콘 Asset Catalog, 번들 자산 경로, 기본 핸들러, 보안 헤더, 개발 워크플로 등 보완사항 명시 |

### Phase 1: 패키저/CLI/번들 구조 (순차)
| 작업 | 파일 | 설명 |
|------|------|------|
| 1.1 | `Sources/KalsaeCLI/Support/PackagerIOS.swift` | `KSPackager.IOSOptions` + `runIOS(_:)` 구현, Info.plist ATS 기본값 false, 옵션화 |
| 1.2 | `Sources/KalsaeCLI/Support/PackagerIOS.swift` | 아이콘 Asset Catalog(`.xcassets`) → `Assets.car` 생성 또는 CFBundleIcons 직접 지정, 리사이즈 macOS 전용 명확화 |
| 1.3 | `Sources/KalsaeCLI/Support/PackagerIOS.swift` | `frontendDist` 번들 상대 rewrite, 번들 내 자산 위치 일치 |
| 1.4 | `Sources/KalsaeCLI/Support/PackagerIOS.swift` | 보안 헤더(`X-Content-Type-Options`, `Referrer-Policy`) 추가 |
| 1.5 | `Sources/KalsaeCLI/Commands/BuildCommand.swift` | iOS 분기 및 arch 검증 추가 |

### Phase 2: PAL/핸들러/런타임 (병렬)
| 작업 | 파일 | 설명 |
|------|------|------|
| 2.1 | `Sources/KalsaePlatformIOS/PAL/KSiOSDialogBackend.swift` | 기본 UIKit 핸들러 내장, retain cycle 없는 패턴 적용 |
| 2.2 | `Sources/KalsaePlatformIOS/PAL/KSiOSMenuBackend.swift` | UIMenu 기반 컨텍스트 메뉴 구현 |
| 2.3 | `Sources/KalsaePlatformIOS/WebKit/KSiOSWebViewHost.swift` | 보안 헤더 추가, 번들 기준 자산 탐색 |
| 2.4 | `Sources/KalsaePlatformIOS/KSiOSPlatform.swift` | 번들 기준 자산 탐색, `UIApplicationMain`/`@main` 진입점 제약 문서화 |

### Phase 3: 테스트/문서화 (병렬)
| 작업 | 파일 | 설명 |
|------|------|------|
| 3.1 | `Tests/KalsaePlatformIOSTests/IOSPALIntegrationTests.swift` | 통합 테스트 강화 (핸들러, IPC, 자산 로딩 등) |
| 3.2 | `.github/workflows/` | iOS 시뮬레이터 CI 단계 추가 |
| 3.3 | `README.md`, `Docs/CLI.md`, `Docs/RFCs/RFC-006-ios-release.md` | 개발 워크플로, 진입점, 번들 구조, ATS/아이콘/자산 경로 등 최신화 |

---

### 주요 보완/결정사항 요약

- **ATS(네트워크 보안)**: Info.plist의 `NSAllowsArbitraryLoads`는 기본 false, 필요시만 옵트인
- **아이콘**: Asset Catalog(`.xcassets`) → `Assets.car`로 컴파일, fallback 시 CFBundleIcons 직접 지정
- **자산 경로**: 패키저가 `frontendDist`를 번들 상대 경로로 rewrite, 런타임은 `Bundle.main` 기준 자산 탐색
- **보안 헤더**: `X-Content-Type-Options`, `Referrer-Policy` 등 Linux/macOS와 동일하게 적용
- **핸들러**: `KSiOSDialogBackend` 등 기본 구현 내장, retain cycle 없는 패턴 적용
- **진입점**: `UIApplicationMain` 직접 호출과 `@main` 진입점 공존/제약 명확히 문서화
- **아이콘 리사이즈**: macOS에서만 동작, 구현 예시 명확화
- **개발 워크플로**: 시뮬레이터 개발/테스트 경로, `kalsae dev` 대체 워크플로 문서화

---

## 5. FAQ

### Q: iOS 패키징이 macOS에서만 가능한 이유는?

Apple의 iOS SDK는 macOS에서만 사용할 수 있다. SwiftPM이 iOS 크로스 컴파일을
지원하지만, 실제 `.app` 번들 생성과 코드사이닝은 macOS가 필요하다.

### Q: 아이콘 리사이즈에 외부 도구가 필요한가?

`KSIconResizer`는 순수 Swift로 구현한다. `CGImage` + `UIGraphicsImageRenderer`
(macOS의 `NSImage` + `CGContext`)를 사용하여 1024x1024 PNG를 다양한 크기로
리사이즈한다. 외부 의존성 없음.

### Q: LaunchScreen.storyboard가 바이너리가 아닌 XML인 이유는?

Interface Builder의 XML 형식(`XIB`)은 사람이 읽을 수 있고 버전 관리에 적합하다.
패키저가 동적으로 앱 이름을 삽입할 수 있어 유지보수에 유리하다.

### Q: iOS에서 `kalsae dev`는 지원하는가?

iOS 시뮬레이터에서는 `kalsae dev`가 동작할 수 있지만, 실제 기기에서는
dev 서버 URL(`http://localhost:5173`)에 접근할 수 없다. 따라서 iOS의
`kalsae dev`는 현재 범위에서 제외한다.

---

## 6. 변경 이력

| 날짜 | 변경 내용 |
|------|----------|
| 2026-05-09 | 초안 작성 |
