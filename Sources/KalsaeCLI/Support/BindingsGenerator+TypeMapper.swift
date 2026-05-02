import Foundation

extension KSBindingsGenerator {
    /// Swift 타입 철자 (e.g. `"[String: Int?]"`)  를
    /// TypeScript 등가물 (`"Record<string, number | null>"`)  로 매핑한다.
    ///
    /// 알 수 없는 식별자는 동일 바인딩 파일에 발행되거나
    /// 소비자가 다른 곳에서 임포트하는 사용자 타입이라고
    /// 가정하고 같은 철자를 그대로 통과시킨다.
    static func mapType(_ swift: String) -> String {
        let t = swift.trimmingCharacters(in: .whitespaces)
        // 옵션널 설탕 표기: T?
        if t.hasSuffix("?") {
            return mapType(String(t.dropLast())) + " | null"
        }
        // Optional<T>
        if t.hasPrefix("Optional<"), t.hasSuffix(">") {
            return mapType(String(t.dropFirst("Optional<".count).dropLast())) + " | null"
        }
        // 배열 설탕 표기: [T]
        if t.hasPrefix("["), t.hasSuffix("]"), !t.contains(":") {
            let inner = String(t.dropFirst().dropLast())
            return "(\(mapType(inner)))[]"
        }
        // 딕셔너리 설탕 표기: [K: V]
        if t.hasPrefix("["), t.hasSuffix("]"), let colon = t.firstIndex(of: ":") {
            let k = String(t[t.index(after: t.startIndex)..<colon])
                .trimmingCharacters(in: .whitespaces)
            let v = String(t[t.index(after: colon)..<t.index(before: t.endIndex)])
                .trimmingCharacters(in: .whitespaces)
            if k == "String" {
                return "Record<string, \(mapType(v))>"
            }
            return "Record<string, \(mapType(v))> /* keys: \(k) */"
        }
        // 제네릭 Array<T> / Set<T>
        if let inner = stripGeneric(t, "Array") ?? stripGeneric(t, "Set") {
            return "(\(mapType(inner)))[]"
        }
        if let inner = stripGeneric(t, "Optional") {
            return mapType(inner) + " | null"
        }
        if let inner = stripGeneric(t, "Dictionary") {
            // Dictionary<K, V>
            if let comma = topLevelSplit(inner, on: ",") {
                let k = String(inner[..<comma]).trimmingCharacters(in: .whitespaces)
                let v = String(inner[inner.index(after: comma)...])
                    .trimmingCharacters(in: .whitespaces)
                if k == "String" { return "Record<string, \(mapType(v))>" }
                return "Record<string, \(mapType(v))> /* keys: \(k) */"
            }
        }
        switch t {
        case "String", "URL", "UUID", "Date", "Data":
            return "string"
        case "Bool":
            return "boolean"
        case "Int", "Int8", "Int16", "Int32", "Int64",
            "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
            "Float", "Double", "CGFloat":
            return "number"
        case "Void", "()":
            return "void"
        default:
            // 사용자 식별자 — 그대로 통과(타입 섹션에 출력되었거나 다른
            // 곳에서 참조된다고 가정).
            return t
        }
    }

    static func stripGeneric(_ t: String, _ name: String) -> String? {
        guard t.hasPrefix(name + "<"), t.hasSuffix(">") else { return nil }
        return String(t.dropFirst(name.count + 1).dropLast())
    }

    static func stripBackticks(_ s: String) -> String {
        var s = s
        if s.hasPrefix("`") { s.removeFirst() }
        if s.hasSuffix("`") { s.removeLast() }
        return s
    }

    /// `<>` 기준으로 따진이 0인 첫 번째 최상위 콤마에서 `s`를 분할한다.
    static func topLevelSplit(_ s: String, on sep: Character) -> String.Index? {
        var depth = 0
        for i in s.indices {
            let c = s[i]
            if c == "<" { depth += 1 } else if c == ">" { depth -= 1 } else if c == sep, depth == 0 { return i }
        }
        return nil
    }
}
