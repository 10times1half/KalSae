import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

/// `SwiftSyntaxMacrosTestSupport.assertMacroExpansion`을 swift-testing 환경에
/// 맞게 감싼 헬퍼. 기본 구현은 `XCTFail`로 실패를 보고하지만, swift-testing의
/// `@Test`/`@Suite`에서는 XCTFail이 실패로 연결되지 않아 단언이 사실상 무시된다.
/// 이 함수는 `failureHandler`로 `Issue.record(...)`를 호출해 실패를 정상적으로
/// swift-testing 결과에 반영한다.
func expectMacroExpansion(
    _ originalSource: String,
    expandedSource expectedExpandedSource: String,
    diagnostics: [DiagnosticSpec] = [],
    macros: [String: Macro.Type],
    applyFixIts: [String]? = nil,
    fixedSource expectedFixedSource: String? = nil,
    testModuleName: String = "TestModule",
    testFileName: String = "test.swift",
    indentationWidth: Trivia = .spaces(4),
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) {
    let macroSpecs = macros.mapValues { MacroSpec(type: $0) }
    SwiftSyntaxMacrosGenericTestSupport.assertMacroExpansion(
        originalSource,
        expandedSource: expectedExpandedSource,
        diagnostics: diagnostics,
        macroSpecs: macroSpecs,
        applyFixIts: applyFixIts,
        fixedSource: expectedFixedSource,
        testModuleName: testModuleName,
        testFileName: testFileName,
        indentationWidth: indentationWidth,
        failureHandler: { failure in
            let location = Testing.SourceLocation(
                fileID: sourceLocation.fileID,
                filePath: sourceLocation.fileID,
                line: Int(failure.location.line),
                column: Int(failure.location.column))
            Issue.record(Comment(rawValue: failure.message), sourceLocation: location)
        }
    )
}
