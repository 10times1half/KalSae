#if os(Linux)
    internal import CKalsaeGtk
    internal import Logging
    public import KalsaeCore
    public import Foundation

    /// Linux implementation of KSWindowBackend for the current GTK host model.
    ///
    /// Phase 1 scope: supports the lifecycle/lookup operations needed by
    /// KSPlatform.run() and built-in window commands. Advanced state and
    /// geometry operations continue to use protocol defaults that throw
    /// unsupportedPlatform until the dedicated GTK window backend lands.
    public struct KSLinuxWindowBackend: KSWindowBackend, Sendable {
        public init() {}

        @MainActor
        internal func registerMainWindow(label: String, host: GtkWebViewHost) -> KSWindowHandle {
            KSLinuxHandleRegistry.shared.register(label: label, host: host)
        }

        public func create(_ config: KSWindowConfig) async throws(KSError) -> KSWindowHandle {
            let result: Result<KSWindowHandle, KSError> = await MainActor.run {
                let appId = "app.Kalsae.\(config.label)"
                let host = GtkWebViewHost(
                    appId: appId,
                    title: config.title,
                    width: config.width,
                    height: config.height)
                return .success(KSLinuxHandleRegistry.shared.register(label: config.label, host: host))
            }
            switch result {
            case .success(let handle):
                return handle
            case .failure(let error):
                throw error
            }
        }

        public func close(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { entry in
                entry.host.quit()
                KSLinuxHandleRegistry.shared.unregister(entry.handle)
            }
        }

        public func show(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.host.show() }
        }

        public func hide(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.host.hide() }
        }

        public func focus(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.host.focus() }
        }

        public func setTitle(_ handle: KSWindowHandle, title: String) async throws(KSError) {
            try await runMain(handle) { $0.host.setTitle(title) }
        }

        public func setSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError) {
            try await runMain(handle) { $0.host.setSize(width: width, height: height) }
        }

        public func setPosition(_ handle: KSWindowHandle, x: Int, y: Int) async throws(KSError) {
            try await runMain(handle) { $0.host.setPosition(x: x, y: y) }
        }

        public func getPosition(_ handle: KSWindowHandle) async throws(KSError) -> KSPoint {
            let entry = try await resolve(handle)
            return await MainActor.run {
                entry.host.getPosition() ?? KSPoint(x: 0, y: 0)
            }
        }

        public func setMaxSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError) {
            try await runMain(handle) { $0.host.setMaxSize(width: width, height: height) }
        }

        public func center(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.host.centerOnScreen() }
        }

        public func webView(for handle: KSWindowHandle) async throws(KSError) -> any KSWebViewBackend {
            let entry = try await resolve(handle)
            return entry.host
        }

        public func all() async -> [KSWindowHandle] {
            await MainActor.run {
                KSLinuxHandleRegistry.shared.allHandles()
            }
        }

        public func find(label: String) async -> KSWindowHandle? {
            await MainActor.run {
                KSLinuxHandleRegistry.shared.handle(for: label)
            }
        }

        public func reload(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.host.reload() }
        }

        public func minimize(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.host.minimize() }
        }

        public func maximize(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.host.maximize() }
        }

        public func restore(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.host.unmaximize() }
        }

        public func toggleMaximize(_ handle: KSWindowHandle) async throws(KSError) {
            let maximized = try await isMaximized(handle)
            if maximized {
                try await restore(handle)
            } else {
                try await maximize(handle)
            }
        }

        public func isMaximized(_ handle: KSWindowHandle) async throws(KSError) -> Bool {
            let entry = try await resolve(handle)
            return await MainActor.run {
                entry.host.isMaximized()
            }
        }

        public func isMinimized(_ handle: KSWindowHandle) async throws(KSError) -> Bool {
            let entry = try await resolve(handle)
            return await MainActor.run {
                entry.host.isMinimized()
            }
        }

        public func isFullscreen(_ handle: KSWindowHandle) async throws(KSError) -> Bool {
            let entry = try await resolve(handle)
            return await MainActor.run {
                entry.host.isFullscreen()
            }
        }

        public func setFullscreen(_ handle: KSWindowHandle, enabled: Bool) async throws(KSError) {
            try await runMain(handle) { $0.host.setFullscreen(enabled) }
        }

        public func getSize(_ handle: KSWindowHandle) async throws(KSError) -> KSSize {
            let entry = try await resolve(handle)
            return await MainActor.run {
                entry.host.getSize() ?? KSSize(width: 0, height: 0)
            }
        }

        public func setMinSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError) {
            try await runMain(handle) { $0.host.setMinSize(width: width, height: height) }
        }

        public func setTheme(_ handle: KSWindowHandle, theme: KSWindowTheme) async throws(KSError) {
            try await runMain(handle) { $0.host.setTheme(theme) }
        }

        public func setBackgroundColor(_ handle: KSWindowHandle, rgba: UInt32) async throws(KSError) {
            let r = Float((rgba >> 24) & 0xFF) / 255.0
            let g = Float((rgba >> 16) & 0xFF) / 255.0
            let b = Float((rgba >> 8) & 0xFF) / 255.0
            let a = Float(rgba & 0xFF) / 255.0
            try await runMain(handle) { $0.host.setBackgroundColor(r: r, g: g, b: b, a: a) }
        }

        public func setCloseInterceptor(_ handle: KSWindowHandle, enabled: Bool) async throws(KSError) {
            try await runMain(handle) { $0.host.setCloseInterceptor(enabled) }
        }

        public func setAlwaysOnTop(_ handle: KSWindowHandle, enabled: Bool) async throws(KSError) {
            try await runMain(handle) { $0.host.setKeepAbove(enabled) }
        }

        public func setZoomFactor(_ handle: KSWindowHandle, factor: Double) async throws(KSError) {
            try await runMain(handle) { $0.host.setZoomLevel(factor) }
        }

        public func getZoomFactor(_ handle: KSWindowHandle) async throws(KSError) -> Double {
            let entry = try await resolve(handle)
            return await MainActor.run { entry.host.getZoomLevel() }
        }

        public func showPrintUI(_ handle: KSWindowHandle, systemDialog: Bool) async throws(KSError) {
            try await runMain(handle) { $0.host.showPrintUI(systemDialog: systemDialog) }
        }

        public func capturePreview(_ handle: KSWindowHandle, format: Int32) async throws(KSError) -> Data {
            let entry = try await resolve(handle)
            do {
                return try await entry.host.capturePreview(format: format)
            } catch {
                throw (error as? KSError)
                    ?? KSError(code: .internal, message: "capturePreview: \(error)")
            }
        }

        public func listDisplays() async throws(KSError) -> [KSDisplayInfo] {
            let result: Result<[KSDisplayInfo], KSError> = await MainActor.run {
                let count = Int(ks_gtk_host_get_display_count(nil))
                guard count > 0 else {
                    return .failure(
                        KSError(
                            code: .unsupportedPlatform,
                            message: "No displays available on Linux backend"))
                }
                var displays: [KSDisplayInfo] = []
                displays.reserveCapacity(count)
                for i in 0..<count {
                    if let info = Self.readDisplayInfo(hostPtr: nil, index: i) {
                        displays.append(info)
                    }
                }
                guard !displays.isEmpty else {
                    return .failure(
                        KSError(
                            code: .unsupportedPlatform,
                            message: "Failed to collect Linux display information"))
                }
                return .success(displays)
            }
            switch result {
            case .success(let displays):
                return displays
            case .failure(let error):
                throw error
            }
        }

        public func currentDisplay(_ handle: KSWindowHandle) async throws(KSError) -> KSDisplayInfo {
            let entry = try await resolve(handle)
            let result: Result<KSDisplayInfo, KSError> = await MainActor.run {
                let index = entry.host.currentDisplayIndex()
                guard index >= 0, let info = Self.readDisplayInfo(hostPtr: entry.host.hostPtr, index: index) else {
                    return .failure(
                        KSError(
                            code: .unsupportedPlatform,
                            message: "Could not resolve current display for '\(handle.label)'"))
                }
                return .success(info)
            }
            switch result {
            case .success(let info):
                return info
            case .failure(let error):
                throw error
            }
        }

        public func startDrag(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.host.startDrag() }
        }

        public func setTaskbarProgress(
            _ handle: KSWindowHandle,
            progress: KSTaskbarProgress
        ) async throws(KSError) {
            _ = handle
            _ = progress
            Self.warnTaskbarProgressUnsupportedOnce()
        }

        public func setOverlayIcon(
            _ handle: KSWindowHandle,
            iconPath: String?,
            description: String?
        ) async throws(KSError) {
            _ = handle
            _ = iconPath
            _ = description
            Self.warnOverlayUnsupportedOnce()
        }

        private func runMain(
            _ handle: KSWindowHandle,
            _ body: @MainActor @Sendable (KSLinuxHandleRegistry.Entry) throws(KSError) -> Void
        ) async throws(KSError) {
            let result: Result<Void, KSError> = await MainActor.run {
                do {
                    guard let entry = KSLinuxHandleRegistry.shared.entry(for: handle) else {
                        throw KSError(
                            code: .windowCreationFailed,
                            message: "No GTK window registered for label '\(handle.label)'")
                    }
                    try body(entry)
                    return .success(())
                } catch {
                    return .failure(
                        error as? KSError
                            ?? KSError(code: .internal, message: "\(error)"))
                }
            }
            switch result {
            case .success:
                return
            case .failure(let error):
                throw error
            }
        }

        private func resolve(_ handle: KSWindowHandle) async throws(KSError) -> KSLinuxHandleRegistry.Entry {
            let result: Result<KSLinuxHandleRegistry.Entry, KSError> = await MainActor.run {
                guard let entry = KSLinuxHandleRegistry.shared.entry(for: handle) else {
                    return .failure(
                        KSError(
                            code: .windowCreationFailed,
                            message: "No GTK window registered for label '\(handle.label)'"))
                }
                return .success(entry)
            }
            switch result {
            case .success(let entry):
                return entry
            case .failure(let error):
                throw error
            }
        }

        @MainActor
        private static func readDisplayInfo(hostPtr: OpaquePointer?, index: Int) -> KSDisplayInfo? {
            var idBuf = [CChar](repeating: 0, count: 128)
            var nameBuf = [CChar](repeating: 0, count: 256)
            var x: Int32 = 0
            var y: Int32 = 0
            var width: Int32 = 0
            var height: Int32 = 0
            var workX: Int32 = 0
            var workY: Int32 = 0
            var workWidth: Int32 = 0
            var workHeight: Int32 = 0
            var scale: Double = 1.0
            var refreshRate: Int32 = 0
            var isPrimary: Int32 = 0

            let ok = idBuf.withUnsafeMutableBufferPointer { idPtr in
                nameBuf.withUnsafeMutableBufferPointer { namePtr in
                    ks_gtk_host_get_display_info(
                        hostPtr,
                        Int32(index),
                        idPtr.baseAddress,
                        idBuf.count,
                        namePtr.baseAddress,
                        nameBuf.count,
                        &x,
                        &y,
                        &width,
                        &height,
                        &workX,
                        &workY,
                        &workWidth,
                        &workHeight,
                        &scale,
                        &refreshRate,
                        &isPrimary)
                }
            }
            guard ok != 0 else { return nil }
            return KSDisplayInfo(
                id: String(cString: idBuf),
                name: String(cString: nameBuf),
                bounds: KSRect(x: Int(x), y: Int(y), width: Int(width), height: Int(height)),
                workArea: KSRect(
                    x: Int(workX), y: Int(workY), width: Int(workWidth), height: Int(workHeight)),
                scaleFactor: scale,
                refreshRate: refreshRate > 0 ? Int(refreshRate) : nil,
                isPrimary: isPrimary != 0)
        }

        nonisolated(unsafe) private static var didWarnTaskbarProgress = false
        nonisolated(unsafe) private static var didWarnOverlay = false
        nonisolated(unsafe) private static let warnLock = NSLock()

        private static func warnTaskbarProgressUnsupportedOnce() {
            warnLock.lock()
            defer { warnLock.unlock() }
            guard !didWarnTaskbarProgress else { return }
            didWarnTaskbarProgress = true
            KSLog.logger("platform.linux.window").warning(
                "setTaskbarProgress is a no-op on Linux (Wails/Tauri parity policy).")
        }

        private static func warnOverlayUnsupportedOnce() {
            warnLock.lock()
            defer { warnLock.unlock() }
            guard !didWarnOverlay else { return }
            didWarnOverlay = true
            KSLog.logger("platform.linux.window").warning(
                "setOverlayIcon is unsupported on Linux and remains a no-op (Wails/Tauri parity policy).")
        }
    }
#endif
