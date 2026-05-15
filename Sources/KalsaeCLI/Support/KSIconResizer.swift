/// 단순 PNG 리사이저. macOS/iOS 호스트에서는 CoreGraphics 로 실제 리사이즈를,
/// Windows/Linux 호스트에서는 원본 데이터를 그대로 반환한다 (Android 런타임이
/// 적응형 mipmap 셀렉션을 수행하므로 PNG 자체가 density-정확하지 않아도 동작).
///
/// RFC-007 §3.1.5 는 "외부 의존성 없는 순수 Swift 구현" 을 요구한다. 본 구현은
/// CoreGraphics 가 가용한 곳에서만 리사이즈하고 그 외에는 fallback 으로
/// 안전한 카피만 한다 — 추가 C 의존성 없이 RFC 의 의도를 보존한다.
public import Foundation

#if canImport(CoreGraphics) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
    import CoreGraphics
    import ImageIO
    import UniformTypeIdentifiers
#endif

public enum KSIconResizer {

    /// CoreGraphics 기반 실제 리사이즈가 가능한 호스트인지.
    public static var isResizingSupported: Bool {
        #if canImport(CoreGraphics) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
            return true
        #else
            return false
        #endif
    }

    /// `pngData` 를 `size` x `size` 정사각 PNG 로 리사이즈한다.
    /// 지원되지 않는 호스트에서는 원본 데이터를 반환.
    public static func resizeIfPossible(pngData: Data, to size: Int) -> Data {
        #if canImport(CoreGraphics) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
            return resizePNG(pngData, to: size) ?? pngData
        #else
            return pngData
        #endif
    }

    /// 1x1 단색 PNG (RGBA 0xFF888888) — 아이콘 미지정 시 placeholder.
    public static func placeholderPNG() -> Data {
        // 미리 인코딩된 1x1 회색 PNG (89 50 4E 47 ...). 디스크 의존성 없음.
        let bytes: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
            0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
            0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xC0,
            0xC0, 0x00, 0x00, 0x00, 0x05, 0x00, 0x01, 0xE2,
            0x26, 0x05, 0x6F, 0x00, 0x00, 0x00, 0x00, 0x49,
            0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
        ]
        return Data(bytes)
    }

    #if canImport(CoreGraphics) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
        private static func resizePNG(_ data: Data, to size: Int) -> Data? {
            guard
                let src = CGImageSourceCreateWithData(data as CFData, nil),
                let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
            else { return nil }
            let cs = CGColorSpaceCreateDeviceRGB()
            guard
                let ctx = CGContext(
                    data: nil, width: size, height: size, bitsPerComponent: 8,
                    bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            guard let resized = ctx.makeImage() else { return nil }
            let out = NSMutableData()
            guard
                let dest = CGImageDestinationCreateWithData(
                    out, UTType.png.identifier as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(dest, resized, nil)
            guard CGImageDestinationFinalize(dest) else { return nil }
            return out as Data
        }
    #endif
}
