import SwiftSyntax
import SwiftParser
public import Foundation

/// Generates TypeScript bindings from Swift source files containing
/// `@KSCommand`-annotated functions and the Codable types they reference.
///
/// This is intentionally a pragmatic, parser-driven generator rather than
/// a SymbolGraph consumer: it works on raw `.swift` text without requiring
/// a successful build, which is the right trade-off for `kalsae generate`
/// inside a watch loop.
///
/// Implementation is split across:
///   - this file: entry point, options/report, source discovery
///   - `BindingsGenerator+Models.swift`: data model types
///   - `BindingsGenerator+Visitor.swift`: SwiftSyntax walker
///   - `BindingsGenerator+TypeMapper.swift`: Swift→TS type mapping
///   - `BindingsGenerator+Renderer.swift`: TypeScript emission
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

    /// Parses `opts.sources`, deduplicates type declarations across files
    /// (first-occurrence wins), sorts the result deterministically, and
    /// writes a TypeScript module to `opts.output`. Throws on I/O
    /// failure of the final write step; individual unreadable source
    /// files are skipped silently to keep the watch-loop UX usable.
    public static func run(_ opts: Options) throws -> Report {
        var commands: [Command] = []
        var typeDecls: [TypeDecl] = []
        var seenTypes = Set<String>()

        for url in opts.sources {
            let text: String
            do { text = try String(contentsOf: url, encoding: .utf8) }
            catch { continue }
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
        try ts.write(to: opts.output, atomically: true, encoding: .utf8)

        return Report(commandCount: commands.count,
                      typeCount: typeDecls.count,
                      outputPath: opts.output.path)
    }

    /// Recursively enumerates `*.swift` files under `root`, skipping
    /// `.build`, `Tests`, `node_modules`, and hidden directories.
    public static func discoverSwiftFiles(under root: URL) -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default
        guard let it = fm.enumerator(at: root,
                                     includingPropertiesForKeys: [.isDirectoryKey],
                                     options: [.skipsHiddenFiles]) else { return [] }
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
