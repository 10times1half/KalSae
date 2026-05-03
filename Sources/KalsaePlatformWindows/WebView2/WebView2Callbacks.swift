#if os(Windows)
    internal import WinSDK
    internal import CKalsaeWV2
    internal import KalsaeCore
    internal import Foundation

    // MARK: - Sendable pointer wrappers
    //
    // WebView2's opaque pointer types are not `Sendable`. All real uses are
    // pinned to the UI thread, so we only need `@unchecked Sendable` boxes
    // to cross the `@convention(c) ↔ @MainActor ↔ continuation` boundary.

    internal struct KSSendableEnv: @unchecked Sendable {
        let value: KSWV2Env
    }
    internal struct KSSendableController: @unchecked Sendable {
        let value: KSWV2Controller
    }
    internal struct KSSendableRaw: @unchecked Sendable {
        let value: UnsafeMutableRawPointer
    }
    internal struct KSSendableUTF16: @unchecked Sendable {
        let value: UnsafePointer<UInt16>
    }
    internal struct KSSendableOutData: @unchecked Sendable {
        let value: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>
    }
    internal struct KSSendableOutLen: @unchecked Sendable {
        let value: UnsafeMutablePointer<Int>
    }
    internal struct KSSendableOutWStr: @unchecked Sendable {
        let value: UnsafeMutablePointer<UnsafeMutablePointer<UInt16>?>
    }
    internal struct KSSendableUTF16PtrArray: @unchecked Sendable {
        let value: UnsafePointer<UnsafePointer<UInt16>?>
    }

    // MARK: - Retain boxes for handlers
    //
    // These travel across `@convention(c)` callbacks and need a stable
    // identity that the C side can hold a `void*` to. Each box is retained
    // when registered with the C shim and released when the host disposes
    // or replaces the corresponding handler.

    @MainActor
    internal final class MessageHandlerBox {
        let handler: @MainActor (String) -> Void
        init(handler: @MainActor @escaping (String) -> Void) {
            self.handler = handler
        }
    }

    @MainActor
    internal final class ResourceHandlerBox {
        let resolver: KSAssetResolver
        let csp: String
        let hostPrefix: String
        init(resolver: KSAssetResolver, csp: String, hostPrefix: String) {
            self.resolver = resolver
            self.csp = csp
            self.hostPrefix = hostPrefix
        }
    }

    @MainActor
    internal final class DropTargetBox {
        let handler: @MainActor (WebView2Host.DropEventKind, Int32, Int32, [String]) -> Bool
        init(
            handler: @MainActor @escaping (WebView2Host.DropEventKind, Int32, Int32, [String]) -> Bool
        ) {
            self.handler = handler
        }
    }

    @MainActor
    internal final class NewWindowHandlerBox {
        let handler: @MainActor (_ uri: String) -> Bool  // returns true = allow
        init(handler: @MainActor @escaping (_ uri: String) -> Bool) {
            self.handler = handler
        }
    }

    @MainActor
    internal final class PermissionHandlerBox {
        // returns: 0=deny, 1=allow, 2=default
        let handler: @MainActor (_ uri: String, _ kind: Int32) -> Int32
        init(handler: @MainActor @escaping (_ uri: String, _ kind: Int32) -> Int32) {
            self.handler = handler
        }
    }

    @MainActor
    internal final class DownloadHandlerBox {
        // returns: 0=allow, 1=cancel
        let handler: @MainActor (_ url: String, _ mime: String) -> Int32
        init(handler: @MainActor @escaping (_ url: String, _ mime: String) -> Int32) {
            self.handler = handler
        }
    }

    @MainActor
    internal final class ServerCertHandlerBox {
        // returns: 0=cancel(deny-secure), 1=allow
        let handler: @MainActor () -> Int32
        init(handler: @MainActor @escaping () -> Int32) {
            self.handler = handler
        }
    }

    @MainActor
    internal final class BasicAuthHandlerBox {
        // returns: 0=cancel, 1=allow(OS 기본 처리)
        let handler: @MainActor (_ uri: String, _ challenge: String) -> Int32
        init(handler: @MainActor @escaping (_ uri: String, _ challenge: String) -> Int32) {
            self.handler = handler
        }
    }

    @MainActor
    internal final class ClientCertHandlerBox {
        // returns: 0=cancel, 1=allow(OS 선택기)
        let handler: @MainActor (_ host: String) -> Int32
        init(handler: @MainActor @escaping (_ host: String) -> Int32) {
            self.handler = handler
        }
    }

    // MARK: - Callback dispatch
    //
    // Every entry point here is invoked from a `@convention(c)` thunk in
    // the C shim. They run on the WebView2 UI thread, which is also the
    // main actor; we use `MainActor.assumeIsolated` rather than hopping
    // through the executor so resource-request callbacks remain synchronous.

    internal enum WebView2Callbacks {
        static func receiveEnv(
            user: UnsafeMutableRawPointer?, hr: Int32, env: KSWV2Env?
        ) {
            guard let user else { return }
            let userBox = KSSendableRaw(value: user)
            let envBox = env.map { KSSendableEnv(value: $0) }
            MainActor.assumeIsolated {
                let host = Unmanaged<WebView2Host>.fromOpaque(userBox.value)
                    .takeUnretainedValue()
                host.fulfillEnv(hr: hr, env: envBox?.value)
            }
        }

        static func receiveController(
            user: UnsafeMutableRawPointer?, hr: Int32, ctrl: KSWV2Controller?
        ) {
            guard let user else { return }
            let userBox = KSSendableRaw(value: user)
            let ctrlBox = ctrl.map { KSSendableController(value: $0) }
            MainActor.assumeIsolated {
                let host = Unmanaged<WebView2Host>.fromOpaque(userBox.value)
                    .takeUnretainedValue()
                host.fulfillController(hr: hr, ctrl: ctrlBox?.value)
            }
        }

        static func dispatchMessage(
            user: UnsafeMutableRawPointer?, msg: UnsafePointer<UInt16>?
        ) {
            guard let user, let msg else { return }
            let userBox = KSSendableRaw(value: user)
            let msgBox = KSSendableUTF16(value: msg)
            MainActor.assumeIsolated {
                let text = msgBox.value.toString()
                let box = Unmanaged<MessageHandlerBox>.fromOpaque(userBox.value)
                    .takeUnretainedValue()
                box.handler(text)
            }
        }

        /// Synchronous resource-request dispatch. Runs on the WebView2 UI
        /// thread (main actor), so we `assumeIsolated` to reach the resolver
        /// and allocate output buffers through the C shim (so `free()` in
        /// `KSWV2.cpp` is CRT-compatible).
        static func dispatchResource(
            user: UnsafeMutableRawPointer?,
            uri: UnsafePointer<UInt16>?,
            outData: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
            outLen: UnsafeMutablePointer<Int>?,
            outCT: UnsafeMutablePointer<UnsafeMutablePointer<UInt16>?>?,
            outCSP: UnsafeMutablePointer<UnsafeMutablePointer<UInt16>?>?
        ) -> Int32 {
            guard let user, let uri, let outData, let outLen else { return 1 }
            let userBox = KSSendableRaw(value: user)
            let uriBox = KSSendableUTF16(value: uri)
            let outDataBox = KSSendableOutData(value: outData)
            let outLenBox = KSSendableOutLen(value: outLen)
            let outCTBox = outCT.map { KSSendableOutWStr(value: $0) }
            let outCSPBox = outCSP.map { KSSendableOutWStr(value: $0) }
            return MainActor.assumeIsolated {
                let box = Unmanaged<ResourceHandlerBox>.fromOpaque(userBox.value)
                    .takeUnretainedValue()
                let uriString = uriBox.value.toString()
                guard uriString.hasPrefix(box.hostPrefix) else { return Int32(1) }
                var path = String(uriString.dropFirst(box.hostPrefix.count))
                if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
                if let h = path.firstIndex(of: "#") { path = String(path[..<h]) }
                if path.isEmpty { path = "/" }

                let asset: KSAssetResolver.Asset
                do {
                    asset = try box.resolver.resolve(path: path)
                } catch {
                    return Int32(1)
                }

                let count = asset.data.count
                guard let rawBuf = KSWV2_Alloc(count) else { return Int32(1) }
                asset.data.withUnsafeBytes { raw in
                    if let src = raw.baseAddress, count > 0 {
                        rawBuf.copyMemory(from: src, byteCount: count)
                    }
                }
                outDataBox.value.pointee =
                    rawBuf.assumingMemoryBound(to: UInt8.self)
                outLenBox.value.pointee = count

                if let outCTBox {
                    outCTBox.value.pointee = wcsdupShim(asset.mimeType)
                }
                if let outCSPBox, !box.csp.isEmpty {
                    outCSPBox.value.pointee = wcsdupShim(box.csp)
                }
                return Int32(0)
            }
        }

        /// Drop event dispatch (synchronous, on the OLE drop manager thread
        /// — which is the UI thread on STA). Decodes the C `wchar_t*[]` into
        /// Swift strings before hopping into the box's handler.
        static func dispatchDrop(
            user: UnsafeMutableRawPointer?,
            kind: Int32,
            x: Int32, y: Int32,
            paths: UnsafePointer<UnsafePointer<UInt16>?>?,
            count: Int32
        ) -> Int32 {
            guard let user else { return 1 }
            let userBox = KSSendableRaw(value: user)
            var collected: [String] = []
            if let paths, count > 0 {
                for i in 0..<Int(count) {
                    if let p = paths[i] {
                        collected.append(p.toString())
                    }
                }
            }
            let pathsCopy = collected
            return MainActor.assumeIsolated {
                let box = Unmanaged<DropTargetBox>
                    .fromOpaque(userBox.value).takeUnretainedValue()
                let evt: WebView2Host.DropEventKind =
                    WebView2Host.DropEventKind(rawValue: kind) ?? .leave
                return box.handler(evt, x, y, pathsCopy) ? Int32(0) : Int32(1)
            }
        }

        static func dispatchNewWindow(
            user: UnsafeMutableRawPointer?,
            uri: UnsafePointer<UInt16>?
        ) -> Int32 {
            guard let user else { return 0 }
            let userBox = KSSendableRaw(value: user)
            let uriStr = uri.map { $0.toString() } ?? ""
            return MainActor.assumeIsolated {
                let box = Unmanaged<NewWindowHandlerBox>
                    .fromOpaque(userBox.value).takeUnretainedValue()
                return box.handler(uriStr) ? Int32(1) : Int32(0)
            }
        }

        static func dispatchPermission(
            user: UnsafeMutableRawPointer?,
            uri: UnsafePointer<UInt16>?,
            kind: Int32
        ) -> Int32 {
            guard let user else { return 0 }
            let userBox = KSSendableRaw(value: user)
            let uriStr = uri.map { $0.toString() } ?? ""
            return MainActor.assumeIsolated {
                let box = Unmanaged<PermissionHandlerBox>
                    .fromOpaque(userBox.value).takeUnretainedValue()
                return box.handler(uriStr, kind)
            }
        }

        static func dispatchDownload(
            user: UnsafeMutableRawPointer?,
            url: UnsafePointer<UInt16>?,
            mime: UnsafePointer<UInt16>?
        ) -> Int32 {
            guard let user else { return 0 }
            let userBox = KSSendableRaw(value: user)
            let urlStr = url.map { $0.toString() } ?? ""
            let mimeStr = mime.map { $0.toString() } ?? ""
            return MainActor.assumeIsolated {
                let box = Unmanaged<DownloadHandlerBox>
                    .fromOpaque(userBox.value).takeUnretainedValue()
                return box.handler(urlStr, mimeStr)
            }
        }

        static func dispatchServerCertError(
            user: UnsafeMutableRawPointer?
        ) -> Int32 {
            guard let user else { return 0 }  // default: deny
            let userBox = KSSendableRaw(value: user)
            return MainActor.assumeIsolated {
                let box = Unmanaged<ServerCertHandlerBox>
                    .fromOpaque(userBox.value).takeUnretainedValue()
                return box.handler()
            }
        }

        static func dispatchBasicAuth(
            user: UnsafeMutableRawPointer?,
            uri: UnsafePointer<UInt16>?,
            challenge: UnsafePointer<UInt16>?
        ) -> Int32 {
            guard let user else { return 0 }  // default: cancel
            let userBox = KSSendableRaw(value: user)
            let uriStr = uri.map { $0.toString() } ?? ""
            let challengeStr = challenge.map { $0.toString() } ?? ""
            return MainActor.assumeIsolated {
                let box = Unmanaged<BasicAuthHandlerBox>
                    .fromOpaque(userBox.value).takeUnretainedValue()
                return box.handler(uriStr, challengeStr)
            }
        }

        static func dispatchClientCert(
            user: UnsafeMutableRawPointer?,
            host: UnsafePointer<UInt16>?
        ) -> Int32 {
            guard let user else { return 0 }  // default: cancel
            let userBox = KSSendableRaw(value: user)
            let hostStr = host.map { $0.toString() } ?? ""
            return MainActor.assumeIsolated {
                let box = Unmanaged<ClientCertHandlerBox>
                    .fromOpaque(userBox.value).takeUnretainedValue()
                return box.handler(hostStr)
            }
        }

        /// Wide-char dup that matches `free()` on the C++ side via the
        /// allocator exported from `KSWV2.cpp`.
        private static func wcsdupShim(_ s: String) -> UnsafeMutablePointer<UInt16>? {
            let units = Array(s.utf16)
            return units.withUnsafeBufferPointer { buf -> UnsafeMutablePointer<UInt16>? in
                KSWV2_WcsDupCopy(buf.baseAddress, buf.count)
            }
        }

        /// Directory containing the running executable. Used to locate
        /// sibling files like `kalsae.runtime.json` and `webview2-runtime/`.
        internal static func executableDirectory() -> URL {
            var buf = [UInt16](repeating: 0, count: 1024)
            let n = buf.withUnsafeMutableBufferPointer { p in
                GetModuleFileNameW(nil, p.baseAddress, DWORD(p.count))
            }
            if n == 0 { return URL(fileURLWithPath: ".") }
            let path = buf.withUnsafeBufferPointer { bufPtr -> String in
                guard let base = bufPtr.baseAddress else { return "." }
                return base.toString()
            }
            return URL(fileURLWithPath: path).deletingLastPathComponent()
        }

        /// Best-effort identifier used to namespace the WebView2 user-data
        /// folder when no explicit override is supplied. Reads from the
        /// runtime policy file's sibling fields when present, falling back
        /// to the executable's base name.
        internal static func appIdentifier() -> String {
            let dir = executableDirectory()
            let url = dir.appendingPathComponent("kalsae.runtime.json")
            if let data = try? Data(contentsOf: url),
                let obj = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
                let id = obj["identifier"] as? String,
                !id.isEmpty
            {
                return id
            }
            var buf = [UInt16](repeating: 0, count: 1024)
            let n = buf.withUnsafeMutableBufferPointer { p in
                GetModuleFileNameW(nil, p.baseAddress, DWORD(p.count))
            }
            if n == 0 { return "Kalsae" }
            let exe = URL(fileURLWithPath: buf.withUnsafeBufferPointer { bufPtr -> String in
                guard let base = bufPtr.baseAddress else { return "." }
                return base.toString()
            })
            return exe.deletingPathExtension().lastPathComponent
        }
    }

    // MARK: - KSError convenience

    extension KSError {
        internal static func webview2Failure(
            _ what: String, hr: Int32, code: KSError.Code
        ) -> KSError {
            KSError(
                code: code,
                message: "\(what) failed (HRESULT=0x\(String(UInt32(bitPattern: hr), radix: 16, uppercase: true)))",
                data: .int(Int(hr)))
        }
    }
#endif
