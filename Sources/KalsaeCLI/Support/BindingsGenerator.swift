/// `@KSCommand`-연동 함수와 Codable 타입을 포함하는 Swift 소스 파일에서
/// TypeScript 바인딩을 생성한다.
///
/// SymbolGraph 소비자가 아닌 실용적인 파서 기반 생성기로 설계되어 있다.
/// 빌드 성공 없이 원시 `.swift` 텍스트를 작업하므로
/// `kalsae generate` 와치 루프 내에서 올바른 트레이드오프이다.
///
/// 구현은 다음 파일들로 분리되어 있다:
///   - 이 파일: 진입점, 옵션/리포트, 소스 검색
///   - `BindingsGenerator+Models.swift`: 데이터 모델 타입
///   - `BindingsGenerator+Visitor.swift`: SwiftSyntax 워커
///   - `BindingsGenerator+TypeMapper.swift`: Swift→TS 타입 매핑
///   - `BindingsGenerator+Renderer.swift`: TypeScript 발행
public import Foundation
import SwiftParser
import SwiftSyntax

public enum KSBindingsGenerator {
    public struct Options: Sendable {
        public var sources: [URL]
        public var output: URL
        public var moduleName: String
        public init(sources: [URL], output: URL, moduleName: String = "Kalsae") {
            self.sources = sources
            self.output = output
            self.moduleName = moduleName
        }
    }

    public struct Report: Sendable, CustomStringConvertible {
        public let commandCount: Int
        public let typeCount: Int
        public let outputPath: String
        public var description: String {
            "Generated \(commandCount) commands and \(typeCount) types → \(outputPath)"
        }
    }

    /// `opts.sources`를 파싱하고 파일 간 타입 선언을 중복 제거하고
    /// (첫 발견 우선), 결과를 결정적으로 정렬하고
    /// `opts.output`에 TypeScript 모듈을 쓴다. 최종 쓰기 I/O 실패 시만
    /// 에러를 던진다; 읽을 수 없는 개별 소스 파일은
    /// 와치 루프 UX를 유지하도록 조용히 건너된다.
    public static func run(_ opts: Options) throws -> Report {
        var commands: [Command] = []
        var typeDecls: [TypeDecl] = []
        var seenTypes = Set<String>()

        for url in opts.sources {
            let text: String
            do { text = try String(contentsOf: url, encoding: .utf8) } catch { continue }
            let tree = Parser.parse(source: text)
            let v = Visitor()
            v.walk(tree)
            commands.append(contentsOf: v.commands)
            for t in v.types where !seenTypes.contains(t.name) {
                seenTypes.insert(t.name)
                typeDecls.append(t)
            }
        }

        commands.sort { $0.commandName < $1.commandName }
        typeDecls.sort { $0.name < $1.name }

        let ts = render(commands: commands, types: typeDecls, module: opts.moduleName)
        try FileManager.default.createDirectory(
            at: opts.output.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try ts.write(to: opts.output, atomically: false, encoding: .utf8)

        return Report(
            commandCount: commands.count,
            typeCount: typeDecls.count,
            outputPath: opts.output.path)
    }

    /// `root` 하위의 `*.swift` 파일을 재귀적으로 열거하며
    /// `.build`, `Tests`, `node_modules`, 히든 디렉터리는 건너된다.
    public static func discoverSwiftFiles(under root: URL) -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default
        guard
            let it = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])
        else { return [] }
        for case let url as URL in it {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                let n = url.lastPathComponent
                if n == ".build" || n == "Tests" || n == "node_modules" {
                    it.skipDescendants()
                }
                continue
            }
            if url.pathExtension == "swift" { out.append(url) }
        }
        return out
    }
}
