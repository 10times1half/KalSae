import SwiftDiagnostics
import SwiftSyntax

/// Diagnostic categories emitted by `@KSCommand`. Surface as compiler
/// errors with structured IDs so callers can suppress individually if
/// needed and IDEs can route them to specific quick-fix providers.
enum KSCommandDiagnostic: String, DiagnosticMessage {
    case notAFunction          = "ksmacro.not_a_function"
    case emptyName             = "ksmacro.empty_name"
    case nonLiteralName        = "ksmacro.non_literal_name"
    case tooManyArguments      = "ksmacro.too_many_arguments"
    case inoutParameter        = "ksmacro.inout_parameter"
    case variadicParameter     = "ksmacro.variadic_parameter"
    case staticOnNonType       = "ksmacro.static_on_non_type"

    var diagnosticID: MessageID {
        MessageID(domain: "Kalsae.Macro.KSCommand", id: rawValue)
    }

    var severity: DiagnosticSeverity { .error }

    var message: String {
        switch self {
        case .notAFunction:
            return "@KSCommand can only be applied to function declarations."
        case .emptyName:
            return "@KSCommand registry name must not be empty."
        case .nonLiteralName:
            return "@KSCommand requires a plain string literal name (no interpolation)."
        case .tooManyArguments:
            return "@KSCommand accepts at most one argument (an optional string literal name)."
        case .inoutParameter:
            return "@KSCommand functions cannot have `inout` parameters; the argument payload is JSON-decoded by value."
        case .variadicParameter:
            return "@KSCommand functions cannot have variadic parameters; declare an array parameter instead."
        case .staticOnNonType:
            return "@KSCommand may only annotate free or static functions; instance methods need an explicit registry binding."
        }
    }
}

/// Fix-its emitted by `@KSCommand`.
enum KSCommandFixIt: FixItMessage {
    case removeArgument
    case replaceVariadicWithArray

    var fixItID: MessageID {
        switch self {
        case .removeArgument:
            return MessageID(domain: "Kalsae.Macro.KSCommand",
                             id: "fixit.remove_argument")
        case .replaceVariadicWithArray:
            return MessageID(domain: "Kalsae.Macro.KSCommand",
                             id: "fixit.replace_variadic_with_array")
        }
    }

    var message: String {
        switch self {
        case .removeArgument:
            return "Remove the argument to use the function name as the registry key."
        case .replaceVariadicWithArray:
            return "Replace the variadic parameter with an array parameter."
        }
    }
}
