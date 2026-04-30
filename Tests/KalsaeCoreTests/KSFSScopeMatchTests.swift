import Testing
import Foundation
@testable import KalsaeCore

@Suite("KSFSScope+Match")
struct KSFSScopeMatchTests {
    private func ctx(app: String = "/app", home: String = "/home/u") -> KSFSScope.ExpansionContext {
        .init(app: app, home: home, docs: "/home/u/Documents", temp: "/tmp")
    }

    @Test("Single * does not cross path separator")
    func starNoSlash() {
        #expect(KSFSScope.glob(pattern: "/a/*", matches: "/a/b"))
        #expect(!KSFSScope.glob(pattern: "/a/*", matches: "/a/b/c"))
    }

    @Test("Double ** crosses any number of separators")
    func doubleStarCrosses() {
        #expect(KSFSScope.glob(pattern: "/a/**", matches: "/a/b/c/d"))
        #expect(KSFSScope.glob(pattern: "/a/**", matches: "/a/b"))
        #expect(!KSFSScope.glob(pattern: "/a/**", matches: "/x/y"))
    }

    @Test("? matches single non-slash")
    func questionMark() {
        #expect(KSFSScope.glob(pattern: "/a/?", matches: "/a/b"))
        #expect(!KSFSScope.glob(pattern: "/a/?", matches: "/a/bc"))
        #expect(!KSFSScope.glob(pattern: "/a/?", matches: "/a/b/c"))
    }

    @Test("Placeholder expansion replaces $APP/$HOME/$DOCS/$TEMP")
    func expansion() {
        let c = ctx(app: "/install", home: "/home/u")
        #expect(KSFSScope.expand("$APP/conf", in: c) == "/install/conf")
        #expect(KSFSScope.expand("$HOME/x", in: c) == "/home/u/x")
        #expect(KSFSScope.expand("$DOCS/y", in: c) == "/home/u/Documents/y")
        #expect(KSFSScope.expand("$TEMP/z", in: c) == "/tmp/z")
    }

    @Test("permits expands patterns and walks deny→allow")
    func permits() {
        let scope = KSFSScope(
            allow: ["$DOCS/kalsaeDemo/**"],
            deny: ["$DOCS/kalsaeDemo/secret/**"])
        let c = ctx()
        #expect(scope.permits(absolutePath: "/home/u/Documents/kalsaeDemo/foo.txt", in: c))
        #expect(scope.permits(absolutePath: "/home/u/Documents/kalsaeDemo/sub/dir/foo.txt", in: c))
        #expect(!scope.permits(absolutePath: "/home/u/Documents/kalsaeDemo/secret/passwords.txt", in: c))
        #expect(!scope.permits(absolutePath: "/home/u/Documents/other/foo.txt", in: c))
    }

    @Test("Empty allow denies every path")
    func emptyAllow() {
        let scope = KSFSScope()
        let c = ctx()
        #expect(!scope.permits(absolutePath: "/home/u/anything", in: c))
    }
}
