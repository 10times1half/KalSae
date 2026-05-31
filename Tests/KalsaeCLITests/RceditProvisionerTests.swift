import Foundation
import Testing

@testable import KalsaeCLICore

@Suite("KSRceditProvisioner")
struct RceditProvisionerTests {

    #if os(Windows)
        @Test("default cache path ends with rcedit-x64.exe")
        func defaultCachePathLooksCorrect() {
            let path = KSRceditProvisioner.defaultCachePath()
            #expect(path != nil)
            #expect(path?.lastPathComponent.lowercased() == "rcedit-x64.exe")
        }
    #else
        @Test("non-Windows host is a no-op")
        func noOpOnNonWindows() throws {
            #expect(KSRceditProvisioner.defaultCachePath() == nil)
            #expect(KSRceditProvisioner.locate() == nil)
            let result = try KSRceditProvisioner.ensure(
                cwd: URL(fileURLWithPath: "/tmp"),
                autoFetch: false)
            #expect(result == nil)
        }
    #endif
}
