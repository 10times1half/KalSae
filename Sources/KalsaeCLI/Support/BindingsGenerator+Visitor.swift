import SwiftSyntax

extension KSBindingsGenerator {
    /// Swift 파일을 파싱하여 `@KSCommand` 함수와
    /// Codable struct/enum 선언을 수집한다.
    ///
    /// 이 방문자는 의도적으로 너그럽rd하게 설계되어 있다:
    /// `kalsae generate`는 와치 루프에서 실행되므로
    /// (e.g. 볼 수 없는 타입 참조 등) 컴파일이 안 되는 소스도 허용한다.
    final class Visitor: SyntaxVisitor {
        var commands: [Command] = []
        var types: [TypeDecl] = []

        init() { super.init(viewMode: .sourceAccurate) }

        // MARK: 함수

        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            guard let attr = ksCommandAttribute(node.attributes) else {
                return .visitChildren
            }
            let funcName = node.name.text
            let commandName = attr.isEmpty ? funcName : attr
            let params: [Param] = node.signature.parameterClause.parameters.map { p in
                let label =
                    (p.firstName.text == "_")
                    ? (p.secondName?.text ?? p.firstName.text)
                    : p.firstName.text
                return Param(
                    label: label,
                    typeText: p.type.trimmedDescription)
            }
            let ret = node.signature.returnClause?.type.trimmedDescription
            let isThrowing = node.signature.effectSpecifiers?.throwsClause != nil
            let isAsync = node.signature.effectSpecifiers?.asyncSpecifier != nil
            commands.append(
                Command(
                    funcName: funcName,
                    commandName: commandName,
                    params: params,
                    returnType: ret,
                    isThrowing: isThrowing,
                    isAsync: isAsync))
            return .visitChildren
        }

        // MARK: 구조체

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            guard inheritsCodable(node.inheritanceClause) else {
                return .visitChildren
            }
            var fields: [Field] = []
            for member in node.memberBlock.members {
                guard let v = member.decl.as(VariableDeclSyntax.self),
                    v.bindingSpecifier.text == "let" || v.bindingSpecifier.text == "var"
                else { continue }
                for b in v.bindings {
                    // 계산 프로퍼티(명시적 accessor 블록이 있는 경우,
                    // 예: `var x: T { ... }`)는 건너뛴다.
                    if b.accessorBlock != nil { continue }
                    guard let id = b.pattern.as(IdentifierPatternSyntax.self),
                        let t = b.typeAnnotation?.type.trimmedDescription
                    else { continue }
                    let typeText = t
                    // 존재 타입과 메타타입은 JSON 형태가 아니므로 제외한다.
                    if typeText.hasPrefix("any ") || typeText.hasPrefix("some ")
                        || typeText.contains(".Type")
                    {
                        continue
                    }
                    fields.append(
                        Field(
                            name: KSBindingsGenerator.stripBackticks(id.identifier.text),
                            typeText: typeText))
                }
            }
            types.append(
                TypeDecl(
                    kind: .structType,
                    name: node.name.text,
                    fields: fields,
                    cases: [],
                    rawType: nil))
            return .visitChildren
        }

        // MARK: 열거형

        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
            guard inheritsCodable(node.inheritanceClause) else {
                return .visitChildren
            }
            var raw: String? = nil
            if let inh = node.inheritanceClause {
                for entry in inh.inheritedTypes {
                    let t = entry.type.trimmedDescription
                    if t == "String" || t == "Int" {
                        raw = t
                        break
                    }
                }
            }
            var cases: [EnumCase] = []
            for member in node.memberBlock.members {
                guard let cd = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
                for el in cd.elements {
                    var assoc: [Field] = []
                    if let params = el.parameterClause?.parameters {
                        for (i, p) in params.enumerated() {
                            let name = p.firstName?.text ?? "_\(i)"
                            assoc.append(
                                Field(
                                    name: name,
                                    typeText: p.type.trimmedDescription))
                        }
                    }
                    cases.append(
                        EnumCase(
                            name: KSBindingsGenerator.stripBackticks(el.name.text),
                            associated: assoc))
                }
            }
            types.append(
                TypeDecl(
                    kind: .enumType,
                    name: node.name.text,
                    fields: [],
                    cases: cases,
                    rawType: raw))
            return .visitChildren
        }

        // MARK: 헬퍼

        /// 속성이 있는 리터럴 명령 이름 인수를 반환한다
        /// (`@KSCommand("foo.bar")` → `"foo.bar"`), 속성이 없는 경우는 빈 문자열
        /// (`@KSCommand`), 함수에 `@KSCommand` 속성이 없으면 `nil`을 반환한다.
        private func ksCommandAttribute(_ attrs: AttributeListSyntax) -> String? {
            for entry in attrs {
                guard let a = entry.as(AttributeSyntax.self) else { continue }
                let name = a.attributeName.trimmedDescription
                if name != "KSCommand" { continue }
                if case .argumentList(let args) = a.arguments {
                    for arg in args {
                        if let s = arg.expression.as(StringLiteralExprSyntax.self) {
                            return s.segments.first?.as(StringSegmentSyntax.self)?
                                .content.text
                        }
                    }
                }
                return ""
            }
            return nil
        }

        private func inheritsCodable(_ clause: InheritanceClauseSyntax?) -> Bool {
            guard let clause else { return false }
            for entry in clause.inheritedTypes {
                let t = entry.type.trimmedDescription
                if t == "Codable" || t == "Decodable" || t == "Encodable" {
                    return true
                }
            }
            return false
        }
    }
}
