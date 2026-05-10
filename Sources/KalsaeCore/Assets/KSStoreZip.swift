public import Foundation

/// Minimal pure-Swift ZIP STORE-only writer/reader.
///
/// Kalsae standalone 임베드 zip 의 producer/consumer 가 둘 다 본 모듈을
/// 사용한다. STORE(method=0, no compression) 만 지원하며, 작은 SPA 번들에서
/// 메모리 직접 서빙(Phase 4) 시 추출/압축 해제 비용을 0 으로 유지한다.
///
/// 호환성: 표준 PKZIP 컨테이너이므로 7-zip / Windows Explorer / `tar.exe`
/// 어느 쪽으로 풀어도 동일 산출물이 나온다.
///
/// ZIP 64, 암호화, 압축, 스트리밍 멀티파일 등은 의도적으로 미지원.
public enum KSStoreZip {
    public struct Entry: Sendable {
        public let name: String
        public let data: Data
        public init(name: String, data: Data) {
            self.name = name
            self.data = data
        }
    }

    public enum ReadError: Error, CustomStringConvertible {
        case notAZipArchive
        case unsupportedMethod(UInt16, name: String)
        case truncated
        case crcMismatch(name: String)

        public var description: String {
            switch self {
            case .notAZipArchive:
                return "Data is not a ZIP archive (EOCD signature missing)."
            case .unsupportedMethod(let m, let name):
                return "ZIP entry \(name) uses unsupported compression method \(m); only STORE (0) is supported."
            case .truncated:
                return "ZIP archive is truncated."
            case .crcMismatch(let name):
                return "ZIP entry \(name) failed CRC32 verification."
            }
        }
    }

    // MARK: - Writer

    /// `entries` 를 STORE 방식으로 묶어 단일 PKZIP `Data` 로 반환한다.
    /// 입력 순서가 그대로 central directory 순서로 보존된다.
    public static func write(entries: [Entry]) -> Data {
        var archive = Data()
        var cdRecords = Data()
        var offsets: [UInt32] = []

        for entry in entries {
            offsets.append(UInt32(archive.count))
            let nameBytes = Array(entry.name.utf8)
            let crc = crc32(of: entry.data)
            let size = UInt32(entry.data.count)

            // Local file header
            archive.append(le32: 0x0403_4b50)
            archive.append(le16: 20)            // version needed
            archive.append(le16: 0)             // general purpose bit flag
            archive.append(le16: 0)             // method (STORE)
            archive.append(le16: 0)             // mod time
            archive.append(le16: 0)             // mod date
            archive.append(le32: crc)
            archive.append(le32: size)          // compressed
            archive.append(le32: size)          // uncompressed
            archive.append(le16: UInt16(nameBytes.count))
            archive.append(le16: 0)             // extra len
            archive.append(contentsOf: nameBytes)
            archive.append(entry.data)

            // Central directory record (built up here, appended after local headers)
            cdRecords.append(le32: 0x0201_4b50)
            cdRecords.append(le16: 20)          // version made by
            cdRecords.append(le16: 20)          // version needed
            cdRecords.append(le16: 0)           // bit flag
            cdRecords.append(le16: 0)           // method
            cdRecords.append(le16: 0)           // mod time
            cdRecords.append(le16: 0)           // mod date
            cdRecords.append(le32: crc)
            cdRecords.append(le32: size)
            cdRecords.append(le32: size)
            cdRecords.append(le16: UInt16(nameBytes.count))
            cdRecords.append(le16: 0)           // extra len
            cdRecords.append(le16: 0)           // comment len
            cdRecords.append(le16: 0)           // disk number start
            cdRecords.append(le16: 0)           // internal attrs
            cdRecords.append(le32: 0)           // external attrs
            cdRecords.append(le32: offsets.last!)
            cdRecords.append(contentsOf: nameBytes)
        }

        let cdOffset = UInt32(archive.count)
        let cdSize = UInt32(cdRecords.count)
        archive.append(cdRecords)

        // EOCD
        archive.append(le32: 0x0605_4b50)
        archive.append(le16: 0)                 // disk number
        archive.append(le16: 0)                 // disk where CD starts
        archive.append(le16: UInt16(entries.count))
        archive.append(le16: UInt16(entries.count))
        archive.append(le32: cdSize)
        archive.append(le32: cdOffset)
        archive.append(le16: 0)                 // comment len

        return archive
    }

    // MARK: - Reader

    /// `data` 에서 ZIP 엔트리를 순회하며 `(name, bytes)` 를 callback 으로 전달.
    /// STORE 외 메서드를 만나면 throw.
    public static func forEachEntry(
        in data: Data,
        verifyCRC: Bool = false,
        _ body: (String, Data) throws -> Void
    ) throws {
        guard let eocd = findEOCD(in: data) else { throw ReadError.notAZipArchive }
        let cdOffset = Int(data.le32(at: eocd + 16))
        let totalEntries = Int(data.le16(at: eocd + 10))

        var p = cdOffset
        for _ in 0..<totalEntries {
            guard p + 46 <= data.count else { throw ReadError.truncated }
            guard data.le32(at: p) == 0x0201_4b50 else { throw ReadError.notAZipArchive }
            let method = data.le16(at: p + 10)
            let crcExpected = data.le32(at: p + 16)
            let compSize = Int(data.le32(at: p + 20))
            let uncompSize = Int(data.le32(at: p + 24))
            let nameLen = Int(data.le16(at: p + 28))
            let extraLen = Int(data.le16(at: p + 30))
            let commentLen = Int(data.le16(at: p + 32))
            let lfhOffset = Int(data.le32(at: p + 42))
            guard p + 46 + nameLen <= data.count else { throw ReadError.truncated }
            let nameBytes = data.subdata(in: (p + 46)..<(p + 46 + nameLen))
            let name = String(decoding: nameBytes, as: UTF8.self)
            p += 46 + nameLen + extraLen + commentLen

            // Read LFH to get the actual data offset (LFH name/extra lengths
            // can differ from CD when extra fields differ; we honor LFH).
            guard lfhOffset + 30 <= data.count else { throw ReadError.truncated }
            guard data.le32(at: lfhOffset) == 0x0403_4b50 else {
                throw ReadError.notAZipArchive
            }
            let lfhMethod = data.le16(at: lfhOffset + 8)
            let lfhNameLen = Int(data.le16(at: lfhOffset + 26))
            let lfhExtraLen = Int(data.le16(at: lfhOffset + 28))
            let dataStart = lfhOffset + 30 + lfhNameLen + lfhExtraLen

            // Directory entries: zero-byte STORE entries with a trailing '/'.
            if name.hasSuffix("/") && uncompSize == 0 { continue }

            let effectiveMethod = lfhMethod != 0 ? lfhMethod : method
            guard effectiveMethod == 0 else {
                throw ReadError.unsupportedMethod(effectiveMethod, name: name)
            }
            guard compSize == uncompSize else { throw ReadError.unsupportedMethod(effectiveMethod, name: name) }
            guard dataStart + compSize <= data.count else { throw ReadError.truncated }

            let payload = data.subdata(in: dataStart..<(dataStart + compSize))
            if verifyCRC, crc32(of: payload) != crcExpected {
                throw ReadError.crcMismatch(name: name)
            }
            try body(name, payload)
        }
    }

    /// 편의: 모든 엔트리를 `[name: data]` 로 반환.
    public static func readAllEntries(from data: Data, verifyCRC: Bool = false)
        throws -> [String: Data]
    {
        var out: [String: Data] = [:]
        try forEachEntry(in: data, verifyCRC: verifyCRC) { name, bytes in
            out[name] = bytes
        }
        return out
    }

    // MARK: - Internals

    private static func findEOCD(in data: Data) -> Int? {
        // EOCD 는 가변 길이 comment 가 끝에 붙을 수 있어 끝에서부터 0xFFFF+22
        // 까지 후방 탐색. 일반 zip 은 코멘트가 비어 있어 마지막 22바이트.
        let max = min(data.count, 0xFFFF + 22)
        guard data.count >= 22 else { return nil }
        var i = data.count - 22
        let lower = data.count - max
        while i >= lower {
            if data.le32(at: i) == 0x0605_4b50 { return i }
            if i == 0 { break }
            i -= 1
        }
        return nil
    }

    // CRC-32 (IEEE 802.3, polynomial 0xEDB88320). Table-based.
    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : (c >> 1)
            }
            return c
        }
    }()

    public static func crc32(of data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            let p = base.assumingMemoryBound(to: UInt8.self)
            for i in 0..<raw.count {
                let idx = Int((c ^ UInt32(p[i])) & 0xFF)
                c = crcTable[idx] ^ (c >> 8)
            }
        }
        return c ^ 0xFFFF_FFFF
    }
}

// MARK: - Data little-endian helpers

extension Data {
    fileprivate mutating func append(le16 v: UInt16) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
    }
    fileprivate mutating func append(le32 v: UInt32) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
        append(UInt8((v >> 16) & 0xFF))
        append(UInt8((v >> 24) & 0xFF))
    }
    fileprivate func le16(at offset: Int) -> UInt16 {
        withUnsafeBytes { raw -> UInt16 in
            let p = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
            return UInt16(p[offset]) | (UInt16(p[offset + 1]) << 8)
        }
    }
    fileprivate func le32(at offset: Int) -> UInt32 {
        withUnsafeBytes { raw -> UInt32 in
            let p = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
            return UInt32(p[offset]) | (UInt32(p[offset + 1]) << 8)
                | (UInt32(p[offset + 2]) << 16) | (UInt32(p[offset + 3]) << 24)
        }
    }
}
