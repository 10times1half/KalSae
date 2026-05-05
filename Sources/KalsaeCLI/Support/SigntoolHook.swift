public import Foundation

/// `kalsae build --signtool-cmd` / `--nsis-signtool-cmd`에서 사용하는 외부
/// 코드사이닝 명령 실행 hook.
///
/// 사용자가 제공한 명령 템플릿에서 `{file}` 플레이스홀더를 대상 파일의 절대
/// 경로로 치환한다. 플레이스홀더가 없으면 명령 끝에 따옴표로 감싸 추가한다.
///
/// 예:
/// ```
/// --signtool-cmd "signtool sign /a /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 {file}"
/// --signtool-cmd "signtool sign /a"   // → 끝에 ` "<path>"` 자동 추가
/// ```
///
/// 실제 인증서/키 관리는 사용자가 책임지며, 이 hook은 단순 명령 실행기다.
public enum KSSigntoolHook {
    /// `{file}` 플레이스홀더를 치환한 최종 명령줄을 반환한다.
    public static func render(template: String, file: URL) -> String {
        let path = file.path
        if template.contains("{file}") {
            return template.replacingOccurrences(of: "{file}", with: "\"\(path)\"")
        }
        return "\(template) \"\(path)\""
    }

    /// 템플릿 명령을 호스트 셸을 통해 실행한다. 비-0 종료 코드는 throw.
    /// `dryrun == true`이면 명령만 출력하고 실행하지 않는다.
    public static func run(
        template: String, file: URL, label: String, dryrun: Bool
    ) throws {
        let cmd = render(template: template, file: file)
        print("✍️   \(label): \(cmd)")
        if dryrun {
            print("(--dryrun) skipping execution")
            return
        }
        try shell(commandLine: cmd)
    }
}
