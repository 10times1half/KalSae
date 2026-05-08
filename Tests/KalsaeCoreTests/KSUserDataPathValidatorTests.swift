import Foundation
import Testing

@testable import KalsaeCore

@Suite("KSUserDataPathValidator")
struct KSUserDataPathValidatorTests {

    private let env: [String: String] = [
        "HOME": "/Users/me",
        "USERPROFILE": "C:\\Users\\me",
        "LOCALAPPDATA": "C:\\Users\\me\\AppData\\Local",
        "APPDATA": "C:\\Users\\me\\AppData\\Roaming",
        "TEMP": "C:\\Windows\\Temp",
        "MYAPP": "Demo",
    ]

    @Test("empty string rejected")
    func emptyRejected() {
        do {
            _ = try KSUserDataPathValidator.validate("", environment: env, homeDirectory: "/Users/me", temporaryDirectory: "/tmp")
            Issue.record("expected failure")
        } catch {
            #expect(error.reason == .empty)
        }
    }

    @Test("relative path rejected")
    func relativeRejected() {
        do {
            _ = try KSUserDataPathValidator.validate("./foo", environment: env, homeDirectory: "/Users/me", temporaryDirectory: "/tmp")
            Issue.record("expected failure")
        } catch {
            #expect(error.reason == .relative)
        }
    }

    @Test("parent traversal rejected")
    func parentTraversalRejected() {
        do {
            _ = try KSUserDataPathValidator.validate(
                "/Users/me/../etc",
                environment: env, homeDirectory: "/Users/me", temporaryDirectory: "/tmp")
            Issue.record("expected failure")
        } catch {
            #expect(error.reason == .parentTraversal)
        }
    }

    @Test("path under home accepted")
    func underHome() throws {
        let resolved = try KSUserDataPathValidator.validate(
            "/Users/me/Library/MyApp",
            environment: env, homeDirectory: "/Users/me", temporaryDirectory: "/tmp")
        #expect(resolved.contains("MyApp"))
    }

    @Test("env variable expansion: %VAR%")
    func windowsEnvExpansion() throws {
        let resolved = try KSUserDataPathValidator.validate(
            "%LOCALAPPDATA%\\\\Kalsae\\\\%MYAPP%",
            environment: env, homeDirectory: "C:\\Users\\me", temporaryDirectory: "C:\\Windows\\Temp")
        #expect(resolved.lowercased().contains("kalsae"))
        #expect(resolved.lowercased().contains("demo"))
    }

    @Test("env variable expansion: $VAR")
    func posixEnvExpansion() throws {
        let resolved = try KSUserDataPathValidator.validate(
            "$HOME/Library/$MYAPP",
            environment: env, homeDirectory: "/Users/me", temporaryDirectory: "/tmp")
        #expect(resolved.contains("Library"))
        #expect(resolved.contains("Demo"))
    }

    @Test("path outside allowed roots rejected")
    func outsideRootsRejected() {
        do {
            _ = try KSUserDataPathValidator.validate(
                "/etc/passwd-data",
                environment: env, homeDirectory: "/Users/me", temporaryDirectory: "/tmp")
            Issue.record("expected failure")
        } catch {
            #expect(error.reason == .outsideAllowedRoots)
        }
    }

    @Test("isAbsolute: drive letter forms recognized")
    func absoluteWindows() {
        #expect(KSUserDataPathValidator.isAbsolute("C:\\foo"))
        #expect(KSUserDataPathValidator.isAbsolute("D:/bar"))
        #expect(KSUserDataPathValidator.isAbsolute("\\\\server\\share"))
        #expect(!KSUserDataPathValidator.isAbsolute("foo\\bar"))
    }

    @Test("isAbsolute: posix root recognized")
    func absolutePosix() {
        #expect(KSUserDataPathValidator.isAbsolute("/usr/local"))
        #expect(!KSUserDataPathValidator.isAbsolute("usr/local"))
    }
}
