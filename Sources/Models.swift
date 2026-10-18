import Foundation
import AppKit

// MARK: - Wheel Modes & Slice Items (Tangerine UX)

enum WheelMode: String, CaseIterable, Identifiable {
    case convert = "convert"   // ⇧ Shift: Format Dönüştür
    case tools   = "tools"     // ⌘ Command: Gelişmiş Dosya Araçları
    case actions = "actions"   // ⌃ Control: Dosya İşlemleri

    var id: String { rawValue }

    var title: String {
        switch self {
        case .convert: return "Dönüştür"
        case .tools:   return "Araçlar"
        case .actions: return "İşlemler"
        }
    }

    var keySymbol: String {
        switch self {
        case .convert: return "⇧"
        case .tools:   return "⌘"
        case .actions: return "⌃"
        }
    }

    var keyName: String {
        switch self {
        case .convert: return "shift"
        case .tools:   return "command"
        case .actions: return "control"
        }
    }

    var accentColor: NSColor {
        switch self {
        case .convert: return NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.12, alpha: 1.0) // Tangerine Orange
        case .tools:   return NSColor(calibratedRed: 0.16, green: 0.52, blue: 0.96, alpha: 1.0) // Royal Blue
        case .actions: return NSColor(calibratedRed: 0.18, green: 0.72, blue: 0.48, alpha: 1.0) // Emerald Green
        }
    }
}

enum ConversionAction: Equatable {
    // Convert formats (⇧ Shift)
    case toPDF
    case toDOCX
    case toUDF
    case toTIFF
    case toJPG
    case toPNG
    case toHTML
    case toTXT
    case toMarkdown
    case toRTF
    case ocrToUDF
    case ocrToDOCX

    // Advanced File Tools (⌘ Command)
    case compressUYAP        // UYAP Boyut Sıkıştırma (<5MB)
    case mergeToPDF          // Tümünü Tek PDF'te Birleştir
    case splitPages          // Sayfaları Böl (PDF / Çok Sayfalı TIFF)
    case ocrExtractText      // Türkçe OCR ile Metin Çıkar (.txt)
    case inspectUDF          // E-İmza & UDF Evrak Doğrulama
    case rotate90            // 90° Saat Yönünde Döndür

    // File Actions (⌃ Control)
    case quickPreview        // Uygulama İçi UDF / TIFF Önizleyici
    case copyTextToClipboard // İçerik Metnini Panoya Kopyala
    case revealInFinder      // Finder'da Göster
    case copyFilePath        // Dosya Yolunu Kopyala
    case shareAirDrop        // AirDrop / Paylaş
}

struct WheelSlice: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let iconName: String
    let badgeText: String
    let action: ConversionAction
}

// MARK: - File Category Detection

enum FileCategory: String, CaseIterable, Identifiable {
    case udf = "UDF (UYAP)"
    case tiff = "TIFF (Çok Sayfalı)"
    case pdf = "PDF"
    case word = "Word (DOCX)"
    case image = "Görsel"
    case text = "Metin / Markdown"
    case mixed = "Çoklu Dosya"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .udf:   return "doc.badge.gearshape.fill"
        case .tiff:  return "square.stack.3d.down.right.fill"
        case .pdf:   return "doc.richtext.fill"
        case .word:  return "doc.text.fill"
        case .image: return "photo.on.rectangle.angled"
        case .text:  return "text.alignleft"
        case .mixed: return "square.on.square.dashed"
        }
    }

    static func detect(from urls: [URL]) -> FileCategory {
        guard let first = urls.first else { return .udf }
        let exts = Set(urls.map { $0.pathExtension.lowercased() })
        if exts.count > 1 {
            // Check if all are images/tiff
            let imageExts: Set<String> = ["tif", "tiff", "jpg", "jpeg", "png", "heic", "webp", "bmp"]
            if exts.isSubset(of: imageExts) {
                return exts.contains("tif") || exts.contains("tiff") ? .tiff : .image
            }
            return .mixed
        }
        let ext = first.pathExtension.lowercased()
        switch ext {
        case "udf":
            return .udf
        case "tif", "tiff":
            return .tiff
        case "pdf":
            return .pdf
        case "docx", "doc", "rtf":
            return .word
        case "jpg", "jpeg", "png", "heic", "webp", "bmp", "gif":
            return .image
        case "txt", "md", "html":
            return .text
        default:
            return .mixed
        }
    }

    static func slices(for urls: [URL], mode: WheelMode) -> [WheelSlice] {
        let category = detect(from: urls)
        switch mode {
        case .convert:
            switch category {
            case .udf:
                return [
                    WheelSlice(id: "pdf", title: "PDF", subtitle: "UDF → A4 PDF Belgesi", iconName: "doc.richtext.fill", badgeText: "PDF", action: .toPDF),
                    WheelSlice(id: "docx", title: "DOCX", subtitle: "UDF → Microsoft Word", iconName: "doc.text.fill", badgeText: "WORD", action: .toDOCX),
                    WheelSlice(id: "tiff", title: "TIFF", subtitle: "UDF → Çok Sayfalı TIFF", iconName: "square.stack.3d.down.right.fill", badgeText: "TIFF", action: .toTIFF),
                    WheelSlice(id: "html", title: "HTML", subtitle: "UDF → Web Görünümü", iconName: "globe", badgeText: "HTML", action: .toHTML),
                    WheelSlice(id: "txt", title: "TXT", subtitle: "UDF → Düz Metin", iconName: "doc.plaintext", badgeText: "TXT", action: .toTXT),
                    WheelSlice(id: "md", title: "MD", subtitle: "UDF → Markdown", iconName: "text.Hash", badgeText: "MD", action: .toMarkdown),
                    WheelSlice(id: "rtf", title: "RTF", subtitle: "UDF → Zengin Metin", iconName: "doc.append", badgeText: "RTF", action: .toRTF)
                ]
            case .tiff:
                return [
                    WheelSlice(id: "pdf", title: "PDF", subtitle: "Çok Sayfalı TIFF → PDF", iconName: "doc.richtext.fill", badgeText: "PDF", action: .toPDF),
                    WheelSlice(id: "ocr_udf", title: "UDF (OCR)", subtitle: "Taranmış TIFF → UYAP UDF", iconName: "doc.badge.gearshape.fill", badgeText: "UDF", action: .ocrToUDF),
                    WheelSlice(id: "ocr_docx", title: "DOCX (OCR)", subtitle: "Taranmış TIFF → Word", iconName: "doc.text.fill", badgeText: "WORD", action: .ocrToDOCX),
                    WheelSlice(id: "jpg", title: "JPG", subtitle: "TIFF Sayfaları → JPG", iconName: "photo", badgeText: "JPG", action: .toJPG),
                    WheelSlice(id: "png", title: "PNG", subtitle: "TIFF Sayfaları → PNG", iconName: "photo.fill", badgeText: "PNG", action: .toPNG),
                    WheelSlice(id: "txt", title: "TXT (OCR)", subtitle: "TIFF → Metin Çıkar", iconName: "text.viewfinder", badgeText: "TXT", action: .ocrExtractText)
                ]
            case .pdf:
                return [
                    WheelSlice(id: "udf", title: "UDF", subtitle: "PDF → UYAP (.udf)", iconName: "doc.badge.gearshape.fill", badgeText: "UDF", action: .toUDF),
                    WheelSlice(id: "docx", title: "DOCX", subtitle: "PDF → Microsoft Word", iconName: "doc.text.fill", badgeText: "WORD", action: .toDOCX),
                    WheelSlice(id: "tiff", title: "TIFF", subtitle: "PDF → Çok Sayfalı TIFF", iconName: "square.stack.3d.down.right.fill", badgeText: "TIFF", action: .toTIFF),
                    WheelSlice(id: "jpg", title: "JPG", subtitle: "PDF → 300 DPI JPG", iconName: "photo", badgeText: "JPG", action: .toJPG),
                    WheelSlice(id: "png", title: "PNG", subtitle: "PDF → 300 DPI PNG", iconName: "photo.fill", badgeText: "PNG", action: .toPNG),
                    WheelSlice(id: "txt", title: "TXT", subtitle: "PDF → Düz Metin", iconName: "doc.plaintext", badgeText: "TXT", action: .toTXT),
                    WheelSlice(id: "md", title: "MD", subtitle: "PDF → Markdown", iconName: "number", badgeText: "MD", action: .toMarkdown)
                ]
            case .word:
                return [
                    WheelSlice(id: "udf", title: "UDF", subtitle: "Word → UYAP (.udf)", iconName: "doc.badge.gearshape.fill", badgeText: "UDF", action: .toUDF),
                    WheelSlice(id: "pdf", title: "PDF", subtitle: "Word → A4 PDF", iconName: "doc.richtext.fill", badgeText: "PDF", action: .toPDF),
                    WheelSlice(id: "tiff", title: "TIFF", subtitle: "Word → Çok Sayfalı TIFF", iconName: "square.stack.3d.down.right.fill", badgeText: "TIFF", action: .toTIFF),
                    WheelSlice(id: "html", title: "HTML", subtitle: "Word → HTML", iconName: "globe", badgeText: "HTML", action: .toHTML),
                    WheelSlice(id: "txt", title: "TXT", subtitle: "Word → Düz Metin", iconName: "doc.plaintext", badgeText: "TXT", action: .toTXT),
                    WheelSlice(id: "md", title: "MD", subtitle: "Word → Markdown", iconName: "number", badgeText: "MD", action: .toMarkdown)
                ]
            case .image:
                return [
                    WheelSlice(id: "pdf", title: "PDF", subtitle: "Görsel → A4 PDF", iconName: "doc.richtext.fill", badgeText: "PDF", action: .toPDF),
                    WheelSlice(id: "tiff", title: "TIFF", subtitle: "Görsel → Çok Sayfalı TIFF", iconName: "square.stack.3d.down.right.fill", badgeText: "TIFF", action: .toTIFF),
                    WheelSlice(id: "ocr_udf", title: "UDF (OCR)", subtitle: "Görsel Metni → UYAP UDF", iconName: "doc.badge.gearshape.fill", badgeText: "UDF", action: .ocrToUDF),
                    WheelSlice(id: "jpg", title: "JPG", subtitle: "Görsel → JPG", iconName: "photo", badgeText: "JPG", action: .toJPG),
                    WheelSlice(id: "png", title: "PNG", subtitle: "Görsel → PNG", iconName: "photo.fill", badgeText: "PNG", action: .toPNG),
                    WheelSlice(id: "ocr_docx", title: "DOCX (OCR)", subtitle: "Görsel Metni → Word", iconName: "doc.text.fill", badgeText: "WORD", action: .ocrToDOCX)
                ]
            case .text, .mixed:
                return [
                    WheelSlice(id: "pdf", title: "PDF", subtitle: "Dosyaları PDF'e Dönüştür", iconName: "doc.richtext.fill", badgeText: "PDF", action: .toPDF),
                    WheelSlice(id: "udf", title: "UDF", subtitle: "UYAP (.udf) Oluştur", iconName: "doc.badge.gearshape.fill", badgeText: "UDF", action: .toUDF),
                    WheelSlice(id: "docx", title: "DOCX", subtitle: "Word (.docx) Oluştur", iconName: "doc.text.fill", badgeText: "WORD", action: .toDOCX),
                    WheelSlice(id: "tiff", title: "TIFF", subtitle: "TIFF Oluştur", iconName: "square.stack.3d.down.right.fill", badgeText: "TIFF", action: .toTIFF),
                    WheelSlice(id: "txt", title: "TXT", subtitle: "Düz Metin Çıkar", iconName: "doc.plaintext", badgeText: "TXT", action: .toTXT)
                ]
            }

        case .tools:
            return [
                WheelSlice(id: "compress", title: "Sıkıştır", subtitle: "UYAP Boyut Küçültme (<5MB)", iconName: "arrow.down.right.and.arrow.up.left", badgeText: "UYAP", action: .compressUYAP),
                WheelSlice(id: "merge", title: "Birleştir", subtitle: "Tek PDF Belgesinde Birleştir", iconName: "doc.on.doc.fill", badgeText: "MERGE", action: .mergeToPDF),
                WheelSlice(id: "split", title: "Sayfa Böl", subtitle: "PDF / TIFF Sayfalarını Ayır", iconName: "scissors", badgeText: "BÖL", action: .splitPages),
                WheelSlice(id: "ocr", title: "Türkçe OCR", subtitle: "Taranmış Evraktan Metin Çıkar", iconName: "text.viewfinder", badgeText: "OCR", action: .ocrExtractText),
                WheelSlice(id: "inspect", title: "E-İmza / Bilgi", subtitle: "UDF İmza & Evrak Doğrulama", iconName: "checkmark.seal.fill", badgeText: "İMZA", action: .inspectUDF),
                WheelSlice(id: "rotate", title: "90° Döndür", subtitle: "Sayfa / Görsel Yönünü Çevir", iconName: "rotate.right.fill", badgeText: "90°", action: .rotate90)
            ]

        case .actions:
            return [
                WheelSlice(id: "preview", title: "Önizle", subtitle: "UDF / Çok Sayfalı TIFF Göster", iconName: "eye.fill", badgeText: "GÖR", action: .quickPreview),
                WheelSlice(id: "copy_text", title: "Metni Kopyala", subtitle: "Evrak Metnini Panoya Al", iconName: "doc.on.clipboard.fill", badgeText: "METİN", action: .copyTextToClipboard),
                WheelSlice(id: "reveal", title: "Finder'da Aç", subtitle: "Dosyayı Klasörde Göster", iconName: "folder.fill", badgeText: "FINDER", action: .revealInFinder),
                WheelSlice(id: "copy_path", title: "Yolu Kopyala", subtitle: "Dosya Yolunu Panoya Kopyala", iconName: "link", badgeText: "YOL", action: .copyFilePath),
                WheelSlice(id: "share", title: "Paylaş", subtitle: "AirDrop, Mail veya Mesajlar", iconName: "square.and.arrow.up.fill", badgeText: "PAYLAŞ", action: .shareAirDrop)
            ]
        }
    }
}

// MARK: - UDF Document Models

struct UDFStyle {
    var name: String
    var family: String = "Times New Roman"
    var size: CGFloat = 12.0
    var bold: Bool = false
    var italic: Bool = false
    var underline: Bool = false
    var foreground: Int? = nil
}

struct UDFRun {
    var text: String
    var bold: Bool = false
    var italic: Bool = false
    var underline: Bool = false
    var family: String = "Times New Roman"
    var size: CGFloat = 12.0
    var foreground: Int? = nil
    var isField: Bool = false
    var fieldName: String? = nil
    var isImage: Bool = false
    var imageDataBase64: String? = nil
    var isTab: Bool = false
    var isSpace: Bool = false

    var hexColor: String? {
        guard let fg = foreground else { return nil }
        let unsigned = UInt32(bitPattern: Int32(truncatingIfNeeded: fg))
        let r = (unsigned >> 16) & 0xFF
        let g = (unsigned >> 8) & 0xFF
        let b = unsigned & 0xFF
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    var nsColor: NSColor? {
        guard let fg = foreground else { return nil }
        let unsigned = UInt32(bitPattern: Int32(truncatingIfNeeded: fg))
        let r = CGFloat((unsigned >> 16) & 0xFF) / 255.0
        let g = CGFloat((unsigned >> 8) & 0xFF) / 255.0
        let b = CGFloat(unsigned & 0xFF) / 255.0
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1.0)
    }
}

struct UDFParagraph {
    var alignment: Int = 0 // 0=Left, 1=Center, 2=Right, 3=Justify
    var leftIndent: CGFloat = 0
    var rightIndent: CGFloat = 0
    var firstLineIndent: CGFloat = 0
    var spaceAbove: CGFloat = 0
    var spaceBelow: CGFloat = 0
    var isNumbered: Bool = false
    var isBulleted: Bool = false
    var runs: [UDFRun] = []

    var plainText: String {
        runs.map { $0.text }.joined()
    }
}

struct UDFTableCell {
    var width: CGFloat? = nil
    var paragraphs: [UDFParagraph] = []

    var plainText: String {
        paragraphs.map { $0.plainText }.joined(separator: "\n")
    }
}

struct UDFTableRow {
    var height: CGFloat = 0
    var cells: [UDFTableCell] = []
}

struct UDFTable {
    var columnCount: Int = 1
    var rows: [UDFTableRow] = []
}

enum UDFElement {
    case paragraph(UDFParagraph)
    case table(UDFTable)
}

struct UDFPageFormat {
    var mediaSizeName: Int = 1
    var paperOrientation: Int = 1 // 1 = Portrait, 2 = Landscape
    var leftMargin: CGFloat = 70.875
    var rightMargin: CGFloat = 70.875
    var topMargin: CGFloat = 70.875
    var bottomMargin: CGFloat = 70.875
}

struct UDFSignatureInfo {
    var isSigned: Bool = false
    var signerName: String? = nil
    var organization: String? = nil
    var signingTime: String? = nil
    var rawBytesCount: Int = 0
}

struct UDFDocumentModel {
    var formatId: String = "1.8"
    var pageFormat: UDFPageFormat = UDFPageFormat()
    var verificationCode: String? = nil
    var registryNumber: String? = nil
    var signature: UDFSignatureInfo = UDFSignatureInfo()
    var elements: [UDFElement] = []
    var fields: [String: String] = [:]

    var paragraphs: [UDFParagraph] {
        elements.compactMap {
            if case .paragraph(let p) = $0 { return p }
            return nil
        }
    }

    var tables: [UDFTable] {
        elements.compactMap {
            if case .table(let t) = $0 { return t }
            return nil
        }
    }

    var plainText: String {
        var parts: [String] = []
        for el in elements {
            switch el {
            case .paragraph(let p):
                parts.append(p.plainText)
            case .table(let t):
                for r in t.rows {
                    parts.append(r.cells.map { $0.plainText }.joined(separator: "\t|\t"))
                }
            }
        }
        return parts.joined(separator: "\n")
    }
}

// MARK: - Conversion History Item

struct ConversionRecord: Identifiable {
    let id = UUID()
    let timestamp: Date
    let sourceURL: URL
    let outputURL: URL
    let actionTitle: String
    let detailMessage: String
    let isSuccess: Bool
}
