# RFC-002 — `kalsae build` Windows 빌드 속도 개선

| 항목 | 내용 |
|------|------|
| 상태 | 승인 (Accepted) |
| 날짜 | 2026-05-08 |
| 영향 범위 | `KalsaeCLI` — `Packager`, `BuildCommand`, `WebView2Provisioner` |
| 관련 | `kalsae build` 파이프라인, `KSResourceSyncManager` |

---

## 1. 동기(Motivation)

`kalsae build`로 빌드한 `kalsae.exe`를 Windows에서 실행할 때, 반복 빌드 속도가
체감상 느리다. `--timings` 분석 결과 다음 세 지점이 개선 가능한 병목으로 확인되었다:

1. **Packager가 매 빌드마다 output 디렉터리를 전체 삭제→재생성**하여, frontend dist
   100+ 파일을 변경 유무와 무관하게 매번 복사한다.
2. **`swift build` 병렬도를 사용자가 조정할 수 없어**, Windows Defender 실시간 스캔과
   I/O 경합 시 최적값을 찾을 수 없다.
3. **`stageLoaderDLL`이 `.build/` 전체를 순회**하여 불필요한 `fileExists` 호출이 발생한다.

---

## 2. 결정 사항

| 항목 | 결정 |
|------|------|
| 증분 복사 범위 | output 디렉터리 삭제 제거 + 전체 증분화 |
| `--jobs` 플래그 | `BuildCommand`에만 추가 (`DevCommand` 제외) |
| `stageLoaderDLL` | known triple 직접 검사로 교체 |
| macOS Packager | 이번 범위에서 제외 (속도 이슈 미보고) |
| `DevCommand` | 이번 범위에서 제외 |

---

## 3. 변경 상세

### 3.1 Packager 증분화 (Phase A)

수정 파일: `Sources/KalsaeCLI/Support/Packager.swift`

#### (a) output 디렉터리 전체 삭제 제거

```swift
// 변경 전 — run() 상단:
if fm.fileExists(atPath: opts.output.path) {
    try fm.removeItem(at: opts.output)          // ← 매번 전체 삭제
}
try fm.createDirectory(at: opts.output, withIntermediateDirectories: true)

// 변경 후:
try fm.createDirectory(at: opts.output, withIntermediateDirectories: true)
```

#### (b) 개별 파일 복사를 안전한 덮어쓰기로 전환

`safeCopy(from:to:fm:)` 헬퍼를 추가한다. 대상이 이미 존재하면 삭제 후 복사한다:

```swift
private static func safeCopy(from src: URL, to dst: URL, fm: FileManager = .default) throws {
    if fm.fileExists(atPath: dst.path) {
        try fm.removeItem(at: dst)
    }
    try fm.copyItem(at: src, to: dst)
}
```

적용 대상:
- step 1: exe 복사 (`fm.copyItem(at: opts.executablePath, to: dstExe)`)
- step 3: Kalsae.json 복사 (`fm.copyItem(at: opts.configPath, to: dstConfig)`)
- step 5: icon 복사 (`fm.copyItem(at: icon, to: dst)`)
- step 6a: bootstrapper 복사 (`copyBootstrapper()` 내부)

변경 불요:
- manifest / runtime json — `String.write` / `Data.write`는 이미 안전하게 덮어씀
- WebView2Loader.dll — `copyLoaderDLL()` 내부에 이미 삭제 확인 로직 존재
- fixed runtime — `copyTree()` 내부에서 이미 삭제 처리

#### (c) Resources/ 트리 — `copyTree` → `KSResourceSyncManager.sync` 교체

```swift
// 변경 전:
try copyTree(from: dist, to: dstResources)

// 변경 후:
if fm.fileExists(atPath: dstResources.path) {
    _ = try KSResourceSyncManager.sync(
        distURL: dist,
        resourcesURL: dstResources,
        preserved: [],
        fm: fm)
} else {
    try fm.copyItem(at: dist, to: dstResources)
}
```

- `preserved: []` — 패키저 output에는 보존 대상 파일이 없음
- 첫 빌드(dstResources 미존재)는 기존 전체 복사로 폴백
- strip 로직은 sync 이후 기존대로 적용 (변경 없음)

기존 `KSResourceSyncManager.sync()`의 3-pass 알고리즘:
1. dist 열거 (size, mtime, relPath)
2. orphan 제거 (dist에 없는 파일 삭제)
3. 변경 복사 (size+mtime 비교, 1초 슬랙 허용)

### 3.2 `--jobs` 플래그 추가 (Phase B)

#### `BuildDevPlan.swiftBuildArguments` 시그니처 확장

수정 파일: `Sources/KalsaeCLI/Support/BuildDevPlan.swift`

```swift
// 변경 전:
public static func swiftBuildArguments(debug: Bool, target: String?) -> [String] {
    var args = ["build", "-c", debug ? "debug" : "release"]
    if let target { args += ["--target", target] }
    return args
}

// 변경 후:
public static func swiftBuildArguments(debug: Bool, target: String?, jobs: Int? = nil) -> [String] {
    var args = ["build", "-c", debug ? "debug" : "release"]
    if let target { args += ["--target", target] }
    if let jobs { args += ["-j", "\(jobs)"] }
    return args
}
```

#### `BuildCommand`에 `--jobs` 옵션 선언

수정 파일: `Sources/KalsaeCLI/Commands/BuildCommand.swift`

```swift
@Option(
    name: [.customShort("j"), .long],
    help: "Maximum number of parallel swift build jobs (default: CPU count).")
var jobs: Int? = nil
```

`run()` 내 직렬/병렬 양쪽 경로에서 전달:

```swift
let args = KSBuildPlan.swiftBuildArguments(debug: debug, target: target, jobs: jobs)
```

사용 예:
```powershell
# Defender 경합 환경에서 병렬도를 줄임
kalsae build -j 4

# CI에서 최대 병렬
kalsae build -j 16
```

### 3.3 `stageLoaderDLL` known triple 직접 검사 (Phase C)

수정 파일: `Sources/KalsaeCLI/Support/WebView2Provisioner.swift`

```swift
// 변경 전 — .build/ 전체 순회:
if let entries = try? fm.contentsOfDirectory(
    at: buildDir,
    includingPropertiesForKeys: [.isDirectoryKey],
    options: [.skipsHiddenFiles])
{
    for entry in entries {
        let triplePath = entry.appendingPathComponent(configuration)
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: triplePath.path, isDirectory: &isDir),
            isDir.boolValue
        {
            dests.append(triplePath)
        }
    }
}

// 변경 후 — known triple 직접 검사:
let knownTriples = [
    "x86_64-unknown-windows-msvc",
    "aarch64-unknown-windows-msvc",
]
for triple in knownTriples {
    let triplePath = buildDir
        .appendingPathComponent(triple)
        .appendingPathComponent(configuration)
    var isDir: ObjCBool = false
    if fm.fileExists(atPath: triplePath.path, isDirectory: &isDir),
       isDir.boolValue
    {
        dests.append(triplePath)
    }
}
```

I/O 호출이 `.build/` 내 항목 수 N에서 상수 2~3으로 감소한다.

---

## 4. 영향받는 파일

| 파일 | 변경 유형 |
|------|----------|
| `Sources/KalsaeCLI/Support/Packager.swift` | output 삭제 제거, `safeCopy` 추가, `copyTree` → sync 교체 |
| `Sources/KalsaeCLI/Support/BuildDevPlan.swift` | `swiftBuildArguments()` 시그니처 확장 |
| `Sources/KalsaeCLI/Commands/BuildCommand.swift` | `--jobs` 옵션 선언 + 전달 |
| `Sources/KalsaeCLI/Support/WebView2Provisioner.swift` | `stageLoaderDLL()` triple 검사 전환 |
| `Sources/KalsaeCLI/Support/ResourceSyncManager.swift` | 변경 없음 (sync() 재사용) |
| `Tests/KalsaeCLITests/PackagerTests.swift` | 기존 테스트 통과 확인 |

---

## 5. 검증

1. `swift build` 성공
2. `swift test --filter "PackagerTests"` — 기존 테스트 통과
3. 수동 검증: `kalsae build` 2회 연속 실행 → 2회차에서 Resources/ 복사 건수 감소
   확인 (`--timings` 비교)
4. `kalsae build -j 4` — swift build에 `-j 4` 전달 확인
5. `kalsae build --timings` — 각 단계 타이밍 정상 출력

---

## 6. 범위 경계

### 포함
- `Packager.run()` 증분화
- `--jobs` 플래그 (`BuildCommand`)
- `stageLoaderDLL` known triple 최적화

### 제외
- `DevCommand` 변경
- `PackagerMac` 증분화 (macOS 빌드 속도 이슈 미보고)
- `ResourceSyncManager` 자체 변경
- `swift build` 컴파일러/링커 자체 최적화
- Windows Defender 제외 설정 (사용자 OS 설정 — 문서 안내만)

---

## 7. 사용자 측 즉시 적용 가능 설정 (코드 변경 불요)

코드 변경과 별개로, 다음 OS 설정으로 추가 속도 향상을 얻을 수 있다:

```powershell
# .build/ 폴더를 Windows Defender 실시간 스캔에서 제외 (20~40% 감소)
Add-MpPreference -ExclusionPath "D:\300_Deveolopment\KalSae\.build"
```

| 조치 | 예상 효과 |
|------|----------|
| `.build/` Defender 제외 | swift build 단계 20~40% 감소 |
| `--clean` 미사용 (증분 빌드 활용) | 2회차~ 50~70% 감소 |
| `--no-package` (개발 반복 시) | package 단계 완전 제거 |
| `--skip-frontend` (frontend 미변경 시) | frontend 단계 제거 |
