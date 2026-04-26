import Foundation

extension KSBuiltinCommands {
    /// Registers `__ks.window.*` handlers — minimize, maximize, restore,
    /// fullscreen, position/size queries and mutations, theme, etc.
    static func registerWindowCommands(
        into registry: KSCommandRegistry,
        windows: any KSWindowBackend,
        resolver: WindowResolver
    ) async {
        await register(registry, "__ks.window.minimize") { _ throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: nil)
            try await windows.minimize(h)
            return Empty()
        }
        await register(registry, "__ks.window.maximize") { _ throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: nil)
            try await windows.maximize(h)
            return Empty()
        }
        await register(registry, "__ks.window.restore") { _ throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: nil)
            try await windows.restore(h)
            return Empty()
        }
        await register(registry, "__ks.window.toggleMaximize") { _ throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: nil)
            try await windows.toggleMaximize(h)
            return Empty()
        }
        await registerQuery(registry, "__ks.window.isMinimized") { _ throws(KSError) -> Bool in
            let h = try await resolver.resolve(window: nil)
            return try await windows.isMinimized(h)
        }
        await registerQuery(registry, "__ks.window.isMaximized") { _ throws(KSError) -> Bool in
            let h = try await resolver.resolve(window: nil)
            return try await windows.isMaximized(h)
        }
        await registerQuery(registry, "__ks.window.isFullscreen") { _ throws(KSError) -> Bool in
            let h = try await resolver.resolve(window: nil)
            return try await windows.isFullscreen(h)
        }
        await register(registry, "__ks.window.setFullscreen") { (args: BoolArg) throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: args.window)
            try await windows.setFullscreen(h, enabled: args.enabled)
            return Empty()
        }
        await register(registry, "__ks.window.setAlwaysOnTop") { (args: BoolArg) throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: args.window)
            try await windows.setAlwaysOnTop(h, enabled: args.enabled)
            return Empty()
        }
        await register(registry, "__ks.window.center") { _ throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: nil)
            try await windows.center(h)
            return Empty()
        }
        await register(registry, "__ks.window.setPosition") { (args: PositionArg) throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: args.window)
            try await windows.setPosition(h, x: args.x, y: args.y)
            return Empty()
        }
        await registerQuery(registry, "__ks.window.getPosition") { _ throws(KSError) -> KSPoint in
            let h = try await resolver.resolve(window: nil)
            return try await windows.getPosition(h)
        }
        await registerQuery(registry, "__ks.window.getSize") { _ throws(KSError) -> KSSize in
            let h = try await resolver.resolve(window: nil)
            return try await windows.getSize(h)
        }
        await register(registry, "__ks.window.setSize") { (args: SizeArg) throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: args.window)
            try await windows.setSize(h, width: args.width, height: args.height)
            return Empty()
        }
        await register(registry, "__ks.window.setMinSize") { (args: SizeArg) throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: args.window)
            try await windows.setMinSize(h, width: args.width, height: args.height)
            return Empty()
        }
        await register(registry, "__ks.window.setMaxSize") { (args: SizeArg) throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: args.window)
            try await windows.setMaxSize(h, width: args.width, height: args.height)
            return Empty()
        }
        await register(registry, "__ks.window.setTitle") { (args: TitleArg) throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: args.window)
            try await windows.setTitle(h, title: args.title)
            return Empty()
        }
        await register(registry, "__ks.window.show") { _ throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: nil)
            try await windows.show(h)
            return Empty()
        }
        await register(registry, "__ks.window.hide") { _ throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: nil)
            try await windows.hide(h)
            return Empty()
        }
        await register(registry, "__ks.window.focus") { _ throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: nil)
            try await windows.focus(h)
            return Empty()
        }
        await register(registry, "__ks.window.close") { _ throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: nil)
            try await windows.close(h)
            return Empty()
        }
        await register(registry, "__ks.window.reload") { _ throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: nil)
            try await windows.reload(h)
            return Empty()
        }
        await register(registry, "__ks.window.setTheme") { (args: ThemeArg) throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: args.window)
            try await windows.setTheme(h, theme: args.theme)
            return Empty()
        }
    }
}
