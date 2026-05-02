// MARK: - @KSCommand
//
// 이 속성을 최상위 또는 static 함수에 붙이면 `KSCommandRegistry`를
// 통해 노출된다. 컴파일러 플러그인이 `_ksRegister_<funcName>(into:)`
// 라는 피어 함수를 만들어, JSON 인자를 디코딩하고 원본 함수를
// 호출한 뒤 결과를 인코딩해 돌려준다.
//
// 사용법
// -----
// ```swift
// @KSCommand
// func greet(name: String?) -> String {
//     "Hello, \(name ?? "World")!"
// }
//
// // 이후 `KSApp.boot`의 configure 블록에서:
// try await _ksRegister_greet(into: registry)
// ```
//
// 속성은 레지스트리 이름을 문자열 리터럴로 받을 수 있다:
// `@KSCommand("user.greet")`. 생략하면 Swift 식별자가 쓰인다.
//
// 지원하는 시그니처
// --------------------
// - `Decodable` 타입의 매개변수 개수 제한 없음. 각 매개변수의 인자 레이블
//   (없으면 내부 이름)이 JSON 키로 매핑된다.
// - async 함수: 생성된 래퍼가 await 한다.
// - throws 함수: 던져진 에러는 잡힌다. `KSError`는 그대로 전파되고,
//   그 외는 `KSError.commandExecutionFailed`로 감싸진다.
// - `-> Void` 반환: 빈 JSON 객체 `{}`가 돌아간다.
// - 임의의 `Encodable` 반환 타입.
@attached(peer, names: prefixed(_ksRegister_), prefixed(__KSArgs_))
public macro KSCommand(_ name: String? = nil) =
    #externalMacro(
        module: "KalsaeMacrosPlugin", type: "KSCommandMacro")
