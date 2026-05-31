import Foundation
import Testing

@testable import KalsaeCLICore

@Suite("KSDoctor")
struct DoctorTests {
    private func makeTempProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae-doctor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: false, encoding: .utf8)
    }

    @Test("Reports missing config")
    func missingConfig() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let report = KSDoctor.run(.init(projectRoot: root, skipExternalChecks: true))
        #expect(report.warnings.contains { $0.contains("Config file not found") })
    }

    @Test("Accepts valid config")
    func validConfigAndDist() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let configURL = root.appendingPathComponent("kalsae.json")
        let distURL = root.appendingPathComponent("dist")
        try FileManager.default.createDirectory(at: distURL, withIntermediateDirectories: true)
        try write("<html></html>", to: distURL.appendingPathComponent("index.html"))

        try write(
            #"{"app":{"name":"Demo","version":"0.1.0","identifier":"dev.kalsae.demo"},"build":{"frontendDist":"dist","devServerURL":"about:blank"},"windows":[{"label":"main","title":"Demo","width":800,"height":600}]}"#,
            to: configURL)

        #if os(Windows)
            let webView2Include =
                root
                .appendingPathComponent("Vendor")
                .appendingPathComponent("WebView2")
                .appendingPathComponent("build")
                .appendingPathComponent("native")
                .appendingPathComponent("include")
            try FileManager.default.createDirectory(at: webView2Include, withIntermediateDirectories: true)
            try write("stub", to: webView2Include.appendingPathComponent("WebView2.h"))
        #endif

        let report = KSDoctor.run(.init(projectRoot: root, skipExternalChecks: true))

        #expect(report.warnings.isEmpty)
        #expect(report.infos.contains { $0.contains("Loaded config") })
        // doctor는 더 이상 frontendDist를 검증하지 않는다.
        #expect(!report.infos.contains { $0.contains("Frontend dist") })
    }

    @Test("Reports warning for invalid JSON config")
    func invalidJSONConfig() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let configURL = root.appendingPathComponent("kalsae.json")
        try write("not valid json", to: configURL)

        let report = KSDoctor.run(.init(projectRoot: root, skipExternalChecks: true))
        #expect(
            report.warnings.contains {
                $0.contains("Config") || $0.contains("config") || $0.contains("parse") || $0.contains("invalid")
            })
    }

    @Test("Warns when swift-syntax cache remote is invalid")
    func invalidSwiftSyntaxRemote() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let cache =
            root
            .appendingPathComponent(".build")
            .appendingPathComponent("repositories")
            .appendingPathComponent("swift-syntax-test")
            .appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try write(
            "[remote \"origin\"]\nurl = https://example.invalid/swift-syntax.git\n",
            to: cache.appendingPathComponent("config"))

        let report = KSDoctor.run(.init(projectRoot: root, skipExternalChecks: true))
        #expect(report.warnings.contains { $0.contains("swift-syntax cache remote looks invalid") })
    }

    @Test("skipExternalChecks suppresses Node/npm probes")
    func skipsExternalChecks() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        // package.json이 있어도 skipExternalChecks=true이면 node/npm 메시지가 등장하지 않아야 한다.
        try write("{}", to: root.appendingPathComponent("package.json"))

        let report = KSDoctor.run(.init(projectRoot: root, skipExternalChecks: true))

        #expect(report.nodeVersion == nil)
        #expect(report.npmVersion == nil)
        #expect(!report.infos.contains { $0.contains("Node.js") })
        #expect(!report.warnings.contains { $0.contains("Node.js") })
    }

    @Test("Vanilla project (no package.json) reports missing node as info, not warning")
    func vanillaProjectNoNode() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let report = KSDoctor.run(.init(projectRoot: root, skipExternalChecks: false))

        if findExecutable(named: "node") == nil {
            // package.json 없음 → warning이 아니라 info로 보고되어야 한다.
            #expect(
                report.infos.contains {
                    $0.contains("Node.js not found") && $0.contains("non-vanilla")
                })
            #expect(!report.warnings.contains { $0.contains("Node.js not found") })
        } else {
            #expect(report.nodeVersion != nil)
        }
    }

    @Test("Captures host environment metadata")
    func capturesHostEnvironment() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let report = KSDoctor.run(.init(projectRoot: root, skipExternalChecks: true))
        // OS / arch / version 은 외부 프로세스 없이도 항상 채워진다.
        #expect(report.osName != nil)
        #expect(report.osVersion != nil)
        #expect(report.architecture != nil)
        // skipExternalChecks=true 인 경우 swift --version 호출은 건너뛴다.
        #expect(report.swiftVersion == nil)
    }

    // MARK: - 패키지 manifest 검증

    @Test("Warns on packaged manifest with invalid processorArchitecture (legacy x64)")
    func packagedManifestInvalidArch() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let pkg =
            root
            .appendingPathComponent("dist")
            .appendingPathComponent("Demo-1.0.0-x64")
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        // 과거 빌드가 만든 잘못된 manifest 시뮬레이션.
        try write(
            "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
                + "<assembly xmlns=\"urn:schemas-microsoft-com:asm.v1\" manifestVersion=\"1.0\">\n"
                + "<assemblyIdentity type=\"win32\" name=\"dev.kalsae.demo\""
                + " version=\"1.0.0.0\" processorArchitecture=\"x64\"/>\n"
                + "</assembly>\n",
            to: pkg.appendingPathComponent("Demo.exe.manifest"))

        let report = KSDoctor.run(.init(projectRoot: root, skipExternalChecks: true))
        #expect(
            report.warnings.contains { $0.contains("processorArchitecture=\"x64\"") },
            "Doctor should flag invalid SxS processorArchitecture, got warnings: \(report.warnings)")
    }

    @Test("Accepts packaged manifest with valid amd64 processorArchitecture")
    func packagedManifestValidArch() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let pkg =
            root
            .appendingPathComponent("dist")
            .appendingPathComponent("Demo-1.0.0-x64")
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        try write(
            "<assembly><assemblyIdentity processorArchitecture=\"amd64\"/></assembly>",
            to: pkg.appendingPathComponent("Demo.exe.manifest"))

        let report = KSDoctor.run(.init(projectRoot: root, skipExternalChecks: true))
        #expect(
            !report.warnings.contains { $0.contains("processorArchitecture") },
            "Doctor must not warn on a valid amd64 manifest, got: \(report.warnings)")
    }

    @Test("Silent when no dist directory exists")
    func packagedManifestNoDist() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let report = KSDoctor.run(.init(projectRoot: root, skipExternalChecks: true))
        #expect(!report.warnings.contains { $0.contains("processorArchitecture") })
        #expect(!report.infos.contains { $0.contains("processorArchitecture") })
    }

    // MARK: - Windows 호스트 진단 (windows.webview2 / wix / signtool)

    @Test("windows status populated on Windows host with WebView2 SDK present")
    func windowsStatusWithWebView2() throws {
        #if os(Windows)
            let root = try makeTempProject()
            defer { try? FileManager.default.removeItem(at: root) }

            let webView2Include =
                root
                .appendingPathComponent("Vendor")
                .appendingPathComponent("WebView2")
                .appendingPathComponent("build")
                .appendingPathComponent("native")
                .appendingPathComponent("include")
            try FileManager.default.createDirectory(
                at: webView2Include, withIntermediateDirectories: true)
            try write("stub", to: webView2Include.appendingPathComponent("WebView2.h"))

            // skipExternalChecks=true 라도 checkWebView2 는 파일 존재 검사라 실행된다.
            // wix/signtool 은 PATH 조회를 동반하므로 skipExternalChecks=false 로 호출.
            let report = KSDoctor.run(.init(projectRoot: root, skipExternalChecks: false))

            let status = try #require(
                report.windows,
                "report.windows should be populated on Windows hosts.")
            #expect(status.webview2 == true)
            // wix/signtool 은 호스트 환경에 따라 다르므로 Bool 값 자체는 검증하지 않고,
            // 필드가 채워졌다는 사실 (Codable 직렬화 가능성) 만 확인한다.
            let encoded = try JSONEncoder().encode(status)
            #expect(!encoded.isEmpty)
        #endif
    }

    @Test("Windows doctor points local path-dependency consumers to the KalSae checkout")
    func windowsPathDependencyWebView2Hint() throws {
        #if os(Windows)
            let root = try makeTempProject()
            let kalsaeRoot = root.appendingPathComponent("deps").appendingPathComponent("KalSae")
            defer { try? FileManager.default.removeItem(at: root) }

            try FileManager.default.createDirectory(
                at: kalsaeRoot.appendingPathComponent("Sources").appendingPathComponent("CKalsaeWV2"),
                withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: kalsaeRoot.appendingPathComponent("Scripts"),
                withIntermediateDirectories: true)
            try write(
                "stub", to: kalsaeRoot.appendingPathComponent("Scripts").appendingPathComponent("fetch-webview2.ps1"))
            try write(
                "// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: \"App\", dependencies: [.package(path: \"deps/KalSae\")])\n",
                to: root.appendingPathComponent("Package.swift"))

            let report = KSDoctor.run(.init(projectRoot: root, skipExternalChecks: true))

            let expectedPath = kalsaeRoot.path.lowercased()
            #expect(
                report.warnings.contains { $0.lowercased().contains(expectedPath) },
                "doctor warnings should include inferred KalSae checkout path; got: \(report.warnings)"
            )
            #expect(report.warnings.contains { $0.contains("fetch-webview2.ps1") })
        #endif
    }

    @Test("windows status is nil on non-Windows hosts")
    func windowsStatusNilOffWindows() throws {
        #if !os(Windows)
            let root = try makeTempProject()
            defer { try? FileManager.default.removeItem(at: root) }

            let report = KSDoctor.run(.init(projectRoot: root, skipExternalChecks: true))
            #expect(report.windows == nil)
        #endif
    }

    @Test("--store win-store passes bare tool names to findExecutable (no doubled .exe.exe)")
    func storeWinStoreUsesBareNames() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let report = KSDoctor.run(
            .init(
                projectRoot: root,
                skipExternalChecks: false,
                distributionTarget: .microsoftStore))
        // 회귀 방지: 과거에는 `requireTool("MakeAppx.exe", ...)`이 PATH 에서
        // "MakeAppx.exe.exe" 를 찾으며 항상 실패해 spurious warning 을 냈다.
        // 어떤 메시지든 doubled-extension 패턴이 등장해선 안 된다.
        for msg in report.warnings + report.infos {
            #expect(
                !msg.contains(".exe.exe") && !msg.contains(".exe.cmd"),
                "doubled-extension leaked into doctor message: \(msg)")
        }
    }
}
