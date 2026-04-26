import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Implementation of `@KSCommand`. Attaches to a function declaration and
/// emits a peer function that registers the original into a
/// `KSCommandRegistry`, handling JSON encode/decode and error translation.
public struct KSCommandMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let fn = declaration.as(FunctionDeclSyntax.self) else {
            // 제자리에서 접해다닠 화자 아이콘을 널때리도록 throw대신
            // diagnose를 사용. 다른 자평안을 상실하지 않고 하나의
            // 의미 있는 오류만 사용자에게 보여준다.
            context.diagnose(
                Diagnostic(node: Syntax(node),
                           message: KSCommandDiagnostic.notAFunction))
            return []
        }

        // 매개변수 제약 검증. 엄격한 실패는 안이지만 확장된 코드가
        // 타입 체커를 트래하지 맄이클 자체에 명시적 오류를
        // 댛어주는 게 디버극적으로 가치 있다.
        if !validateParameters(fn: fn, in: context) {
            return []
        }
        if !validateAttributeArguments(node: node, in: context) {
            return []
        }

        let funcName = fn.name.text
        let signature = fn.signature
        let isAsync = signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrowing = signature.effectSpecifiers?.throwsClause != nil
        let returnType = signature.returnClause?.type.trimmedDescription
        let isVoid: Bool = {
            guard let r = returnType else { return true }
            switch r {
            case "Void", "()": return true
            default: return false
            }
        }()

        // 선택적 문자열 리터럴 이름 인자 추출.
        let registryName = Self.registryName(from: node) ?? funcName

        // 매개변수 수집.
        let params = signature.parameterClause.parameters

        // 비공개 Args 구조체 본문 구성.
        var argFields: [String] = []
        var callArgs: [String] = []
        for param in params {
            let firstName = param.firstName.text
            let secondName = param.secondName?.text
            // JSON 키 = 인자 레이블(있는 경우), 그렇지 않으면 내부 이름.
            let jsonKey: String = (firstName == "_") ? (secondName ?? "_") : firstName
            let typeText = param.type.trimmedDescription

            argFields.append("let \(jsonKey): \(typeText)")

            // 호출 지점 레이블:
            //   `func f(_ x: Int)`  → 레이블 없음
            //   `func f(x: Int)`    → `x: args.x`
            //   `func f(a b: Int)`  → `a: args.a`
            if firstName == "_" {
                callArgs.append("args.\(jsonKey)")
            } else {
                callArgs.append("\(firstName): args.\(jsonKey)")
            }
        }

        let peerName = "_ksRegister_\(funcName)"
        let argsTypeName = "__KSArgs_\(funcName)"

        let decodeBlock: String
        if params.isEmpty {
            // 인자없는 명령은 페이로드를 완전히 무시한다.
            decodeBlock = "let args = \(argsTypeName)()\n            _ = args\n            _ = data"
        } else {
            decodeBlock = """
            let args: \(argsTypeName)
            do {
                args = try Foundation.JSONDecoder().decode(\(argsTypeName).self, from: data)
            } catch {
                return .failure(KalsaeCore.KSError(
                    code: .commandDecodeFailed,
                    message: String(describing: error)))
            }
            """
        }

        let callPrefix: String = {
            var s = ""
            if isThrowing { s += "try " }
            if isAsync    { s += "await " }
            return s
        }()

        let callExpr = "\(callPrefix)\(funcName)(\(callArgs.joined(separator: ", ")))"

        let invokeBlock: String
        if isThrowing {
            if isVoid {
                invokeBlock = """
                do {
                    \(callExpr)
                } catch let e as KalsaeCore.KSError {
                    return .failure(e)
                } catch {
                    return .failure(KalsaeCore.KSError(
                        code: .commandExecutionFailed,
                        message: String(describing: error)))
                }
                let __payload = Foundation.Data("{}".utf8)
                return .success(__payload)
                """
            } else {
                invokeBlock = """
                let __result: \(returnType ?? "Void")
                do {
                    __result = \(callExpr)
                } catch let e as KalsaeCore.KSError {
                    return .failure(e)
                } catch {
                    return .failure(KalsaeCore.KSError(
                        code: .commandExecutionFailed,
                        message: String(describing: error)))
                }
                do {
                    let __payload = try Foundation.JSONEncoder().encode(__result)
                    return .success(__payload)
                } catch {
                    return .failure(KalsaeCore.KSError(
                        code: .commandEncodeFailed,
                        message: String(describing: error)))
                }
                """
            }
        } else {
            if isVoid {
                invokeBlock = """
                \(callExpr)
                let __payload = Foundation.Data("{}".utf8)
                return .success(__payload)
                """
            } else {
                invokeBlock = """
                let __result = \(callExpr)
                do {
                    let __payload = try Foundation.JSONEncoder().encode(__result)
                    return .success(__payload)
                } catch {
                    return .failure(KalsaeCore.KSError(
                        code: .commandEncodeFailed,
                        message: String(describing: error)))
                }
                """
            }
        }

        // 생성되는 핸들러 클로저는 항상 @Sendable + async이다.
        // `__KSArgs_<funcName>`는 피어 함수 내부에 중첩하는 대신 파일 스코프의
        // 자체 피어로 방출한다. Swift 6.3 Windows IRGen이 매크로 확장된 클로저
        // 내부의 중첩 타입을 참조하는 디버그 정보를 만난 때 크래시되기 때문.

        let argsDecl: String
        if params.isEmpty {
            argsDecl = """
            /// Argument payload for `\(funcName)`. Generated by `@KSCommand`.
            struct \(argsTypeName): Swift.Decodable {}
            """
        } else {
            argsDecl = """
            /// Argument payload for `\(funcName)`. Generated by `@KSCommand`.
            struct \(argsTypeName): Swift.Decodable {
                \(argFields.joined(separator: "\n                "))
            }
            """
        }

        let funcDecl = """
        /// Registers `\(funcName)` into `registry` under the name
        /// `"\(registryName)"`. Generated by `@KSCommand`.
        func \(peerName)(into registry: KalsaeCore.KSCommandRegistry) async {
            await registry.register("\(registryName)") { @Sendable (data: Foundation.Data) async -> Swift.Result<Foundation.Data, KalsaeCore.KSError> in
                \(decodeBlock)
                \(invokeBlock)
            }
        }
        """

        return [
            DeclSyntax(stringLiteral: argsDecl),
            DeclSyntax(stringLiteral: funcDecl),
        ]
    }

    /// Pulls a string-literal argument out of `@KSCommand("foo")`.
    private static func registryName(from node: AttributeSyntax) -> String? {
        guard case let .argumentList(args) = node.arguments else { return nil }
        guard let first = args.first else { return nil }
        guard let literal = first.expression.as(StringLiteralExprSyntax.self) else {
            return nil
        }
        // 평범한 문자열 세그먼트를 이어붙인다.
        var s = ""
        for seg in literal.segments {
            if let ss = seg.as(StringSegmentSyntax.self) {
                s += ss.content.text
            } else {
                // 보간(표현식) — 리터럴이 아니므로 중단한다.
                return nil
            }
        }
        return s
    }

    // MARK: - Validation helpers

    /// Inspects the function signature and reports any constructs that
    /// would either prevent expansion or trip up the type checker once
    /// the macro has emitted its peer. Returns `false` when an error
    /// was emitted, in which case the macro should bail out.
    private static func validateParameters(
        fn: FunctionDeclSyntax,
        in context: some MacroExpansionContext
    ) -> Bool {
        var ok = true
        for param in fn.signature.parameterClause.parameters {
            // `inout T` — JSON 경우 값 의미만 가능하므로 의미가 없다.
            if let attrType = param.type.as(AttributedTypeSyntax.self),
               attrType.specifiers.contains(where: { $0.as(SimpleTypeSpecifierSyntax.self)?.specifier.tokenKind == .keyword(.inout) }) {
                context.diagnose(
                    Diagnostic(node: Syntax(param.type),
                               message: KSCommandDiagnostic.inoutParameter))
                ok = false
            }
            // 가변 인자 (`T...`).
            if let _ = param.ellipsis {
                let fixIt = FixIt(
                    message: KSCommandFixIt.replaceVariadicWithArray,
                    changes: [
                        // 타입을 `[T]`로 바꾸고 `...`을 제거한다.
                        .replace(
                            oldNode: Syntax(param),
                            newNode: Syntax(
                                param
                                    .with(\.type, TypeSyntax("[\(raw: param.type.trimmedDescription)]"))
                                    .with(\.ellipsis, nil))),
                    ])
                context.diagnose(
                    Diagnostic(node: Syntax(param),
                               message: KSCommandDiagnostic.variadicParameter,
                               fixIts: [fixIt]))
                ok = false
            }
        }
        return ok
    }

    /// Validates the `@KSCommand(...)` attribute argument list. The
    /// attribute accepts either no arguments or a single string-literal
    /// name; anything else is rejected with a fix-it.
    private static func validateAttributeArguments(
        node: AttributeSyntax,
        in context: some MacroExpansionContext
    ) -> Bool {
        guard case let .argumentList(args) = node.arguments else { return true }
        if args.count > 1 {
            context.diagnose(
                Diagnostic(node: Syntax(args),
                           message: KSCommandDiagnostic.tooManyArguments))
            return false
        }
        guard let first = args.first else { return true }
        guard let literal = first.expression.as(StringLiteralExprSyntax.self) else {
            // `@KSCommand(123)` 등 리터럴이 아니면 fix-it으로 인자 제거 제안.
            let fixIt = FixIt(
                message: KSCommandFixIt.removeArgument,
                changes: [
                    .replace(oldNode: Syntax(args),
                             newNode: Syntax(LabeledExprListSyntax([]))),
                ])
            context.diagnose(
                Diagnostic(node: Syntax(first.expression),
                           message: KSCommandDiagnostic.nonLiteralName,
                           fixIts: [fixIt]))
            return false
        }
        // 보간 세그먼트가 있으면 (예: `\(name)`) 거부한다.
        for seg in literal.segments {
            if seg.as(StringSegmentSyntax.self) == nil {
                context.diagnose(
                    Diagnostic(node: Syntax(literal),
                               message: KSCommandDiagnostic.nonLiteralName))
                return false
            }
        }
        // 빈 문자열(`@KSCommand("")`) 거부.
        let raw = literal.segments.compactMap {
            $0.as(StringSegmentSyntax.self)?.content.text
        }.joined()
        if raw.isEmpty {
            let fixIt = FixIt(
                message: KSCommandFixIt.removeArgument,
                changes: [
                    .replace(oldNode: Syntax(args),
                             newNode: Syntax(LabeledExprListSyntax([]))),
                ])
            context.diagnose(
                Diagnostic(node: Syntax(literal),
                           message: KSCommandDiagnostic.emptyName,
                           fixIts: [fixIt]))
            return false
        }
        return true
    }
}

// `KSMacroError`는 SwiftDiagnostics 도입 이전에 쓰이던 throw 전용 솼이다.
// 우수 경로가 이제 diagnose 기반이며 아니지만 테스트에서의 API 호환을
// 위해 존재는 유지한다.
enum KSMacroError: Error, CustomStringConvertible {
    case notAFunction

    var description: String {
        switch self {
        case .notAFunction:
            return "@KSCommand can only be applied to function declarations."
        }
    }
}
