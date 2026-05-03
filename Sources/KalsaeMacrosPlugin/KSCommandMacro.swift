import SwiftDiagnostics
import SwiftSyntax
/// `@KSCommand` 매크로 구현체. 함수 선언을 분석해 JSON 인자를
/// 디코딩하고 변환한 뒤, `KSCommandRegistry`에
/// 등록하는 피어 함수를 생성한다.
import SwiftSyntaxMacros

// `KSMacroError`는 SwiftDiagnostics 도입 전에도 throw를 사용할 수
// 있도록 별도 경로가 존재하지만, 매크로 내부의 API 변환을
// 위해 현재도 남아 있다.
public struct KSCommandMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let fn = declaration.as(FunctionDeclSyntax.self) else {
            // 선언이 함수가 아니면 진단을 위해 throw하는 대신
            // diagnose를 사용. 이렇게 하면 여러 오류가
            // 있어도 사용자에게 한꺼번에 보여줄 수 있다.
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: KSCommandDiagnostic.notAFunction))
            return []
        }

        // 매크로 변환 검증 단계를 통과하지 못하면 생성 코드가
        // 잘못된 접근을 시도해 사용자에게 혼란을 줄 수 있으므로
        // 일찍 중단하는 것이 바람직하다.
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

        // 생성된 문자열 리터럴에서 레지스트리 이름 추출.
        let registryName = Self.registryName(from: node) ?? funcName

        // 매크로 변수 추출.
        let params = signature.parameterClause.parameters

        // 빈 생성자 Args 구조체 타입 선언.
        var argFields: [String] = []
        var callArgs: [String] = []
        for param in params {
            let firstName = param.firstName.text
            let secondName = param.secondName?.text
            // JSON 키 = 인자 레이블(있는 경우), 그렇지 않으면 내부 이름.
            let jsonKey: String = (firstName == "_") ? (secondName ?? "_") : firstName
            let typeText = param.type.trimmedDescription

            argFields.append("let \(jsonKey): \(typeText)")

            // 호출 인자 레이블
            //   `func f(_ x: Int)`  레이블 없음
            //   `func f(x: Int)`    `x: args.x`
            //   `func f(a b: Int)`  `a: args.a`
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
            // 인자가 없는 명령은 빈 페이로드를 전달한다.
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
            if isAsync { s += "await " }
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

        // 생성된 함수들은 기본적으로 @Sendable + async이다.
        // `__KSArgs_<funcName>`은 피어 함수 내에서 중첩된 타입의
        // 전체 선언으로 생성된다. Swift 6.3 Windows IRGen이 마크롤
        // 처리할 때 중첩 타입 선언을 찾는 특수 로직을 필요로 하기 때문이다.

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

    /// `@KSCommand("foo")`에서 문자열 리터럴에서 레지스트리 이름을 추출한다.
    private static func registryName(from node: AttributeSyntax) -> String? {
        guard case .argumentList(let args) = node.arguments else { return nil }
        guard let first = args.first else { return nil }
        guard let literal = first.expression.as(StringLiteralExprSyntax.self) else {
            return nil
        }
        // 보간 문자열 세그먼트를 걸러낸다.
        var s = ""
        for seg in literal.segments {
            if let ss = seg.as(StringSegmentSyntax.self) {
                s += ss.content.text
            } else {
                // 보간(interpolation) 세그먼트가 있으면 중단한다.
                return nil
            }
        }
        return s
    }

    // MARK: - 검증 헬퍼

    /// 함수 시그니처를 검사해 잘못된 접근을 시도하기 전에 일찍 중단하고
    /// 적절한 오류를 진단해 사용자에게 혼란을 주지 않도록 한다.
    /// 검증이 실패한 경우 `false`를 반환하며, 매크로는 중단해야 한다.
    private static func validateParameters(
        fn: FunctionDeclSyntax,
        in context: some MacroExpansionContext
    ) -> Bool {
        var ok = true
        for param in fn.signature.parameterClause.parameters {
            // `inout T` 는 JSON 역직렬화가 불가능하므로 거부한다.
            if let attrType = param.type.as(AttributedTypeSyntax.self),
                attrType.specifiers.contains(where: {
                    $0.as(SimpleTypeSpecifierSyntax.self)?.specifier.tokenKind == .keyword(.inout)
                })
            {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(param.type),
                        message: KSCommandDiagnostic.inoutParameter))
                ok = false
            }
            // 가변 인자 (`T...`).
            if param.ellipsis != nil {
                let fixIt = FixIt(
                    message: KSCommandFixIt.replaceVariadicWithArray,
                    changes: [
                        // 타입을 `[T]`로 바꾸고 `...`를 제거한다.
                        .replace(
                            oldNode: Syntax(param),
                            newNode: Syntax(
                                param
                                    .with(\.type, TypeSyntax("[\(raw: param.type.trimmedDescription)]"))
                                    .with(\.ellipsis, nil)))
                    ])
                context.diagnose(
                    Diagnostic(
                        node: Syntax(param),
                        message: KSCommandDiagnostic.variadicParameter,
                        fixIts: [fixIt]))
                ok = false
            }
        }
        return ok
    }

    /// `@KSCommand(...)` 속성 인자 목록을 검증한다.
    /// 속성은 인자가 없거나 단일 문자열 리터럴만 허용하며,
    /// 그 외는 fix-it과 함께 거부한다.
    private static func validateAttributeArguments(
        node: AttributeSyntax,
        in context: some MacroExpansionContext
    ) -> Bool {
        guard case .argumentList(let args) = node.arguments else { return true }
        if args.count > 1 {
            context.diagnose(
                Diagnostic(
                    node: Syntax(args),
                    message: KSCommandDiagnostic.tooManyArguments))
            return false
        }
        guard let first = args.first else { return true }
        guard let literal = first.expression.as(StringLiteralExprSyntax.self) else {
            // `@KSCommand(123)` 은 리터럴이 아니면 fix-it으로 인자 제거를 제안.
            let fixIt = FixIt(
                message: KSCommandFixIt.removeArgument,
                changes: [
                    .replace(
                        oldNode: Syntax(args),
                        newNode: Syntax(LabeledExprListSyntax([])))
                ])
            context.diagnose(
                Diagnostic(
                    node: Syntax(first.expression),
                    message: KSCommandDiagnostic.nonLiteralName,
                    fixIts: [fixIt]))
            return false
        }
        // 보간 세그먼트가 있으면 (예: `\(name)`) 거부한다.
        for seg in literal.segments {
            if seg.as(StringSegmentSyntax.self) == nil {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(literal),
                        message: KSCommandDiagnostic.nonLiteralName))
                return false
            }
        }
        // 빈 문자열 (`@KSCommand("")`) 거부.
        let raw = literal.segments.compactMap {
            $0.as(StringSegmentSyntax.self)?.content.text
        }.joined()
        if raw.isEmpty {
            let fixIt = FixIt(
                message: KSCommandFixIt.removeArgument,
                changes: [
                    .replace(
                        oldNode: Syntax(args),
                        newNode: Syntax(LabeledExprListSyntax([])))
                ])
            context.diagnose(
                Diagnostic(
                    node: Syntax(literal),
                    message: KSCommandDiagnostic.emptyName,
                    fixIts: [fixIt]))
            return false
        }
        return true
    }
}
enum KSMacroError: Error, CustomStringConvertible {
    case notAFunction

    var description: String {
        switch self {
        case .notAFunction:
            return "@KSCommand can only be applied to function declarations."
        }
    }
}
