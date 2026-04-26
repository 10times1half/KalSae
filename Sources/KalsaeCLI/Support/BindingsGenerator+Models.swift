import SwiftSyntax

extension KSBindingsGenerator {
    // MARK: - Models
    //
    // 공개 노출 표면을 최소화하기 위해 모두 internal로 둔다 — 생성기
    // 내부 데이터 모델일 뿐 외부 사용처는 없다.

    /// Single `@KSCommand` function discovered in source.
    struct Command: Sendable {
        let funcName: String
        let commandName: String
        let params: [Param]
        /// Swift return type text. `nil` when the function returns `Void`.
        let returnType: String?
        let isThrowing: Bool
        let isAsync: Bool
    }

    /// Function parameter — `label` matches what JS will pass in the
    /// argument object; `typeText` is the raw Swift type spelling.
    struct Param: Sendable {
        let label: String
        let typeText: String
    }

    /// Codable type discovered in source. Either a `struct` (with
    /// `fields`) or an `enum` (with `cases`).
    struct TypeDecl: Sendable {
        enum Kind: Sendable { case structType, enumType }
        let kind: Kind
        let name: String
        let fields: [Field]
        let cases: [EnumCase]
        /// Raw inheritance for enums (e.g. `"String"`, `"Int"`); `nil`
        /// when the enum is a discriminated union.
        let rawType: String?
    }

    struct Field: Sendable {
        let name: String
        let typeText: String
    }

    struct EnumCase: Sendable {
        let name: String
        let associated: [Field]
    }
}
