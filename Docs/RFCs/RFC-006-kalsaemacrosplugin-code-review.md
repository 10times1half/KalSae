# RFC-006: KalsaeMacrosPlugin 코드 리뷰

| 항목 | 내용 |
|------|------|
| **상태** | 초안 |
| **작성일** | 2026-05-09 |
| **검토자** | 품질관리팀 |
| **대상** | `Sources/KalsaeMacrosPlugin/` 전면 코드 리뷰 |

---

## 1. 검토 개요

KalsaeMacrosPlugin은 `@KSCommand` 매크로의 컴파일러 플러그인 구현체로,
SwiftSyntax 기반 PeerMacro를 통해 함수 선언을 분석해 JSON 인자 디코딩 및
`KSCommandRegistry` 등록 코드를 자동 생성한다.

### 1.1 검토 대상 파일

| 파일 | 역할 | 라인 수 |
|------|------|---------|
| `Sources/KalsaeMacrosPlugin/Plugin.swift` | CompilerPlugin 진입점 | 9 |
| `Sources/KalsaeMacrosPlugin/KSCommandDiagnostics.swift` | 진단 메시지 + FixIt 정의 | 68 |
| `Sources/KalsaeMacrosPlugin/KSCommandMacro.swift` | **핵심**: `@KSCommand` PeerMacro 구현 | 346 |
| `Sources/KalsaeMacros/KSCommand.swift` | 소비자 측 `@attached(peer)` 선언 | 35 |
| `Tests/KalsaeMacrosTests/KSCommandMacroTests.swift` | 확장 테스트 | 175 |
| `Tests/KalsaeMacrosTests/KSCommandMacroDiagnosticsTests.swift` | 진단 테스트 | 95 |

---

## 2. 🔴 Critical Issues (반드시 수정 필요)

### 2.1 `import` 문 순서 오염

**파일:** `KSCommandDiagnostics.swift` (line 1-5), `KSCommandMacro.swift` (line 1-6)

**현재 코드:**
```swift
// KSCommandDiagnostics.swift
import SwiftDiagnostics       // line 1
/// `@KSCommand`이 발행하는 진단 카테고리...  // line 2-4 (doc comment가 import 사이에 끼어있음)
import SwiftSyntax            // line 5

// KSCommandMacro.swift
import SwiftDiagnostics       // line 1
import SwiftSyntax            // line 2
/// `@KSCommand` 매크로 구현체...           // line 3-6 (doc comment가 import 사이에 끼어있음)
import SwiftSyntaxMacros      // line 7
```

**문제:** Doc comment 블록이 `import` 선언들 사이에 끼어 있어 Swift의 일반적인 컨벤션(import block → doc comment → code)을 위반한다. 컴파일에는 문제가 없지만 가독성과 일관성을 해친다.

**수정 방안:** 모든 `import`를 하나의 블록으로 모으고, 그 뒤에 doc comment를 배치한다.

---

### 2.2 `KSMacroError` 데드 코드

**파일:** `KSCommandMacro.swift` (line 337-346)

**현재 코드:**
```swift
enum KSMacroError: Error, CustomStringConvertible {
    case notAFunction

    var description: String {
        switch self {
        case .notAFunction:
            return "@KSCommand can only be applied to function declarations."
        }
    }
}
```

**문제:**
- `KSMacroError.notAFunction`은 `expansion()` 내에서 **단 한 번도 사용되지 않는다** (line 17-26에서 `context.diagnose()`로 처리).
- 주석(line 8-10)에서도 "SwiftDiagnostics 도입 전에도 throw를 사용할 수 있도록 별도 경로가 존재하지만, 현재도 남아 있다"고 명시적으로 인정.
- `throws`가 함수 시그니처에 선언되어 있지만(`throws -> [DeclSyntax]`), 실제로 `throw`하는 경로가 전혀 없다.

**수정 방안:**
1. `KSMacroError` 타입 전체를 제거한다.
2. `expansion()`의 `throws` 선언을 제거한다 (`-> [DeclSyntax]`).
3. 관련 주석(line 8-10)도 제거한다.

---

### 2.3 `__KSArgs_` 타입 이름 불일치 — 생성 코드 vs `@attached(peer)` 선언

**파일:** `KSCommandMacro.swift` (line 81) vs `Sources/KalsaeMacros/KSCommand.swift` (line 32)

**현재 코드:**
```swift
// KSCommandMacro.swift line 81
let argsTypeName = "__KSArgs_\(funcName)"

// KSCommand.swift line 32
@attached(peer, names: prefixed(_ksRegister_), prefixed(__KSArgs_))
```

**문제:** `@attached(peer)`의 `names:` 선언은 `prefixed(__KSArgs_)`로 되어 있다. 그런데 생성되는 타입 이름은 `__KSArgs_<funcName>`이다. SwiftSyntax의 `prefixed` 매처는 접두사 매칭을 하므로 실제로는 동작하지만, **의도와 다르다.** `__KSArgs_`는 접두사가 아니라 전체 타입 이름의 일부일 뿐이다. 만약 어떤 함수 이름이 `Args_foo` 같은 식으로 시작한다면 의도치 않은 이름 충돌이 발생할 수 있다.

**수정 방안:** `@attached(peer)` 선언을 `named(__KSArgs_)`가 아니라 더 구체적으로 변경하거나, 생성되는 타입 이름을 `__KSArgs_` 접두사만으로 충분히 유니크하게 보장할 수 있도록 설계를 재검토한다. (현실적으로 충돌 가능성은 낮지만, 매크로 생성 심볼의 이름 충돌은 디버깅이 매우 어렵다.)

---

### 2.4 `Foundation` 모듈 참조 일관성

**파일:** `KSCommandMacro.swift` 전반

생성된 코드에서 `Foundation.JSONDecoder`, `Foundation.JSONEncoder`, `Foundation.Data`를 **명시적 모듈 한정자**로 사용하고 있다. 이는 생성된 코드가 `import Foundation` 없이도 컴파일되도록 하기 위한 의도로 보인다.

**문제:**
- `KalsaeMacrosPlugin` 타겟 자체는 `Foundation`을 import하지 않는다. 생성된 **문자열 리터럴**에만 `Foundation.` 접두사가 붙어 있다.
- AGENTS.md §4: "Files that expose **public** types **must** use `public import Foundation`" — `KSCommandMacro`는 `public struct`이지만 `Foundation`을 import하지 않는다. 생성된 코드가 `Foundation`에 의존하는 것은 매크로 확장 결과물이므로 `KalsaeMacrosPlugin` 모듈의 import와는 무관하지만, **매크로 사용처에서 Foundation을 사용할 수 있어야 한다는 전제 조건을 문서화해야 한다.**

**수정 방안:** 최소한 doc comment에 "이 매크로를 사용하려면 사용처에서 `import Foundation`이 필요하다"는 내용을 추가한다.

---

### 2.5 `inout` 파라미터 감지 로직의 취약성

**파일:** `KSCommandMacro.swift` (line 238-248)

**현재 코드:**
```swift
if let attrType = param.type.as(AttributedTypeSyntax.self),
    attrType.specifiers.contains(where: {
        $0.as(SimpleTypeSpecifierSyntax.self)?.specifier.tokenKind == .keyword(.inout)
    })
```

**문제:** SwiftSyntax의 `AttributedTypeSyntax.specifiers` 배열에서 `inout`을 찾는 방식이다. Swift 6.0에서 `inout`은 `SimpleTypeSpecifierSyntax`로 표현되지만, 향후 SwiftSyntax 버전에서 표현 방식이 바뀌면 감지에 실패할 수 있다. 또한 `inout`이 `specifiers`의 첫 번째 요소가 아닐 경우(예: `inout consuming T`)에도 정상 동작하지만, Swift 6.0에서 `inout consuming`은 문법적으로 허용되지 않으므로 현실적인 문제는 아니다.

**수정 방안:** `param.type.as(AttributedTypeSyntax.self)`가 nil일 경우 (즉, `inout`이 없는 일반 타입)은 통과하지만, `inout`이 `specifiers`에 있으면서 `AttributedTypeSyntax`로 파싱되지 않는 엣지 케이스가 존재할 수 있다. `param.type.tokenKind`를 직접 확인하는 보다 직접적인 방법을 고려한다.

---

## 3. 🟡 Warning Issues (권장 수정)

### 3.1 `registryName(from:)`의 중복 로직

**파일:** `KSCommandMacro.swift` (line 207-224) vs `validateAttributeArguments` (line 276-335)

`registryName(from:)`과 `validateAttributeArguments()`가 **문자열 리터럴 세그먼트를 순회하며 보간을 검사하는 로직을 중복**으로 가지고 있다.

- `registryName(from:)`: line 215-221에서 보간 세그먼트 검사 후 `nil` 반환
- `validateAttributeArguments()`: line 306-313에서 동일한 검사 후 진단

**수정 방안:** `registryName(from:)`을 `validateAttributeArguments()` **내부에서만** 호출하거나, 검증 로직을 공유 헬퍼로 추출한다. 현재는 `expansion()`에서 `validateAttributeArguments()`를 먼저 호출한 후(line 34-36), `registryName(from:)`을 다시 호출(line 52)하여 동일한 AST 순회를 두 번 수행한다.

---

### 3.2 `isVoid` 판별 로직의 불완전성

**파일:** `KSCommandMacro.swift` (line 43-49)

**현재 코드:**
```swift
let isVoid: Bool = {
    guard let r = returnType else { return true }
    switch r {
    case "Void", "()": return true
    default: return false
    }
}()
```

**문제:**
- `Swift.Void`, `Foundation.Void` 등 모듈 한정자가 붙은 경우 감지하지 못한다.
- `()` (Void)는 `trimmedDescription`이 `()`가 맞지만, 공백이 있는 `( )` 같은 경우도 있을 수 있다.
- `Never` 반환 타입은 고려되지 않았다.

**수정 방안:** `returnClause?.type`을 AST 레벨에서 `IdentifierTypeSyntax` 또는 `TupleTypeSyntax`로 직접 매칭하는 것이 더 안전하다.

---

### 3.3 `_ = args` / `_ = data` 패턴의 냄새

**파일:** `KSCommandMacro.swift` (line 86)

**현재 코드:**
```swift
decodeBlock = "let args = \(argsTypeName)()\n            _ = args\n            _ = data"
```

**문제:** 인자가 없는 명령에서 `args`와 `data`를 받아서 사용하지 않으므로 컴파일러 경고를 피하기 위해 `_ =`로 할당한다. 이는 생성된 코드에서 불필요한 노이즈를 만든다.

**수정 방안:** 클로저 시그니처 자체를 `@Sendable (_: Foundation.Data) async -> ...`로 변경하거나, `data` 파라미터를 언더스코어로 받도록 생성 코드를 변경한다. 하지만 이는 `registry.register`의 시그니처를 바꾸는 일이므로 단순하지 않다. 최소한 `_ = data`는 `data`가 클로저 캡처로 들어오는 것이므로 경고가 발생하지 않을 수 있다 — 확인 필요.

---

### 3.4 테스트 코드의 `__Args` 타입 이름 불일치

**파일:** `Tests/KalsaeMacrosTests/KSCommandMacroTests.swift`

테스트에서 기대하는 확장 결과(`expandedSource`)에는 `__Args`라는 타입 이름이 하드코딩되어 있다:

```swift
// line 32: struct __Args: Swift.Decodable {
```

하지만 실제 구현(`KSCommandMacro.swift` line 81)에서는 `__KSArgs_\(funcName)`을 생성한다:

```swift
let argsTypeName = "__KSArgs_\(funcName)"
```

**이 테스트는 현재 실패해야 정상이다.** 만약 통과하고 있다면, 테스트 인프라(`assertMacroExpansion`)가 매크로를 실제로 확장하지 않고 문자열을 그대로 비교하고 있거나, 테스트가 무언가 다른 방식으로 동작하고 있는 것이다.

→ **이것은 잠재적인 테스트 거짓 양성(false positive)이다.** 반드시 확인이 필요하다.

---

### 3.5 `@Sendable` 클로저 내부에서 `JSONDecoder` 인스턴스 생성

**파일:** `KSCommandMacro.swift` (line 193)

**현재 코드:**
```swift
await registry.register("\(registryName)") { @Sendable (data: Foundation.Data) async -> Swift.Result<Foundation.Data, KalsaeCore.KSError> in
```

생성된 클로저는 `@Sendable`이다. `args`는 클로저 내부에서 생성되므로 (`let args = ...`) 데이터 경합 문제는 없다. 하지만 `Foundation.JSONDecoder().decode()`에서 새 `JSONDecoder` 인스턴스를 매 호출마다 생성하는 것은 성능 측면에서 약간의 오버헤드가 있다.

**수정 방안:** `JSONDecoder` 인스턴스를 정적 공유 인스턴스로 사용하는 것을 고려하거나, 최소한 생성 코드에서 `JSONDecoder()` 호출을 한 번만 하도록 최적화한다. (단, `JSONDecoder`는 thread-safe하므로 공유해도 안전하다.)

---

## 4. 🟢 칭찬할 점 (유지할 것)

1. **진단 우선 접근법:** `throw` 대신 `context.diagnose()`를 사용해 여러 오류를 한 번에 사용자에게 보여주는 방식은 Swift 매크로 모범 사례에 부합한다.
2. **Fix-it 제공:** `variadicParameter`, `nonLiteralName`, `emptyName`에 대해 Fix-it을 제공하는 것은 사용자 경험을 크게 향상시킨다.
3. **타입 안전한 오류 처리:** 생성된 코드에서 `KSError` 타입 캐스팅(`catch let e as KalsaeCore.KSError`)을 통해 타입 안전하게 오류를 전파하는 패턴은 AGENTS.md의 "Typed throws everywhere" 정신과 일치한다.
4. **모듈 한정자 사용:** 생성된 코드에서 `Foundation.`, `KalsaeCore.`, `Swift.` 접두사를 명시적으로 사용하여 모듈 충돌을 방지한 점은 좋은 습관이다.
5. **테스트 커버리지:** 기본 확장 테스트(4개) + 진단 테스트(4개)로 주요 케이스를 커버하고 있다.

---

## 5. 종합 평가

| 영역 | 등급 | 설명 |
|------|------|------|
| **기능 정확성** | 🟢 A | 매크로가 생성하는 코드의 논리는 정확하고, 에러 처리가 체계적임 |
| **코드 품질** | 🟡 B | import 순서 오염, 데드 코드, 중복 로직 등 청소 필요 |
| **테스트 품질** | 🟠 C | **테스트 기대값과 실제 생성값이 불일치** — 반드시 확인 필요 |
| **문서화** | 🟢 A | doc comment가 상세하고, 사용 예제가 포함되어 있음 |
| **안전성** | 🟢 A | `@Sendable` 클로저, 타입 안전한 오류 처리, 모듈 한정자 사용 |

**종합 점수: 82/100** (기능은 견고하나, 데드 코드 제거 + 테스트 검증 + import 정리가 필요)

---

## 6. 우선순위별 액션 아이템

| 우선순위 | 항목 | 난이도 | 영향 |
|----------|------|--------|------|
| P0 | 테스트 `__Args` vs `__KSArgs_` 불일치 검증 | 상 | 테스트 신뢰성 |
| P0 | `KSMacroError` 데드 코드 제거 + `throws` 제거 | 하 | 코드 품질 |
| P1 | `import` 문 순서 정리 | 하 | 가독성 |
| P1 | `registryName(from:)` 중복 로직 제거 | 중 | 성능 + 유지보수 |
| P2 | `isVoid` AST 레벨 매칭으로 개선 | 중 | 정확성 |
| P2 | `Foundation` 의존성 문서화 | 하 | 문서화 |
| P3 | `JSONDecoder` 공유 인스턴스 최적화 | 하 | 성능 |
| P3 | `_ = args` / `_ = data` 패턴 개선 | 중 | 코드 품질 |
