import Testing
import Foundation
@testable import KalsaeCLICore

@Suite("KSBindingsGenerator — TypeMapper")
struct BindingsTypeMapperTests {

    @Test("Primitives map to TS scalars")
    func primitives() {
        #expect(KSBindingsGenerator.mapType("String") == "string")
        #expect(KSBindingsGenerator.mapType("Bool") == "boolean")
        #expect(KSBindingsGenerator.mapType("Int") == "number")
        #expect(KSBindingsGenerator.mapType("Double") == "number")
        #expect(KSBindingsGenerator.mapType("UInt64") == "number")
        #expect(KSBindingsGenerator.mapType("Void") == "void")
        #expect(KSBindingsGenerator.mapType("()") == "void")
    }

    @Test("Foundation string-shaped types collapse to string")
    func stringShaped() {
        #expect(KSBindingsGenerator.mapType("URL") == "string")
        #expect(KSBindingsGenerator.mapType("UUID") == "string")
        #expect(KSBindingsGenerator.mapType("Date") == "string")
        #expect(KSBindingsGenerator.mapType("Data") == "string")
    }

    @Test("Optional sugar T? becomes union with null")
    func optionalSugar() {
        #expect(KSBindingsGenerator.mapType("String?") == "string | null")
        #expect(KSBindingsGenerator.mapType("Int?") == "number | null")
        #expect(KSBindingsGenerator.mapType("Optional<Bool>") == "boolean | null")
    }

    @Test("Array sugar [T] becomes (T)[]")
    func arraySugar() {
        #expect(KSBindingsGenerator.mapType("[String]") == "(string)[]")
        #expect(KSBindingsGenerator.mapType("[Int?]") == "(number | null)[]")
        #expect(KSBindingsGenerator.mapType("Array<String>") == "(string)[]")
        #expect(KSBindingsGenerator.mapType("Set<Int>") == "(number)[]")
    }

    @Test("Dictionary sugar [K: V] yields Record when keys are String")
    func dictionarySugar() {
        #expect(KSBindingsGenerator.mapType("[String: Int]") == "Record<string, number>")
        #expect(KSBindingsGenerator.mapType("[String: Bool?]") == "Record<string, boolean | null>")
        // Non-String keys preserved as comment for visibility
        let mapped = KSBindingsGenerator.mapType("[Int: String]")
        #expect(mapped.hasPrefix("Record<string, string>"))
        #expect(mapped.contains("keys: Int"))
    }

    @Test("Dictionary<K, V> generic form")
    func dictionaryGeneric() {
        #expect(KSBindingsGenerator.mapType("Dictionary<String, Int>") == "Record<string, number>")
    }

    @Test("Unknown identifier passes through verbatim")
    func unknownPassThrough() {
        #expect(KSBindingsGenerator.mapType("MyCustomType") == "MyCustomType")
    }

    @Test("Nested generics via topLevelSplit")
    func nestedGenerics() {
        // Dictionary<String, Array<Int>>
        let s = KSBindingsGenerator.mapType("Dictionary<String, Array<Int>>")
        #expect(s == "Record<string, (number)[]>")
    }

    @Test("stripBackticks helper")
    func backticks() {
        #expect(KSBindingsGenerator.stripBackticks("`class`") == "class")
        #expect(KSBindingsGenerator.stripBackticks("plain") == "plain")
    }
}

@Suite("KSBindingsGenerator — Renderer & end-to-end")
struct BindingsRendererTests {

    private func makeOptions(sources: [URL], output: URL) -> KSBindingsGenerator.Options {
        KSBindingsGenerator.Options(sources: sources, output: output, moduleName: "TestMod")
    }

    private func writeTemp(_ src: String) throws -> (URL, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bindings-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let input = dir.appendingPathComponent("Source.swift")
        try src.write(to: input, atomically: true, encoding: .utf8)
        let output = dir.appendingPathComponent("out.ts")
        return (input, output)
    }

    @Test("Empty input produces only header + invoke shim")
    func emptyInput() throws {
        let (input, output) = try writeTemp("// empty\n")
        defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }

        let report = try KSBindingsGenerator.run(makeOptions(sources: [input], output: output))
        #expect(report.commandCount == 0)
        #expect(report.typeCount == 0)

        let ts = try String(contentsOf: output, encoding: .utf8)
        #expect(ts.contains("AUTO-GENERATED"))
        #expect(ts.contains("Module: TestMod"))
        #expect(ts.contains("function _invoke()"))
        #expect(ts.contains("export const App = {"))
    }

    @Test("@KSCommand without params renders zero-arg promise")
    func commandNoParams() throws {
        let src = """
        import Foundation
        @KSCommand
        func ping() -> String { "pong" }
        """
        let (input, output) = try writeTemp(src)
        defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }

        _ = try KSBindingsGenerator.run(makeOptions(sources: [input], output: output))
        let ts = try String(contentsOf: output, encoding: .utf8)
        #expect(ts.contains("ping(): Promise<string>"))
        #expect(ts.contains("_invoke()(\"ping\")"))
    }

    @Test("@KSCommand with single param wraps into object literal")
    func commandSingleParam() throws {
        let src = """
        @KSCommand
        func greet(name: String) -> String { name }
        """
        let (input, output) = try writeTemp(src)
        defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }

        _ = try KSBindingsGenerator.run(makeOptions(sources: [input], output: output))
        let ts = try String(contentsOf: output, encoding: .utf8)
        #expect(ts.contains("greet(name: string): Promise<string>"))
        #expect(ts.contains("_invoke()(\"greet\", { name })"))
    }

    @Test("@KSCommand with multiple params uses args object")
    func commandMultiParam() throws {
        let src = """
        @KSCommand
        func add(a: Int, b: Int) -> Int { a + b }
        """
        let (input, output) = try writeTemp(src)
        defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }

        _ = try KSBindingsGenerator.run(makeOptions(sources: [input], output: output))
        let ts = try String(contentsOf: output, encoding: .utf8)
        #expect(ts.contains("add(args: { a: number; b: number }): Promise<number>"))
        #expect(ts.contains("_invoke()(\"add\", args)"))
    }

    @Test("Codable struct renders as TS interface")
    func codableStruct() throws {
        let src = """
        struct User: Codable {
            let id: String
            let age: Int?
        }
        """
        let (input, output) = try writeTemp(src)
        defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }

        let r = try KSBindingsGenerator.run(makeOptions(sources: [input], output: output))
        #expect(r.typeCount == 1)
        let ts = try String(contentsOf: output, encoding: .utf8)
        #expect(ts.contains("export interface User {"))
        #expect(ts.contains("id: string;"))
        #expect(ts.contains("age?: number | null;"))
    }

    @Test("String-raw enum becomes TS string union")
    func stringEnum() throws {
        let src = """
        enum Mode: String, Codable {
            case light
            case dark
        }
        """
        let (input, output) = try writeTemp(src)
        defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }

        _ = try KSBindingsGenerator.run(makeOptions(sources: [input], output: output))
        let ts = try String(contentsOf: output, encoding: .utf8)
        #expect(ts.contains("export type Mode = \"light\" | \"dark\";"))
    }

    @Test("Custom command name from attribute argument")
    func customCommandName() throws {
        let src = """
        @KSCommand("custom.name")
        func foo() {}
        """
        let (input, output) = try writeTemp(src)
        defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }

        _ = try KSBindingsGenerator.run(makeOptions(sources: [input], output: output))
        let ts = try String(contentsOf: output, encoding: .utf8)
        #expect(ts.contains("foo(): Promise<void>"))
        #expect(ts.contains("_invoke()(\"custom.name\")"))
    }

    @Test("Duplicate types across files: first occurrence wins")
    func dedup() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bindings-dedup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = dir.appendingPathComponent("A.swift")
        let b = dir.appendingPathComponent("B.swift")
        try "struct Pt: Codable { let x: Int }".write(to: a, atomically: true, encoding: .utf8)
        try "struct Pt: Codable { let y: String }".write(to: b, atomically: true, encoding: .utf8)
        let output = dir.appendingPathComponent("out.ts")

        let r = try KSBindingsGenerator.run(makeOptions(sources: [a, b], output: output))
        #expect(r.typeCount == 1)
    }
}
