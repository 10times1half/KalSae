import Foundation

extension KSBuiltinCommands {
    /// `__ks.app.*`, `__ks.environment`, `__ks.log`를 등록한다 —
    /// 특정 도메인에 속하지 않는 포괄적인 명령 집합이다.
    static func registerAppCommands(
        into registry: KSCommandRegistry,
        quit: @escaping @Sendable () -> Void,
        platformName: String
    ) async {
        await register(registry, "__ks.app.quit") { _ throws(KSError) -> Empty in
            quit()
            return Empty()
        }
        await registerQuery(registry, "__ks.environment") { _ throws(KSError) -> Environment in
            Environment(
                os: kalsaeOSName(),
                arch: kalsaeArchName(),
                platform: platformName,
                osVersion: kalsaeOSVersionString(),
                locale: kalsaeSystemLocale(),
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                kalsaeVersion: KSVersion.current)
        }

        let webLog = KSLog.logger("web")
        await register(registry, "__ks.log") { (args: LogArg) throws(KSError) -> Empty in
            switch args.level {
            case "trace": webLog.trace("\(args.message)")
            case "debug": webLog.debug("\(args.message)")
            case "info": webLog.info("\(args.message)")
            case "warn": webLog.warning("\(args.message)")
            case "error": webLog.error("\(args.message)")
            default: webLog.info("\(args.message)")
            }
            return Empty()
        }
    }
}
