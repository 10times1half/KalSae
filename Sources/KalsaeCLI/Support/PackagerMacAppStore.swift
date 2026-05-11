/// macOS App Store (MAS) 패키징 파이프라인 (RFC-008 Phase 3).
///
/// Developer ID 와 분리한 이유:
///   * 산출물이 `.app` 가 아니라 **`.pkg`** (productbuild)
///   * 입력에 **`embedded.provisionprofile`** 가 필수 (MAS 심사 통과 조건)
///   * codesign 옵션이 다름: `--options=runtime` 제거, sandbox entitlements 강제
///   * 공증 없음 — App Store Connect 가 심사 시 자체 검증한다
///
/// 4 단계 파이프라인:
///   1. (입력 검증) `embedded.provisionprofile` 존재 + signing identity 존재
///   2. provisionprofile 을 `.app/Contents/embedded.provisionprofile` 로 복사
///   3. `codesign --force --timestamp --entitlements <path> -s "<APP_CERT>" <.app>`
///   4. `productbuild --sign "<PKG_CERT>" --component <.app> /Applications <App>.pkg`
///
/// 모든 단계가 **순수 명령 시퀀스** 로 표현되어 단위 테스트 가능하며,
/// 실행기는 macOS 외 호스트에서 stdout 출력만 수행한다.
public import Foundation
public import KalsaeCore

extension KSPackager {

    /// MAS 사이닝 입력값.
    public struct MacAppStoreInput: Sendable {
        public var bundle: URL  // <App>.app
        public var pkgOutput: URL  // 출력 .pkg 경로
        public var appSigningIdentity: String  // "3rd Party Mac Developer Application: …"
        public var installerSigningIdentity: String  // "3rd Party Mac Developer Installer: …"
        public var provisionProfilePath: URL  // embedded.provisionprofile
        public var entitlementsPath: URL  // MAS entitlements .plist
        public var installLocation: String  // 일반적으로 "/Applications"

        public init(
            bundle: URL,
            pkgOutput: URL,
            appSigningIdentity: String,
            installerSigningIdentity: String,
            provisionProfilePath: URL,
            entitlementsPath: URL,
            installLocation: String = "/Applications"
        ) {
            self.bundle = bundle
            self.pkgOutput = pkgOutput
            self.appSigningIdentity = appSigningIdentity
            self.installerSigningIdentity = installerSigningIdentity
            self.provisionProfilePath = provisionProfilePath
            self.entitlementsPath = entitlementsPath
            self.installLocation = installLocation
        }
    }

    /// MAS 패키징 명령 시퀀스를 계산한다. 파일 I/O 없음.
    ///
    /// 첫 단계는 **메타데이터** 로만 표현된다(`label="copy-provisioning"`,
    /// `command="<cp>"`, `args=[src, dst]`). 실행기가 macOS 에서 `FileManager.copyItem`
    /// 로 매핑하고, 그 외 호스트에서는 출력만 한다.
    public static func planMacAppStorePipeline(_ input: MacAppStoreInput) -> [MacSignStep] {
        var steps: [MacSignStep] = []

        // (1) embedded.provisionprofile 복사
        let dst = input.bundle
            .appendingPathComponent("Contents")
            .appendingPathComponent("embedded.provisionprofile")
        steps.append(.init(
            command: "<cp>",
            args: [input.provisionProfilePath.path, dst.path],
            label: "copy-provisioning"))

        // (2) codesign — MAS 는 --options=runtime 제거. entitlements 가 sandbox 강제.
        let codesignArgs = [
            "--force",
            "--timestamp",
            "--entitlements", input.entitlementsPath.path,
            "--sign", input.appSigningIdentity,
            input.bundle.path,
        ]
        steps.append(.init(command: "codesign", args: codesignArgs, label: "codesign"))

        // (3) productbuild → .pkg
        let productbuildArgs = [
            "--sign", input.installerSigningIdentity,
            "--component", input.bundle.path, input.installLocation,
            input.pkgOutput.path,
        ]
        steps.append(.init(command: "productbuild", args: productbuildArgs, label: "productbuild"))

        return steps
    }

    // MARK: - 실행기 (macOS 전용 — 그 외는 출력만)

    public static func executeMacAppStoreSteps(
        _ steps: [MacSignStep],
        dryRun: Bool,
        warnings: inout [String]
    ) throws {
        #if os(macOS)
            if dryRun {
                printMASPlanned(steps)
                return
            }
            for step in steps {
                if step.command == "<cp>" {
                    // FileManager 로 복사
                    let src = URL(fileURLWithPath: step.args[0])
                    let dst = URL(fileURLWithPath: step.args[1])
                    let fm = FileManager.default
                    if fm.fileExists(atPath: dst.path) {
                        try fm.removeItem(at: dst)
                    }
                    try fm.copyItem(at: src, to: dst)
                    print("  ▶ \(step.label): \(src.lastPathComponent) → \(dst.path)")
                } else {
                    print("  ▶ \(step.label): \(step.command) \(step.args.joined(separator: " "))")
                    try shell(command: step.command, arguments: step.args)
                }
            }
        #else
            printMASPlanned(steps)
            if !dryRun {
                warnings.append(
                    "Mac App Store pipeline skipped on non-macOS host. "
                    + "Re-run `kalsae build --store mas` on macOS to actually sign + package.")
            }
        #endif
    }

    private static func printMASPlanned(_ steps: [MacSignStep]) {
        for step in steps {
            if step.command == "<cp>" {
                print("  • \(step.label): cp \(step.args[0]) \(step.args[1])")
            } else {
                print("  • \(step.label): \(step.command) \(step.args.joined(separator: " "))")
            }
        }
    }
}
