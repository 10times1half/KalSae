#if os(Android)
    import Foundation

    // RFC-007 Phase 4 — request-id ↔ continuation 매핑.
    //
    // Kotlin 호스트는 `AlertDialog` / `ActivityResultLauncher` 같은 비동기 UI
    // 결과를 즉시 반환할 수 없다. Swift 측은 다음 흐름을 사용한다:
    //
    //   1) `KSAndroidDialogBackend` 의 핸들러가 `register(...)` 로 요청 ID 를
    //      받고 continuation 을 등록한다.
    //   2) 등록된 JNI 훅(`_jniShowAlert` 등)을 호출하여 (requestId, optionsJSON)
    //      을 Kotlin 에 전달한다.
    //   3) 사용자가 응답하면 Kotlin 은
    //      `KalsaeJNI.onDialogResult(requestId, resultJson)` 을 호출하여
    //      Swift 의 `KS_android_on_dialog_result(...)` 진입점으로 결과를
    //      되돌린다.
    //   4) 진입점은 `deliver(_:json:)` 로 continuation 을 깨운다.
    //
    // 모든 상태 접근은 `lock` 으로 직렬화한다. `@unchecked Sendable` 은 actor
    // 사용 불가 (cdecl 진입점이 sync 컨텍스트에서 호출됨) 인 정당화된 경우다.

    final class KSAndroidJNIRegistry: @unchecked Sendable {
        static let shared = KSAndroidJNIRegistry()

        private let lock = NSLock()
        // Int32 만 사용하는 이유: Kotlin/JNI 측 시그니처가 `Int` (Java `int`,
        // 32 비트) 라서 Swift `Int32` 와 1:1 매핑된다.
        private var nextID: Int32 = 1
        private var pending: [Int32: (String) -> Void] = [:]

        private init() {}

        /// continuation 을 등록하고 발급된 요청 ID 를 반환한다.
        /// 이후 `deliver(_:json:)` 또는 `cancel(_:)` 가 호출되면 closure 는
        /// 단 한 번만 실행되고 맵에서 제거된다.
        func register(_ resume: @escaping (String) -> Void) -> Int32 {
            lock.lock()
            defer { lock.unlock() }
            let id = nextID
            // Int32.max 도달 시 1 로 wrap. 음수/0 은 invalid sentinel 로 사용.
            if nextID == Int32.max {
                nextID = 1
            } else {
                nextID &+= 1
            }
            pending[id] = resume
            return id
        }

        /// `KS_android_on_dialog_result` 가 호출되면 매칭되는 continuation 을
        /// 깨우고 맵에서 제거한다. 매칭 항목이 없으면 조용히 무시한다(중복/늦은
        /// 응답 방어).
        func deliver(_ id: Int32, json: String) {
            lock.lock()
            let resume = pending.removeValue(forKey: id)
            lock.unlock()
            resume?(json)
        }

        /// 등록 후 JNI 훅 호출에 실패한 경우 등 continuation 을 회수해야 할 때
        /// 사용한다. 매칭이 없으면 no-op.
        func cancel(_ id: Int32) {
            lock.lock()
            _ = pending.removeValue(forKey: id)
            lock.unlock()
        }

        #if DEBUG
            /// 단위 테스트 보조 — 현재 보류 중인 요청 수.
            var pendingCount: Int {
                lock.lock()
                defer { lock.unlock() }
                return pending.count
            }
        #endif
    }
#endif
