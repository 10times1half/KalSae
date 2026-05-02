import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import KalsaeMacrosPlugin

private let macros: [String: Macro.Type] = [
    "KSCommand": KSCommandMacro.self
]
@Suite("KSCommandMacro diagnostics")
struct KSCommandMacroDiagnosticsTests {

    @Test("Non-function declaration emits notAFunction diagnostic")
    func notAFunction() {
        assertMacroExpansion(
            """
            @KSCommand
            struct Greet {}
            """,
            expandedSource: """
                struct Greet {}
                """,
            diagnostics: [
                .init(
                    message: "@KSCommand can only be applied to function declarations.",
                    line: 1, column: 1)
            ],
            macros: macros)
    }

    @Test("Empty literal name emits emptyName diagnostic with fix-it")
    func emptyName() {
        assertMacroExpansion(
            #"""
            @KSCommand("")
            func go() {}
            """#,
            expandedSource: """
                func go() {}
                """,
            diagnostics: [
                .init(
                    message: "@KSCommand registry name must not be empty.",
                    line: 1, column: 12,
                    fixIts: [
                        .init(message: "Remove the argument to use the function name as the registry key.")
                    ])
            ],
            macros: macros)
    }

    @Test("Non-literal name emits nonLiteralName diagnostic")
    func nonLiteralName() {
        assertMacroExpansion(
            """
            @KSCommand(123)
            func go() {}
            """,
            expandedSource: """
                func go() {}
                """,
            diagnostics: [
                .init(
                    message: "@KSCommand requires a plain string literal name (no interpolation).",
                    line: 1, column: 12,
                    fixIts: [
                        .init(message: "Remove the argument to use the function name as the registry key.")
                    ])
            ],
            macros: macros)
    }

    @Test("Variadic parameter emits diagnostic with fix-it")
    func variadicParameter() {
        assertMacroExpansion(
            """
            @KSCommand
            func tagged(items: String...) {}
            """,
            expandedSource: """
                func tagged(items: String...) {}
                """,
            diagnostics: [
                .init(
                    message:
                        "@KSCommand functions cannot have variadic parameters; declare an array parameter instead.",
                    line: 2, column: 13,
                    fixIts: [
                        .init(message: "Replace the variadic parameter with an array parameter.")
                    ])
            ],
            macros: macros)
    }
}
