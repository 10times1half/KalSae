import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct KalsaeMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        KSCommandMacro.self
    ]
}
