/// macOS Developer ID 코드사이닝 + 공증 + 스테이플 파이프라인 (RFC-008 Phase 1).
///
/// 본 모듈은 **순수 함수**로 명령 시퀀스를 계산하고, 별도 `execute` 단계에서
/// 실행한다. 이렇게 분리해야:
///   1. 단위 테스트에서 명령 인자 순서 / 옵션 조합을 결정적으로 검증 가능
///   2. `--dryrun` 플래그가 동일 시퀀스를 stdout 으로 출력만 가능
///   3. 실제 실행은 macOS 호스트에서만 `Process` 를 띄우고, 그 외 플랫폼은
///      안전하게 no-op
///
/// 5 단계 파이프라인 (RFC-008 §P1):
///   1. (entitlementsPath 미지정 시) Hardened Runtime 기본 entitlements 생성
///   2. `codesign --force --options=runtime --timestamp --entitlements <path> -s <identity> <.app>`
///   3. `ditto -c -k --keepParent <.app> <.zip>`
///   4. `xcrun notarytool submit <.zip> --keychain-profile <profile> --wait`
///   5. `xcrun stapler staple <.app>`
public import Foundation
public import KalsaeCore

extension KSPackager {

    /// 한 단계 명령. `command` 는 PATH 조회 대상이고, `args` 는 그대로 전달된다.
    public struct MacSignStep: Sendable, Equatable {
        public let command: String
        public let args: [String]
        /// 사용자 가독용 라벨 (`"codesign"`, `"notarize"`, …).
        public let label: String

        public init(command: String, args: [String], label: String) {
            self.command = command
            self.args = args
            self.label = label
        }
    }

    /// Developer ID 사이닝 입력값 — 순수 계산용 (파일 I/O 없음).
    public struct MacSignInput: Sendable {
        public var bundle: URL  // <App>.app
        public var zipOutput: URL  // <App>-<ver>.zip (ditto 산출물)
        public var identity: String  // codesign -s 값
        public var notarytoolProfile: String?  // store-credentials 프로파일명
        /// 사용자가 직접 지정한 entitlements.plist. 미지정 시 기본 plist 를
        /// `defaultEntitlementsPath` 위치에 생성한다.
        public var entitlementsPath: URL?
        /// `entitlementsPath == nil` 일 때 기본 plist 를 쓸 위치.
        public var defaultEntitlementsPath: URL
        /// MAS 분기에서도 본 구조체를 재사용한다. `.macAppStore` 면
        /// `--options=runtime` 을 빼고 `productbuild` 단계를 별도로 호출한다.
        public var target: KSDistributionTarget

        public init(
            bundle: URL,
            zipOutput: URL,
            identity: String,
            notarytoolProfile: String?,
            entitlementsPath: URL?,
            defaultEntitlementsPath: URL,
            target: KSDistributionTarget
        ) {
            self.bundle = bundle
            self.zipOutput = zipOutput
            self.identity = identity
            self.notarytoolProfile = notarytoolProfile
            self.entitlementsPath = entitlementsPath
            self.defaultEntitlementsPath = defaultEntitlementsPath
            self.target = target
        }
    }

    // MARK: - 명령 시퀀스 계산 (pure)

    /// `input` 에 대해 codesign → ditto → notarize → staple 명령 시퀀스를 빌드한다.
    /// 파일 I/O 는 일으키지 않는다. `notarytoolProfile == nil` 이면 4·5단계를
    /// 생략하고 codesign 까지만 수행한다(공증은 후속 단계로 미룸).
    public static func planDeveloperIDSigning(_ input: MacSignInput) -> [MacSignStep] {
        var steps: [MacSignStep] = []

        let entitlements = input.entitlementsPath ?? input.defaultEntitlementsPath

        // (2) codesign
        var codesignArgs = [
            "--force",
            "--options=runtime",
            "--timestamp",
            "--entitlements", entitlements.path,
            "--sign", input.identity,
            input.bundle.path,
        ]
        if input.target == .macAppStore {
            // MAS 에서는 hardened runtime 이 아니라 sandbox + provisioning.
            // 본 함수는 호출되지 않지만 안전한 분기로 옵션을 빼둔다.
            codesignArgs.removeAll(where: { $0 == "--options=runtime" })
        }
        steps.append(.init(command: "codesign", args: codesignArgs, label: "codesign"))

        // (3) ditto
        steps.append(
            .init(
                command: "ditto",
                args: [
                    "-c", "-k", "--sequesterRsrc", "--keepParent",
                    input.bundle.path, input.zipOutput.path,
                ],
                label: "ditto"))

        // (4) notarytool submit + wait
        if let profile = input.notarytoolProfile, !profile.isEmpty {
            steps.append(
                .init(
                    command: "xcrun",
                    args: [
                        "notarytool", "submit", input.zipOutput.path,
                        "--keychain-profile", profile, "--wait",
                    ],
                    label: "notarize"))

            // (5) stapler staple
            steps.append(
                .init(
                    command: "xcrun",
                    args: ["stapler", "staple", input.bundle.path],
                    label: "staple"))
        }

        return steps
    }

    // MARK: - 기본 entitlements (Hardened Runtime)

    /// Developer ID 모드의 기본 Hardened Runtime entitlements.
    /// WKWebView 가 JIT 을 요구하므로 `allow-jit=true` 만 켠다. 그 외는
    /// 보수적으로 비활성 — 사용자 앱이 추가 권한이 필요하면 `--entitlements`
    /// 로 직접 plist 를 지정한다.
    public static func renderDefaultHardenedRuntimeEntitlements() -> String {
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>com.apple.security.cs.allow-jit</key>
                <true/>
                <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
                <false/>
                <key>com.apple.security.cs.disable-library-validation</key>
                <false/>
                <key>com.apple.security.cs.allow-dyld-environment-variables</key>
                <false/>
            </dict>
            </plist>
            """
    }

    // MARK: - 실행기

    /// 계산된 시퀀스를 실제로 실행하거나(`dryRun=false`), stdout 에 출력한다(`dryRun=true`).
    /// macOS 외 플랫폼에서는 `dryRun=false` 라도 안전하게 출력만 수행하며,
    /// `warnings` 에 "skipped on non-macOS host" 를 기록한다.
    public static func executeMacSignSteps(
        _ steps: [MacSignStep],
        dryRun: Bool,
        warnings: inout [String]
    ) throws {
        #if os(macOS)
            if dryRun {
                printPlanned(steps)
                return
            }
            for step in steps {
                print("  ▶ \(step.label): \(step.command) \(step.args.joined(separator: " "))")
                try shell(command: step.command, arguments: step.args)
            }
        #else
            printPlanned(steps)
            if !dryRun {
                warnings.append(
                    "Developer ID signing pipeline skipped on non-macOS host. "
                    + "Re-run `kalsae build --store devid` on macOS to actually sign + notarize.")
            }
        #endif
    }

    private static func printPlanned(_ steps: [MacSignStep]) {
        for step in steps {
            print("  • \(step.label): \(step.command) \(step.args.joined(separator: " "))")
        }
    }
}
