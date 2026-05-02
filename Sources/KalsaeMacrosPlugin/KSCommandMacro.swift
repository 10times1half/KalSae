import SwiftDiagnostics
import SwiftSyntax
/// `@KSCommand` 援ы쁽泥? ?⑥닔 ?좎뼵??泥⑤??섏뼱 JSON ?몄퐫???붿퐫??諛?/// ?ㅻ쪟 蹂?섏쓣 泥섎━?섎㈃???먮낯??`KSCommandRegistry`??/// ?깅줉?섎뒗 ?쇱뼱 ?⑥닔瑜?諛쒗뻾?쒕떎.
import SwiftSyntaxMacros

// `KSMacroError`??SwiftDiagnostics ?꾩엯 ?댁쟾???곗씠??throw ?꾩슜 ?쇱씠??
// ?곗닔 寃쎈줈媛 ?댁젣 diagnose 湲곕컲?대ŉ ?꾨땲吏留??뚯뒪?몄뿉?쒖쓽 API ?명솚??// ?꾪빐 議댁옱???좎??쒕떎.
public struct KSCommandMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let fn = declaration.as(FunctionDeclSyntax.self) else {
            // ?쒖옄由ъ뿉???묓빐?ㅻ떊 ?붿옄 ?꾩씠肄섏쓣 ?먮븣由щ룄濡?throw???            // diagnose瑜??ъ슜. ?ㅻⅨ ?먰룊?덉쓣 ?곸떎?섏? ?딄퀬 ?섎굹??            // ?섎? ?덈뒗 ?ㅻ쪟留??ъ슜?먯뿉寃?蹂댁뿬以??
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: KSCommandDiagnostic.notAFunction))
            return []
        }

        // 留ㅺ컻蹂???쒖빟 寃利? ?꾧꺽???ㅽ뙣???덉씠吏留??뺤옣??肄붾뱶媛
        // ???泥댁빱瑜??몃옒?섏? 留꾩씠???먯껜??紐낆떆???ㅻ쪟瑜?        // ?쏆뼱二쇰뒗 寃??붾쾭洹뱀쟻?쇰줈 媛移??덈떎.
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

        // ?좏깮??臾몄옄??由ы꽣???대쫫 ?몄옄 異붿텧.
        let registryName = Self.registryName(from: node) ?? funcName

        // 留ㅺ컻蹂???섏쭛.
        let params = signature.parameterClause.parameters

        // 鍮꾧났媛?Args 援ъ“泥?蹂몃Ц 援ъ꽦.
        var argFields: [String] = []
        var callArgs: [String] = []
        for param in params {
            let firstName = param.firstName.text
            let secondName = param.secondName?.text
            // JSON ??= ?몄옄 ?덉씠釉??덈뒗 寃쎌슦), 洹몃젃吏 ?딆쑝硫??대? ?대쫫.
            let jsonKey: String = (firstName == "_") ? (secondName ?? "_") : firstName
            let typeText = param.type.trimmedDescription

            argFields.append("let \(jsonKey): \(typeText)")

            // ?몄텧 吏???덉씠釉?
            //   `func f(_ x: Int)`  ???덉씠釉??놁쓬
            //   `func f(x: Int)`    ??`x: args.x`
            //   `func f(a b: Int)`  ??`a: args.a`
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
            // ?몄옄?녿뒗 紐낅졊? ?섏씠濡쒕뱶瑜??꾩쟾??臾댁떆?쒕떎.
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

        // ?앹꽦?섎뒗 ?몃뱾???대줈?????긽 @Sendable + async?대떎.
        // `__KSArgs_<funcName>`???쇱뼱 ?⑥닔 ?대???以묒꺽?섎뒗 ????뚯씪 ?ㅼ퐫?꾩쓽
        // ?먯껜 ?쇱뼱濡?諛⑹텧?쒕떎. Swift 6.3 Windows IRGen??留ㅽ겕濡??뺤옣???대줈?
        // ?대???以묒꺽 ??낆쓣 李몄“?섎뒗 ?붾쾭洹??뺣낫瑜?留뚮궃 ???щ옒?쒕릺湲??뚮Ц.

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

    /// `@KSCommand("foo")`?먯꽌 臾몄옄??由ы꽣???몄옄瑜?異붿텧?쒕떎.
    private static func registryName(from node: AttributeSyntax) -> String? {
        guard case .argumentList(let args) = node.arguments else { return nil }
        guard let first = args.first else { return nil }
        guard let literal = first.expression.as(StringLiteralExprSyntax.self) else {
            return nil
        }
        // ?됰쾾??臾몄옄???멸렇癒쇳듃瑜??댁뼱遺숈씤??
        var s = ""
        for seg in literal.segments {
            if let ss = seg.as(StringSegmentSyntax.self) {
                s += ss.content.text
            } else {
                // 蹂닿컙(?쒗쁽?? ??由ы꽣?댁씠 ?꾨땲誘濡?以묐떒?쒕떎.
                return nil
            }
        }
        return s
    }

    // MARK: - 寃利??ы띁

    /// ?⑥닔 ?쒓렇?덉쿂瑜?寃?ы븯???뺤옣??諛⑺빐?섍굅??留ㅽ겕濡쒓? ?쇱뼱瑜?諛쒗뻾???댄썑
    /// ???泥댁빱瑜?怨ㅻ??섍쾶 留뚮뱶??援ъ“瑜?由ы룷?명븳??
    /// ?ㅻ쪟媛 諛쒗뻾??寃쎌슦 `false`瑜?諛섑솚?섎ŉ, 留ㅽ겕濡쒕뒗 以묐떒?댁빞 ?쒕떎.
    private static func validateParameters(
        fn: FunctionDeclSyntax,
        in context: some MacroExpansionContext
    ) -> Bool {
        var ok = true
        for param in fn.signature.parameterClause.parameters {
            // `inout T` ??JSON 寃쎌슦 媛??섎?留?媛?ν븯誘濡??섎?媛 ?녿떎.
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
            // 媛蹂 ?몄옄 (`T...`).
            if param.ellipsis != nil {
                let fixIt = FixIt(
                    message: KSCommandFixIt.replaceVariadicWithArray,
                    changes: [
                        // ??낆쓣 `[T]`濡?諛붽씀怨?`...`???쒓굅?쒕떎.
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

    /// `@KSCommand(...)` ?띿꽦 ?몄닔 紐⑸줉??寃利앺븳??
    /// ?띿꽦? ?몄닔?녾굅???⑥씪 臾몄옄??由ы꽣???대쫫留??덉슜?섎ŉ,
    /// 洹??몃뒗 fix-it怨??④퍡 嫄곕??쒕떎.
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
            // `@KSCommand(123)` ??由ы꽣?댁씠 ?꾨땲硫?fix-it?쇰줈 ?몄옄 ?쒓굅 ?쒖븞.
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
        // 蹂닿컙 ?멸렇癒쇳듃媛 ?덉쑝硫?(?? `\(name)`) 嫄곕??쒕떎.
        for seg in literal.segments {
            if seg.as(StringSegmentSyntax.self) == nil {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(literal),
                        message: KSCommandDiagnostic.nonLiteralName))
                return false
            }
        }
        // 鍮?臾몄옄??`@KSCommand("")`) 嫄곕?.
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
