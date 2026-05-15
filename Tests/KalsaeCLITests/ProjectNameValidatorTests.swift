import Foundation
import Testing

@testable import KalsaeCLICore

@Suite("KSProjectNameValidator")
struct ProjectNameValidatorTests {

    // MARK: - containsNonASCII

    @Test("containsNonASCII detects Hangul / CJK / accented chars")
    func detectsNonASCII() {
        #expect(KSProjectNameValidator.containsNonASCII("칼세") == true)
        #expect(KSProjectNameValidator.containsNonASCII("中文") == true)
        #expect(KSProjectNameValidator.containsNonASCII("テスト") == true)
        #expect(KSProjectNameValidator.containsNonASCII("café") == true)
        #expect(KSProjectNameValidator.containsNonASCII("my-칼세-app") == true)
    }

    @Test("containsNonASCII accepts pure ASCII")
    func acceptsASCII() {
        #expect(KSProjectNameValidator.containsNonASCII("my-app") == false)
        #expect(KSProjectNameValidator.containsNonASCII("MyApp_v2") == false)
        #expect(KSProjectNameValidator.containsNonASCII("") == false)
        #expect(KSProjectNameValidator.containsNonASCII("C:\\Projects\\Kalsae") == false)
    }

    // MARK: - validateName rejects

    @Test(
        "validateName rejects non-ASCII / invalid names",
        arguments: [
            "칼세testKS1",
            "칼세",
            "my-칼세-app",
            "café",
            "中文",
            "テスト",
            "1stApp",
            "my app",
            "my.app",
            "my@app",
            "",
            "-app",
            "_app",
        ])
    func rejectsBadNames(_ name: String) {
        #expect(throws: KSProjectNameValidator.ValidationFailure.self) {
            try KSProjectNameValidator.validateName(name)
        }
    }

    // MARK: - validateName accepts

    @Test(
        "validateName accepts valid ASCII names",
        arguments: [
            "my-app",
            "my_app2",
            "MyApp",
            "MyApp-v2_beta",
            "a",
            "Z9",
            "kalsae",
            "Kalsae123",
        ])
    func acceptsGoodNames(_ name: String) throws {
        try KSProjectNameValidator.validateName(name)
    }

    // MARK: - validatePath

    @Test("validatePath rejects paths containing non-ASCII characters")
    func rejectsNonASCIIPaths() {
        let p1 = URL(fileURLWithPath: "C:\\Projects\\칼세\\sub")
        #expect(throws: KSProjectNameValidator.ValidationFailure.self) {
            try KSProjectNameValidator.validatePath(p1, role: "current working directory")
        }
        let p2 = URL(fileURLWithPath: "/home/사용자/proj")
        #expect(throws: KSProjectNameValidator.ValidationFailure.self) {
            try KSProjectNameValidator.validatePath(p2, role: "--dir target")
        }
    }

    @Test("validatePath accepts pure-ASCII paths including Windows drive letters")
    func acceptsASCIIPaths() throws {
        try KSProjectNameValidator.validatePath(
            URL(fileURLWithPath: "C:\\Projects\\Kalsae"),
            role: "current working directory")
        try KSProjectNameValidator.validatePath(
            URL(fileURLWithPath: "/Users/me/proj-1"),
            role: "--dir target")
    }

    @Test("validatePath error message includes the role label and offending path")
    func errorIncludesContext() {
        let p = URL(fileURLWithPath: "C:\\Projects\\칼세")
        do {
            try KSProjectNameValidator.validatePath(p, role: "current working directory")
            Issue.record("Expected throw")
        } catch let e as KSProjectNameValidator.ValidationFailure {
            #expect(e.description.contains("current working directory"))
            #expect(e.description.contains("칼세"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
