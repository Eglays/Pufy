import Foundation
import PDFKit
import UniformTypeIdentifiers

enum FileExtractionError: LocalizedError {
    case fileTooLarge
    case unsupportedType
    case unreadablePDF
    case emptyText
    case docxReadFailed
    case generic(String)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return NSLocalizedString("Dosya çok büyük (en fazla 25 MB).", comment: "")
        case .unsupportedType:
            return NSLocalizedString("Desteklenmeyen dosya türü.", comment: "")
        case .unreadablePDF:
            return NSLocalizedString("Bu PDF'te okunabilir metin yok (taranmış belge olabilir)", comment: "")
        case .emptyText:
            return NSLocalizedString("Dosyada okunabilir metin bulunamadı.", comment: "")
        case .docxReadFailed:
            return NSLocalizedString("Word belgesi açılamadı.", comment: "")
        case .generic(let msg):
            return msg
        }
    }
}

final class DocxXmlParser: NSObject, XMLParserDelegate {
    private var buffer = ""
    private var inTextElement = false

    func extractText(from xmlData: Data) -> String {
        buffer = ""
        inTextElement = false
        let parser = XMLParser(data: xmlData)
        parser.delegate = self
        parser.parse()
        return buffer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let tag = elementName.lowercased()
        if tag == "w:t" || tag == "t" {
            inTextElement = true
        } else if tag == "w:tab" || tag == "tab" {
            buffer.append("\t")
        } else if tag == "w:br" || tag == "br" {
            buffer.append("\n")
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inTextElement {
            buffer.append(string)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let tag = elementName.lowercased()
        if tag == "w:t" || tag == "t" {
            inTextElement = false
        } else if tag == "w:p" || tag == "p" {
            buffer.append("\n")
        }
    }
}

enum FileTextExtractor {
    static let maxFileSize = 25 * 1024 * 1024 // 25 MB
    static let maxTextLength = 60_000         // 60.000 karakter

    static let supportedExtensions: Set<String> = [
        // PDF
        "pdf",
        // Word
        "docx",
        // Text
        "txt", "md", "csv", "json", "log",
        // Code
        "swift", "kt", "py", "js", "ts", "html", "css", "xml", "yaml", "yml"
    ]

    static func detectKind(extension ext: String) -> String {
        switch ext.lowercased() {
        case "pdf":
            return "pdf"
        case "docx":
            return "docx"
        case "txt", "md", "csv", "json", "log":
            return "text"
        default:
            return "code"
        }
    }

    /// Dosyadan metin çıkarır (ana iş parçacığını kilitlememesi için Task.detached ile çağrılmalı)
    static func extract(from url: URL) throws -> FileAttachment {
        let isSecured = url.startAccessingSecurityScopedResource()
        defer { if isSecured { url.stopAccessingSecurityScopedResource() } }

        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
        let size = resourceValues?.fileSize ?? (try? Data(contentsOf: url).count) ?? 0

        guard size <= maxFileSize else {
            throw FileExtractionError.fileTooLarge
        }

        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            throw FileExtractionError.unsupportedType
        }

        let name = url.lastPathComponent
        let kind = detectKind(extension: ext)

        var rawText = ""
        var pageCount: Int? = nil

        switch kind {
        case "pdf":
            guard let doc = PDFDocument(url: url) else {
                throw FileExtractionError.unreadablePDF
            }
            pageCount = doc.pageCount
            var pagesText: [String] = []
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i), let pText = page.string {
                    let trimmed = pText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        pagesText.append(trimmed)
                    }
                }
            }
            rawText = pagesText.joined(separator: "\n\n")
            if rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw FileExtractionError.unreadablePDF
            }

        case "docx":
            let fileData = try Data(contentsOf: url)
            guard let docXmlData = MiniZip.extract(entryName: "word/document.xml", from: fileData) else {
                throw FileExtractionError.docxReadFailed
            }
            let parser = DocxXmlParser()
            rawText = parser.extractText(from: docXmlData)
            if rawText.isEmpty {
                throw FileExtractionError.emptyText
            }

        default:
            // Text ve Code dosyaları
            let fileData = try Data(contentsOf: url)
            if let str = String(data: fileData, encoding: .utf8) {
                rawText = str
            } else {
                // Windows-1254 (Windows Latin 5) dene
                let win1254 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsLatin5.rawValue)))
                if let str = String(data: fileData, encoding: win1254) {
                    rawText = str
                } else {
                    // ISO-8859-9 (ISO Latin 5) dene
                    let iso8859_9 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.isoLatin5.rawValue)))
                    if let str = String(data: fileData, encoding: iso8859_9) {
                        rawText = str
                    } else {
                        rawText = String(decoding: fileData, as: UTF8.self)
                    }
                }
            }
        }

        let cleanText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            throw FileExtractionError.emptyText
        }

        let truncated = cleanText.count > maxTextLength
        let finalText = truncated ? String(cleanText.prefix(maxTextLength)) : cleanText

        return FileAttachment(
            name: name,
            kind: kind,
            size: size,
            text: finalText,
            truncated: truncated,
            pageCount: pageCount
        )
    }
}
