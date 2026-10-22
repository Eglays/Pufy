import Foundation
import Compression

/// Harici kütüphane gerektirmeyen, hafif ZIP arşivi okuyucusu.
/// Özellikle DOCX içindeki `word/document.xml` dosyasını okumak için tasarlanmıştır.
enum MiniZip {
    struct Entry {
        let name: String
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    /// ZIP verisi içerisinden belirtilen dosya adının içeriğini çıkarır
    static func extract(entryName: String, from data: Data) -> Data? {
        guard let entries = listEntries(in: data) else { return nil }
        guard let target = entries.first(where: { $0.name == entryName }) else { return nil }
        return readEntry(target, from: data)
    }

    /// Merkezi dizini (Central Directory) tarayarak dosya girdilerini listeler
    static func listEntries(in data: Data) -> [Entry]? {
        guard let eocdOffset = findEOCD(in: data) else { return nil }
        guard eocdOffset + 22 <= data.count else { return nil }

        let cdCount = Int(readUInt16(data, at: eocdOffset + 10))
        let cdOffset = Int(readUInt32(data, at: eocdOffset + 16))

        var currentOffset = cdOffset
        var entries: [Entry] = []

        for _ in 0..<cdCount {
            guard currentOffset + 46 <= data.count else { break }
            let sig = readUInt32(data, at: currentOffset)
            guard sig == 0x02014b50 else { break } // PK\x01\x02

            let method = readUInt16(data, at: currentOffset + 10)
            let compSize = Int(readUInt32(data, at: currentOffset + 20))
            let uncompSize = Int(readUInt32(data, at: currentOffset + 24))
            let nameLen = Int(readUInt16(data, at: currentOffset + 28))
            let extraLen = Int(readUInt16(data, at: currentOffset + 30))
            let commentLen = Int(readUInt16(data, at: currentOffset + 32))
            let localOffset = Int(readUInt32(data, at: currentOffset + 42))

            let nameStart = currentOffset + 46
            guard nameStart + nameLen <= data.count else { break }
            let nameData = data.subdata(in: nameStart..<(nameStart + nameLen))
            let name = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)

            entries.append(Entry(
                name: name,
                compressionMethod: method,
                compressedSize: compSize,
                uncompressedSize: uncompSize,
                localHeaderOffset: localOffset
            ))

            currentOffset += 46 + nameLen + extraLen + commentLen
        }

        return entries
    }

    /// Belirli bir girdinin sıkıştırılmış/saklanmış verisini çözer
    private static func readEntry(_ entry: Entry, from data: Data) -> Data? {
        let offset = entry.localHeaderOffset
        guard offset + 30 <= data.count else { return nil }
        let sig = readUInt32(data, at: offset)
        guard sig == 0x04034b50 else { return nil } // PK\x03\x04

        let nameLen = Int(readUInt16(data, at: offset + 26))
        let extraLen = Int(readUInt16(data, at: offset + 28))
        let dataStart = offset + 30 + nameLen + extraLen
        let dataEnd = dataStart + entry.compressedSize

        guard dataEnd <= data.count else { return nil }
        let compressedData = data.subdata(in: dataStart..<dataEnd)

        switch entry.compressionMethod {
        case 0: // Stored (sıkıştırmasız)
            return compressedData
        case 8: // Deflate (Apple Compression COMPRESSION_ZLIB)
            return decompressDeflate(compressedData, uncompressedSize: entry.uncompressedSize)
        default:
            return nil
        }
    }

    /// Apple Compression framework ile raw DEFLATE açar
    private static func decompressDeflate(_ compressed: Data, uncompressedSize: Int) -> Data? {
        guard uncompressedSize > 0 else { return Data() }
        var destBuffer = [UInt8](repeating: 0, count: uncompressedSize)

        let decompressedCount = compressed.withUnsafeBytes { (srcRaw: UnsafeRawBufferPointer) -> Int in
            guard let srcPtr = srcRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return destBuffer.withUnsafeMutableBytes { (dstRaw: UnsafeMutableRawBufferPointer) -> Int in
                guard let dstPtr = dstRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                return compression_decode_buffer(
                    dstPtr,
                    uncompressedSize,
                    srcPtr,
                    compressed.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard decompressedCount > 0 else { return nil }
        return Data(destBuffer.prefix(decompressedCount))
    }

    /// Dosya sonundaki End of Central Directory (EOCD) imzasını bulur
    private static func findEOCD(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let maxSearch = min(data.count, 65536 + 22)
        let searchStart = data.count - maxSearch

        // Sondan başa doğru PK\x05\x06 ara
        for i in stride(from: data.count - 22, through: searchStart, by: -1) {
            if readUInt32(data, at: i) == 0x06054b50 {
                return i
            }
        }
        return nil
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        let b0 = UInt16(data[offset])
        let b1 = UInt16(data[offset + 1])
        return b0 | (b1 << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }
}
