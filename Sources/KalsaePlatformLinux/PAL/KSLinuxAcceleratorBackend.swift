#if os(Linux)
public import KalsaeCore

/// `KSAcceleratorBackend`의 Linux 스터브.
///
/// GTK4 윈도우 범위 단축키는 `GtkShortcutController`를 통해,
/// Wayland 전역 단축키는 `xdg-foreign` / `zwp_shortcuts`
/// 프로토콜 확장을 통해 연결할 수 있다. 전체 구현은 이후 단계에 산정된다.
/// 그 때까지 모든 메서드는 프로토콜 기본값 `.unsupportedPlatform` 에러를
/// 통해 폴백된다.
public final class KSLinuxAcceleratorBackend: KSAcceleratorBackend {
    public nonisolated init() {}
}
#endif
