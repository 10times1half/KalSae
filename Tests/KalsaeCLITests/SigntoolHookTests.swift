import Foundation
import Testing

@testable import KalsaeCLICore

@Suite("KSSigntoolHook — template rendering")
struct SigntoolHookTests {

    @Test("render() substitutes {file} placeholder with quoted path")
    func substitutesPlaceholder() {
        let url = URL(fileURLWithPath: "/tmp/My App.exe")
        let cmd = KSSigntoolHook.render(
            template: "signtool sign /a /fd SHA256 {file}",
            file: url)
        #expect(cmd == "signtool sign /a /fd SHA256 \"/tmp/My App.exe\"")
    }

    @Test("render() appends quoted path when {file} placeholder is absent")
    func appendsPath() {
        let url = URL(fileURLWithPath: "/tmp/foo.exe")
        let cmd = KSSigntoolHook.render(
            template: "signtool sign /a",
            file: url)
        #expect(cmd == "signtool sign /a \"/tmp/foo.exe\"")
    }

    @Test("render() handles multiple {file} occurrences")
    func multipleOccurrences() {
        let url = URL(fileURLWithPath: "/tmp/x.exe")
        let cmd = KSSigntoolHook.render(
            template: "echo {file} && copy {file} {file}.bak",
            file: url)
        #expect(cmd == "echo \"/tmp/x.exe\" && copy \"/tmp/x.exe\" \"/tmp/x.exe\".bak")
    }

    @Test("dryrun mode does not execute the command")
    func dryrunSkipsExecution() throws {
        // 존재하지 않는 명령이라도 dryrun이면 throw하지 않는다.
        let url = URL(fileURLWithPath: "/tmp/nonexistent.exe")
        try KSSigntoolHook.run(
            template: "this-command-definitely-does-not-exist-zzzz {file}",
            file: url,
            label: "test",
            dryrun: true)
    }
}
