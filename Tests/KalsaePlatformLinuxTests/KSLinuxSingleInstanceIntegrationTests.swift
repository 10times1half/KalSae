#if os(Linux)
    import Testing
    import Foundation
    @testable import KalsaePlatformLinux

    private final class KSRelayStore: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [[String]] = []

        func append(_ args: [String]) {
            lock.lock()
            entries.append(args)
            lock.unlock()
        }

        func snapshot() -> [[String]] {
            lock.lock()
            let copy = entries
            lock.unlock()
            return copy
        }
    }

    @Suite("KSLinuxSingleInstance — integration contract", .serialized)
    struct KSLinuxSingleInstanceIntegrationTests {

        @Test("acquire returns primary for first instance")
        func acquireReturnsPrimaryForFirstInstance() {
            let identifier =
                "dev.kalsae.test.single.primary.\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
            let store = KSRelayStore()

            let outcome = KSLinuxSingleInstance.acquire(identifier: identifier) { args in
                store.append(args)
            }

            switch outcome {
            case .primary:
                #expect(true)
            case .relayed:
                Issue.record("First acquire should be primary")
            }
        }

        @Test("second instance relays args to primary")
        func secondInstanceRelaysArgs() async {
            let identifier = "dev.kalsae.test.single.relay.\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
            let store = KSRelayStore()

            let first = KSLinuxSingleInstance.acquire(identifier: identifier) { args in
                store.append(args)
            }
            guard case .primary = first else {
                Issue.record("Initial acquire must be primary")
                return
            }

            let relayedArgs = ["kalsae-demo", "kalsae://open?id=42"]

            var secondOutcome: KSLinuxSingleInstance.Outcome = .primary
            for _ in 0..<10 {
                secondOutcome = KSLinuxSingleInstance.acquire(
                    identifier: identifier,
                    args: relayedArgs
                ) { _ in }
                if case .relayed = secondOutcome { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }

            switch secondOutcome {
            case .primary:
                Issue.record("Second acquire should relay to the existing primary")
                return
            case .relayed:
                #expect(true)
            }

            var delivered = false
            for _ in 0..<20 {
                let snapshot = store.snapshot()
                if snapshot.contains(where: { $0 == relayedArgs }) {
                    delivered = true
                    break
                }
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            #expect(
                delivered,
                "Primary instance should receive relayed args payload")
        }
    }
#endif
