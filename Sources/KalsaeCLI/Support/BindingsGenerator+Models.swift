import SwiftSyntax

extension KSBindingsGenerator {
    // MARK: - 모델
    //
    // 공개 노출 표면을 최소화하기 위해 모두 internal로 둔다 — 생성기
    // 내부 데이터 모델일 뿐 외부 사용처는 없다.

    /// 소스에서 발견된 단일 `@KSCommand` 함수.
    struct Command: Sendable {
        let funcName: String
        let commandName: String
        let params: [Param]
        /// Swift 반환 타입 텍스트. 함수가 `Void`를 반환할 때는 `nil`.
        let returnType: String?
        let isThrowing: Bool
        let isAsync: Bool
    }

    /// 함수 매개변수 — `label`은 JS가 인수 객체에서 전달할 내용과 일치하며;
    /// `typeText`는 원시 Swift 타입 철자이다.
    struct Param: Sendable {
        let label: String
        let typeText: String
    }

    /// 소스에서 발견된 Codable 타입.
    /// `fields`가 있는 `struct`이거나 `cases`가 있는 `enum`이다.
    struct TypeDecl: Sendable {
        enum Kind: Sendable { case structType, enumType }
        let kind: Kind
        let name: String
        let fields: [Field]
        let cases: [EnumCase]
        /// 열거형의 원시 상속 (e.g. `"String"`, `"Int"`); 열거형이
        /// 구분자 유니인일 때는 `nil`.
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
