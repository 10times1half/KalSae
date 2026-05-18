/// Windows PE (Portable Executable) Import Table 파서.
///
/// `dumpbin /dependents` 의존성을 제거하기 위해 PE/COFF 헤더를 순수 Swift 로
/// 읽어 import descriptor 배열에서 DLL 이름 목록을 추출한다. `KSWindowsRuntimeStager`
/// 가 빌드 산출물 옆에 어떤 DLL 을 staging 해야 하는지 결정할 때 사용한다.
///
/// 참고:
/// - PE 포맷: <https://learn.microsoft.com/en-us/windows/win32/debug/pe-format>
/// - 본 파서는 **read-only** 이며 PE 구조의 일부 (DOS / NT Header / Optional
///   Header / Section Table / Import Directory) 만 해석한다. Bound imports,
///   delay-load imports, resource directory 는 다루지 않는다.
///
/// 호스트 OS 와 무관하게 동작하므로 macOS/Linux 호스트에서도 PE 파일을
/// 분석할 수 있다 (CI/cross-compile 검증 용도).
public import Foundation

public enum KSPEImportReader {
    /// 주어진 PE 파일의 Import Table 에 등록된 DLL 이름 목록을 반환한다.
    ///
    /// 반환 값은 PE 안에 저장된 그대로의 ASCII 문자열이다(예:
    /// `"KERNEL32.dll"`, `"swift_Concurrency.dll"`). 정렬·중복 제거는
    /// 호출자가 책임진다.
    ///
    /// - Throws: `ShellError.message` — 파일이 PE 가 아니거나 헤더가 깨졌을 때.
    public static func importedDLLs(at url: URL) throws -> [String] {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try parse(data: data)
    }

    /// `Data` 에서 직접 파싱. 테스트에서 메모리 픽스처를 그대로 넣을 때 사용한다.
    public static func parse(data: Data) throws -> [String] {
        let reader = Reader(data: data)

        // 1) DOS Header — "MZ" 시그니처 + e_lfanew (PE 헤더 오프셋, +0x3C)
        guard reader.byte(at: 0) == 0x4D, reader.byte(at: 1) == 0x5A else {
            throw ShellError.message("Not a PE file: missing 'MZ' DOS signature.")
        }
        let peOffset = Int(try reader.uint32(at: 0x3C))

        // 2) "PE\0\0" 시그니처
        guard reader.byte(at: peOffset) == 0x50,
            reader.byte(at: peOffset + 1) == 0x45,
            reader.byte(at: peOffset + 2) == 0,
            reader.byte(at: peOffset + 3) == 0
        else {
            throw ShellError.message(
                "Not a PE file: missing 'PE\\0\\0' signature at offset \(peOffset).")
        }

        // 3) COFF File Header (20 bytes) — Number of Sections @ +2,
        //    Size of Optional Header @ +16. Optional Header 는 직후에 위치.
        let coffOffset = peOffset + 4
        let numberOfSections = Int(try reader.uint16(at: coffOffset + 2))
        let optHeaderSize = Int(try reader.uint16(at: coffOffset + 16))
        let optHeaderOffset = coffOffset + 20
        let sectionTableOffset = optHeaderOffset + optHeaderSize

        // 4) Optional Header magic — PE32 (0x10B) vs PE32+ (0x20B).
        //    Data Directory 위치가 magic 에 따라 다르다 (PE32=+0x60, PE32+=+0x70).
        let magic = try reader.uint16(at: optHeaderOffset)
        let dataDirOffset: Int
        switch magic {
        case 0x10B: dataDirOffset = optHeaderOffset + 0x60
        case 0x20B: dataDirOffset = optHeaderOffset + 0x70
        default:
            throw ShellError.message(
                "Unknown PE Optional Header magic: 0x\(String(magic, radix: 16)).")
        }

        // Data Directory[1] = Import Table (RVA, Size).
        let importTableRVA = try reader.uint32(at: dataDirOffset + 8)
        let importTableSize = try reader.uint32(at: dataDirOffset + 12)
        if importTableRVA == 0 || importTableSize == 0 {
            // Import 가 없는 PE (드물지만 가능).
            return []
        }

        // 5) Section Table — RVA → File Offset 변환에 사용.
        var sections: [Section] = []
        sections.reserveCapacity(numberOfSections)
        for i in 0..<numberOfSections {
            let base = sectionTableOffset + i * 40  // IMAGE_SECTION_HEADER = 40 bytes
            let virtualSize = try reader.uint32(at: base + 8)
            let virtualAddress = try reader.uint32(at: base + 12)
            let sizeOfRawData = try reader.uint32(at: base + 16)
            let pointerToRawData = try reader.uint32(at: base + 20)
            sections.append(
                Section(
                    virtualAddress: virtualAddress,
                    virtualSize: max(virtualSize, sizeOfRawData),
                    pointerToRawData: pointerToRawData))
        }

        guard let importFileOffset = rvaToFileOffset(importTableRVA, sections: sections) else {
            throw ShellError.message(
                "Import Table RVA 0x\(String(importTableRVA, radix: 16)) not contained in any section.")
        }

        // 6) IMAGE_IMPORT_DESCRIPTOR (20 bytes) 배열, null entry 로 종료.
        //    Name RVA 는 offset +12.
        var names: [String] = []
        var cursor = importFileOffset
        let importTableEnd = importFileOffset + Int(importTableSize)
        while cursor + 20 <= reader.count {
            let nameRVA = try reader.uint32(at: cursor + 12)
            let originalThunk = try reader.uint32(at: cursor + 0)
            let firstThunk = try reader.uint32(at: cursor + 16)
            // null descriptor 종료 조건
            if nameRVA == 0 && originalThunk == 0 && firstThunk == 0 { break }
            if let nameOffset = rvaToFileOffset(nameRVA, sections: sections),
                let name = readASCIIZ(reader: reader, at: nameOffset)
            {
                names.append(name)
            }
            cursor += 20
            // 안전장치: Import Table Size 를 넘어서면 종료.
            if cursor >= importTableEnd { break }
        }
        return names
    }

    // MARK: - Helpers

    private struct Section {
        let virtualAddress: UInt32
        let virtualSize: UInt32
        let pointerToRawData: UInt32
    }

    private static func rvaToFileOffset(_ rva: UInt32, sections: [Section]) -> Int? {
        for s in sections {
            if rva >= s.virtualAddress, rva < s.virtualAddress &+ s.virtualSize {
                return Int(s.pointerToRawData &+ (rva &- s.virtualAddress))
            }
        }
        return nil
    }

    private static func readASCIIZ(reader: Reader, at offset: Int) -> String? {
        var end = offset
        while end < reader.count, reader.byte(at: end) != 0 {
            end += 1
        }
        if end <= offset { return "" }
        let bytes = reader.subdata(from: offset, count: end - offset)
        return String(data: bytes, encoding: .ascii)
    }

    /// Little-endian 정수 추출을 캡슐화하는 얇은 래퍼. PE 는 항상 little-endian.
    private struct Reader {
        let data: Data
        var count: Int { data.count }
        func byte(at offset: Int) -> UInt8 {
            guard offset >= 0, offset < data.count else { return 0 }
            return data[data.startIndex + offset]
        }
        func uint16(at offset: Int) throws -> UInt16 {
            guard offset >= 0, offset + 2 <= data.count else {
                throw ShellError.message("PE: short read at offset \(offset) (uint16).")
            }
            let lo = UInt16(data[data.startIndex + offset])
            let hi = UInt16(data[data.startIndex + offset + 1])
            return lo | (hi << 8)
        }
        func uint32(at offset: Int) throws -> UInt32 {
            guard offset >= 0, offset + 4 <= data.count else {
                throw ShellError.message("PE: short read at offset \(offset) (uint32).")
            }
            var v: UInt32 = 0
            for i in 0..<4 {
                v |= UInt32(data[data.startIndex + offset + i]) << (8 * i)
            }
            return v
        }
        func subdata(from offset: Int, count: Int) -> Data {
            let start = data.startIndex + offset
            return data.subdata(in: start..<(start + count))
        }
    }
}
