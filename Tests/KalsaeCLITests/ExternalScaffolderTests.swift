import Foundation
import Testing

@testable import KalsaeCLICore

@Suite("KSExternalScaffolder")
struct ExternalScaffolderTests {
    private func makeTempProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae-scaffolder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: false, encoding: .utf8)
    }

    @Test("Overlay writes Package.swift / App.swift / kalsae.json")
    func overlayWritesKalsaeFiles() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let scaffolder = KSExternalScaffolder(
            name: "demo", frontend: "react", packageManager: "npm")
        try scaffolder.writeKalsaeOverlay(into: root)

        let pkg = root.appendingPathComponent("Package.swift")
        let app = root.appendingPathComponent("Sources/demo/App.swift")
        let cfg = root.appendingPathComponent("Sources/demo/Resources/kalsae.json")

        #expect(FileManager.default.fileExists(atPath: pkg.path))
        #expect(FileManager.default.fileExists(atPath: app.path))
        #expect(FileManager.default.fileExists(atPath: cfg.path))

        let pkgText = try String(contentsOf: pkg, encoding: .utf8)
        #expect(pkgText.contains("name: \"demo\""))
    }

    @Test("Patches vite.config.ts with base: './'")
    func patchesViteConfig() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let viteConfig = root.appendingPathComponent("vite.config.ts")
        try write(
            """
            import { defineConfig } from 'vite'
            import react from '@vitejs/plugin-react'

            export default defineConfig({
              plugins: [react()],
            })
            """,
            to: viteConfig)

        let scaffolder = KSExternalScaffolder(
            name: "demo", frontend: "react", packageManager: "npm")
        try scaffolder.patchViteConfig(in: root)

        let patched = try String(contentsOf: viteConfig, encoding: .utf8)
        #expect(patched.contains("base: './'"))
    }

    @Test("patchViteConfig is idempotent when base is already set")
    func patchViteConfigIdempotent() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let viteConfig = root.appendingPathComponent("vite.config.ts")
        let original = """
            export default defineConfig({
              base: '/foo/',
              plugins: [],
            })
            """
        try write(original, to: viteConfig)

        let scaffolder = KSExternalScaffolder(
            name: "demo", frontend: "react", packageManager: "npm")
        try scaffolder.patchViteConfig(in: root)

        let after = try String(contentsOf: viteConfig, encoding: .utf8)
        #expect(after == original)
    }

    @Test("mergeGitignore appends SwiftPM artifacts without duplicates")
    func mergesGitignore() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let gitignore = root.appendingPathComponent(".gitignore")
        try write("node_modules\ndist\n", to: gitignore)

        let scaffolder = KSExternalScaffolder(
            name: "demo", frontend: "react", packageManager: "npm")
        try scaffolder.mergeGitignore(in: root)

        let text = try String(contentsOf: gitignore, encoding: .utf8)
        #expect(text.contains("node_modules"))
        #expect(text.contains(".build"))
        #expect(text.contains(".swiftpm"))

        // 두 번 호출해도 중복 추가 없음.
        try scaffolder.mergeGitignore(in: root)
        let again = try String(contentsOf: gitignore, encoding: .utf8)
        let buildCount = again.components(separatedBy: ".build").count - 1
        #expect(buildCount == 1)
    }
}
