/// 결정론적 UUID v5 생성기 (RFC 4122 §4.3).
///
/// 동일 (namespace, name) 입력은 항상 동일 UUID를 산출한다.
/// Tauri/WiX/MSI 호환 — Tauri는 DNS 네임스페이스 + `"<productName>.exe.app.<arch>"`로
/// UpgradeCode를 자동 생성한다. 같은 알고리즘을 채택해 Tauri 프로젝트에서 마이그레이션
/// 시 동일 GUID를 유지한다.
///
/// SHA-1 의존성을 피하기 위해 순수 Swift 구현을 포함한다 (CommonCrypto/CryptoKit
/// 없이 동작). 32 바이트 입력 기준 ~10 µs 수준이며, 빌드당 한 번만 호출되므로
/// 성능은 충분하다.
public import Foundation

public enum KSUUIDv5 {
    /// RFC 4122 §4.3에 정의된 DNS 네임스페이스 UUID.
    public static let dnsNamespace: UUID =
        UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!

    /// SHA-1 기반 UUID v5 생성.
    public static func v5(namespace: UUID, name: String) -> UUID {
        let nsBytes = uuidBytes(namespace)
        let nameBytes = Array(name.utf8)
        let digest = sha1(nsBytes + nameBytes)
        // 16바이트로 자르고 version(5) / variant(RFC4122) 비트 설정
        var out = Array(digest.prefix(16))
        out[6] = (out[6] & 0x0F) | 0x50  // version 5
        out[8] = (out[8] & 0x3F) | 0x80  // RFC 4122 variant
        return uuidFromBytes(out)
    }

    /// `"XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"` 대문자 16진 표기.
    public static func format(_ uuid: UUID) -> String {
        return uuid.uuidString.uppercased()
    }

    // MARK: - UUID byte helpers

    private static func uuidBytes(_ u: UUID) -> [UInt8] {
        let t = u.uuid
        return [
            t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7,
            t.8, t.9, t.10, t.11, t.12, t.13, t.14, t.15,
        ]
    }

    private static func uuidFromBytes(_ b: [UInt8]) -> UUID {
        precondition(b.count == 16)
        return UUID(
            uuid: (
                b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]
            ))
    }

    // MARK: - 순수 Swift SHA-1 (RFC 3174)

    /// 외부 의존성 없는 SHA-1. 입력 ≤ 수 KB 가정 (UUID v5 namespace+name).
    public static func sha1(_ message: [UInt8]) -> [UInt8] {
        var h0: UInt32 = 0x6745_2301
        var h1: UInt32 = 0xEFCD_AB89
        var h2: UInt32 = 0x98BA_DCFE
        var h3: UInt32 = 0x1032_5476
        var h4: UInt32 = 0xC3D2_E1F0

        // ── 패딩 ──
        var msg: [UInt8] = message
        let bitLen: UInt64 = UInt64(message.count) * 8
        msg.append(0x80)
        while msg.count % 64 != 56 { msg.append(0x00) }
        for i in (0..<8).reversed() {
            let shift: UInt64 = UInt64(i) * 8
            let byte: UInt8 = UInt8((bitLen >> shift) & 0xFF)
            msg.append(byte)
        }

        // ── 64바이트 블록 처리 ──
        var idx: Int = 0
        while idx < msg.count {
            sha1ProcessBlock(
                msg: msg, idx: idx,
                h0: &h0, h1: &h1, h2: &h2, h3: &h3, h4: &h4)
            idx += 64
        }

        var out: [UInt8] = []
        for h in [h0, h1, h2, h3, h4] {
            out.append(UInt8((h >> 24) & 0xFF))
            out.append(UInt8((h >> 16) & 0xFF))
            out.append(UInt8((h >> 8) & 0xFF))
            out.append(UInt8(h & 0xFF))
        }
        return out
    }

    @inline(__always)
    private static func rotl(_ x: UInt32, _ n: UInt32) -> UInt32 {
        (x << n) | (x >> (32 - n))
    }

    /// SHA-1 단일 64 바이트 블록 처리. `sha1` 본체에서 분리되어 type-checker가
    /// 풀어야 할 식 그래프를 작게 유지한다 (성능/동작 변화 없음).
    private static func sha1ProcessBlock(
        msg: [UInt8], idx: Int,
        h0: inout UInt32, h1: inout UInt32, h2: inout UInt32,
        h3: inout UInt32, h4: inout UInt32
    ) {
        var w: [UInt32] = [UInt32](repeating: 0, count: 80)
        for j in 0..<16 {
            let off: Int = idx + j * 4
            let b0: UInt32 = UInt32(msg[off]) << 24
            let b1: UInt32 = UInt32(msg[off + 1]) << 16
            let b2: UInt32 = UInt32(msg[off + 2]) << 8
            let b3: UInt32 = UInt32(msg[off + 3])
            w[j] = b0 | b1 | b2 | b3
        }
        for j in 16..<80 {
            let x: UInt32 = w[j - 3] ^ w[j - 8] ^ w[j - 14] ^ w[j - 16]
            w[j] = rotl(x, 1)
        }
        var a: UInt32 = h0
        var b: UInt32 = h1
        var c: UInt32 = h2
        var d: UInt32 = h3
        var e: UInt32 = h4
        for j in 0..<80 {
            let f: UInt32
            let k: UInt32
            switch j {
            case 0..<20:
                f = (b & c) | ((~b) & d)
                k = 0x5A82_7999
            case 20..<40:
                f = b ^ c ^ d
                k = 0x6ED9_EBA1
            case 40..<60:
                f = (b & c) | (b & d) | (c & d)
                k = 0x8F1B_BCDC
            default:
                f = b ^ c ^ d
                k = 0xCA62_C1D6
            }
            let t1: UInt32 = rotl(a, 5) &+ f
            let t2: UInt32 = t1 &+ e
            let t3: UInt32 = t2 &+ k
            let temp: UInt32 = t3 &+ w[j]
            e = d
            d = c
            c = rotl(b, 30)
            b = a
            a = temp
        }
        h0 = h0 &+ a
        h1 = h1 &+ b
        h2 = h2 &+ c
        h3 = h3 &+ d
        h4 = h4 &+ e
    }
}

/// `<productName>.exe.app.<arch>` (Tauri 호환) DNS 네임스페이스 v5에서
/// MSI UpgradeCode를 자동 생성한다.
extension KSUUIDv5 {
    public static func wixUpgradeCode(productName: String, arch: String) -> UUID {
        let name = "\(productName).exe.app.\(arch)"
        return v5(namespace: dnsNamespace, name: name)
    }
}
