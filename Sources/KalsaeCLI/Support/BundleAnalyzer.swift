/// 프론트엔드 번들 디렉터리를 분석해 크기 리포트와 최적화 제안을 생성한다.
///
/// `kalsae build`의 일부로 호출되어 개발자에게 번들 구성에 대한
/// 인사이트를 제공한다. "thin frontend" 원칙을 장려하기 위한 도구이다.
public import Foundation

public struct KSBundleReport: Sendable, CustomStringConvertible {
    public let totalFiles: Int
    public let totalBytes: Int
    public let totalBytesFormatted: String
    public let largestFiles: [(name: String, bytes: Int)]
    public let warnings: [String]
    public let suggestions: [String]

    public var description: String {
        var lines: [String] = [
            "",
            "📊  Frontend Bundle Analysis",
            "─────────────────────────────",
            "  Files:  \(totalFiles)",
            "  Size:   \(totalBytesFormatted) (\(ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)))",
        ]
        if !largestFiles.isEmpty {
            lines.append("")
            lines.append("  Largest files:")
            for (name, bytes) in largestFiles {
                let pct = totalBytes > 0 ? Double(bytes) / Double(totalBytes) * 100 : 0
                lines.append(
                    "    • \(name)  "
                        + "\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))"
                        + " (\(String(format: "%.1f", pct))%)"
                )
            }
        }
        if !warnings.isEmpty {
            lines.append("")
            lines.append("  ⚠  Warnings:")
            for w in warnings { lines.append("    • \(w)") }
        }
        if !suggestions.isEmpty {
            lines.append("")
            lines.append("  💡  Suggestions:")
            for s in suggestions { lines.append("    • \(s)") }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// 사람이 읽기 쉬운 바이트 포맷 (예: "1.2 MB").
    public static func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

public enum KSBundleAnalyzer {
    /// 분석할 때 무시할 파일 확장자/이름 패턴.
    private static let ignoredExtensions: Set<String> = [
        // 소스맵 — 프로덕션에 불필요
        "map"
    ]

    private static let ignoredNames: Set<String> = [
        ".gitkeep", ".gitignore", ".DS_Store", "thumbs.db",
    ]

    /// 프론트엔드 dist 디렉터리를 분석한다.
    /// - Parameter distURL: 프론트엔드 빌드 산출물 디렉터리
    /// - Returns: 번들 분석 리포트
    public static func analyze(distURL: URL) -> KSBundleReport {
        let fm = FileManager.default
        var totalBytes = 0
        var totalFiles = 0
        var allFiles: [(name: String, bytes: Int, ext: String)] = []
        var warnings: [String] = []
        var suggestions: [String] = []

        guard
            let enumerator = fm.enumerator(
                at: distURL,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles])
        else {
            return KSBundleReport(
                totalFiles: 0, totalBytes: 0, totalBytesFormatted: "0 bytes",
                largestFiles: [], warnings: ["Cannot enumerate dist directory."],
                suggestions: [])
        }

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]),
                values.isDirectory != true,
                let size = values.fileSize
            else { continue }

            let name = fileURL.lastPathComponent
            let ext = fileURL.pathExtension.lowercased()

            // 무시 목록
            if ignoredNames.contains(name) { continue }

            totalFiles += 1
            totalBytes += size
            allFiles.append((name: name, bytes: size, ext: ext))

            // 경고: 소스맵 파일
            if ext == "map" {
                warnings.append(
                    "Source map found: \(name) (\(KSBundleReport.formatBytes(size))) — strip in production")
            }
        }

        // 상위 5개 큰 파일
        let sorted = allFiles.sorted { $0.bytes > $1.bytes }
        let largest = Array(sorted.prefix(5)).map { ($0.name, $0.bytes) }

        // 제안 생성
        let totalMB = Double(totalBytes) / 1_048_576.0
        if totalMB > 1.0 {
            suggestions.append(
                "Bundle is \(String(format: "%.1f", totalMB)) MB. Consider code-splitting, "
                    + "tree-shaking, and lazy-loading."
            )
        }

        let htmlFiles = allFiles.filter { $0.ext == "html" }
        if htmlFiles.count > 1 {
            suggestions.append(
                "Multiple HTML entry points (\(htmlFiles.count)). Consider a single-page app for smaller footprint.")
        }

        let hasSourceMaps = allFiles.contains { $0.ext == "map" }
        if hasSourceMaps {
            suggestions.append(
                "Enable `stripSourceMaps` in kalsae.json build config to remove .map files during packaging.")
        }

        let jsFiles = allFiles.filter { $0.ext == "js" || $0.ext == "mjs" }
        let jsTotal = jsFiles.reduce(0) { $0 + $1.bytes }
        if jsTotal > 512_000 {
            suggestions.append(
                "JavaScript total is \(KSBundleReport.formatBytes(jsTotal)). Consider code-splitting.")
        }

        return KSBundleReport(
            totalFiles: totalFiles,
            totalBytes: totalBytes,
            totalBytesFormatted: KSBundleReport.formatBytes(totalBytes),
            largestFiles: largest,
            warnings: warnings,
            suggestions: suggestions)
    }

    /// dist 디렉터리에서 불필요한 파일(소스맵 등)을 제거한다.
    /// - Parameters:
    ///   - distURL: 프론트엔드 빌드 산출물 디렉터리
    ///   - stripSourceMaps: 소스맵(.map) 파일 제거 여부
    ///   - stripExtensions: 추가로 제거할 확장자 목록
    /// - Returns: 제거된 파일 수, 제거 실패 파일 수, 절약된 바이트 수
    @discardableResult
    public static func strip(
        distURL: URL,
        stripSourceMaps: Bool,
        stripExtensions: [String] = []
    ) -> (removed: Int, failed: Int, savedBytes: Int) {
        let fm = FileManager.default
        var removed = 0
        var failed = 0
        var savedBytes = 0

        var extensionsToStrip = Set(stripExtensions.map { $0.lowercased() })
        if stripSourceMaps {
            extensionsToStrip.insert("map")
        }

        guard !extensionsToStrip.isEmpty,
            let enumerator = fm.enumerator(
                at: distURL,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles])
        else { return (0, 0, 0) }

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]),
                values.isDirectory != true,
                let size = values.fileSize
            else { continue }

            let ext = fileURL.pathExtension.lowercased()
            if extensionsToStrip.contains(ext) {
                do {
                    try fm.removeItem(at: fileURL)
                    removed += 1
                    savedBytes += size
                } catch {
                    failed += 1
                }
            }
        }

        return (removed, failed, savedBytes)
    }
}
