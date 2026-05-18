import Foundation
import Testing

@testable import KalsaeCLICore

@Suite("KSPEImportReader")
struct PEImportReaderTests {

    @Test("Rejects non-PE files (missing MZ)")
    func rejectsNonPE() {
        let bogus = Data([0x00, 0x01, 0x02, 0x03, 0x04])
        #expect(throws: ShellError.self) {
            _ = try KSPEImportReader.parse(data: bogus)
        }
    }

    @Test("Rejects empty data")
    func rejectsEmpty() {
        #expect(throws: ShellError.self) {
            _ = try KSPEImportReader.parse(data: Data())
        }
    }

    @Test("Rejects MZ without valid PE signature")
    func rejectsMZWithoutPE() {
        // "MZ" 헤더는 있지만 e_lfanew 가 가리키는 위치에 PE\0\0 가 없음.
        var bytes = [UInt8](repeating: 0, count: 0x100)
        bytes[0] = 0x4D
        bytes[1] = 0x5A
        // e_lfanew @ 0x3C → 0x80, 그러나 0x80 부터 "PE\0\0" 가 아님.
        bytes[0x3C] = 0x80
        #expect(throws: ShellError.self) {
            _ = try KSPEImportReader.parse(data: Data(bytes))
        }
    }

    #if os(Windows)
        /// 시스템 EXE 의 import 테이블에서 KERNEL32.dll 을 발견하는지 확인.
        /// notepad.exe 는 모든 Windows 버전에 존재한다.
        @Test("Parses a real PE (notepad.exe) and finds KERNEL32")
        func parsesNotepad() throws {
            let systemRoot = ProcessInfo.processInfo.environment["SystemRoot"]
                ?? "C:\\Windows"
            let notepad = URL(fileURLWithPath: systemRoot)
                .appendingPathComponent("System32")
                .appendingPathComponent("notepad.exe")
            guard FileManager.default.fileExists(atPath: notepad.path) else {
                Issue.record("notepad.exe not found at \(notepad.path); skipping")
                return
            }
            let deps = try KSPEImportReader.importedDLLs(at: notepad)
            let lower = deps.map { $0.lowercased() }
            // 모던 Windows 의 notepad.exe 는 KERNEL32 대신 api-ms-win-* /
            // kernelbase 등 forwarder 만 직접 import 할 수 있으므로,
            // "Win32 핵심 DLL 중 하나" 만 검증한다.
            #expect(!deps.isEmpty)
            #expect(
                lower.contains {
                    $0.hasPrefix("kernel32")
                        || $0.hasPrefix("kernelbase")
                        || $0.hasPrefix("api-ms-win-")
                        || $0.hasPrefix("ntdll")
                }
            )
        }
    #endif
}
