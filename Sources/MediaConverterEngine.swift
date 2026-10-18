import Foundation
import AppKit
import PDFKit
import ImageIO
import UniformTypeIdentifiers
import Vision

enum MediaEngineError: LocalizedError {
    case unreadableSource(String)
    case destinationCreationFailed(String)
    case emptyInput

    var errorDescription: String? {
        switch self {
        case .unreadableSource(let name): return "Kaynak dosya okunamadı: \(name)"
        case .destinationCreationFailed(let name): return "Çıktı dosyası oluşturulamadı: \(name)"
        case .emptyInput: return "İşlenecek dosya seçilmedi."
        }
    }
}

struct MediaConverterEngine {

    // MARK: - Unique Output URL Helper

    static func uniqueOutputURL(nextTo sourceURL: URL, newSuffix: String = "", newExtension: String) -> URL {
        let fm = FileManager.default
        let folder = sourceURL.deletingLastPathComponent()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let cleanExt = newExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))

        // If source already has the same extension and no suffix was provided, add "_donusturulen"
        let effectiveSuffix = (sourceURL.pathExtension.lowercased() == cleanExt.lowercased() && newSuffix.isEmpty) ? "_yeni" : newSuffix
        var candidate = folder.appendingPathComponent("\(baseName)\(effectiveSuffix).\(cleanExt)")
        var counter = 2
        while fm.fileExists(atPath: candidate.path) && candidate.path == sourceURL.path {
            candidate = folder.appendingPathComponent("\(baseName)\(effectiveSuffix)_\(counter).\(cleanExt)")
            counter += 1
        }
        return candidate
    }

    // MARK: - 1. Multi-page TIFF & Images -> PDF

    /// Reads all frames from one or more TIFF / image files and writes a single multi-page PDF.
    static func convertImagesOrTIFFToPDF(from urls: [URL], to destinationURL: URL) throws -> Int {
        var cgImages: [CGImage] = []
        for url in urls {
            let frames = try extractCGImages(from: url)
            cgImages.append(contentsOf: frames)
        }
        guard !cgImages.isEmpty else {
            throw MediaEngineError.unreadableSource(urls.first?.lastPathComponent ?? "Görsel")
        }

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
            throw MediaEngineError.destinationCreationFailed(destinationURL.lastPathComponent)
        }

        var defaultBox = CGRect(x: 0, y: 0, width: 595.28, height: 841.89) // A4
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &defaultBox, nil) else {
            throw MediaEngineError.destinationCreationFailed(destinationURL.lastPathComponent)
        }

        for img in cgImages {
            let imgW = CGFloat(img.width)
            let imgH = CGFloat(img.height)
            let isLandscape = imgW > imgH * 1.15
            let pageW: CGFloat = isLandscape ? 841.89 : 595.28
            let pageH: CGFloat = isLandscape ? 595.28 : 841.89

            var pageBox = CGRect(x: 0, y: 0, width: pageW, height: pageH)
            let pageInfo: [CFString: Any] = [
                kCGPDFContextMediaBox: Data(bytes: &pageBox, count: MemoryLayout<CGRect>.size)
            ]
            pdfContext.beginPDFPage(pageInfo as CFDictionary)

            // Fit image proportionally inside page with small margin (or full bleed if scanned document)
            let scale = min(pageW / imgW, pageH / imgH)
            let drawW = imgW * scale
            let drawH = imgH * scale
            let drawX = (pageW - drawW) / 2.0
            let drawY = (pageH - drawH) / 2.0

            pdfContext.interpolationQuality = .high
            pdfContext.draw(img, in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
            pdfContext.endPDFPage()
        }

        pdfContext.closePDF()
        try pdfData.write(to: destinationURL, options: .atomic)
        return cgImages.count
    }

    /// Extracts all CGImage frames from an image or multi-page TIFF file.
    static func extractCGImages(from url: URL) throws -> [CGImage] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw MediaEngineError.unreadableSource(url.lastPathComponent)
        }
        let count = CGImageSourceGetCount(source)
        var images: [CGImage] = []
        for i in 0..<count {
            if let cgImg = CGImageSourceCreateImageAtIndex(source, i, nil) {
                images.append(cgImg)
            }
        }
        if images.isEmpty, let nsImg = NSImage(contentsOf: url),
           let cgImg = nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            images.append(cgImg)
        }
        return images
    }

    // MARK: - 2. PDF / Images -> Multi-Page TIFF

    static func convertPDFToMultiPageTIFF(from pdfURL: URL, to destinationURL: URL, dpi: CGFloat = 200.0) throws -> Int {
        guard let pdfDoc = PDFDocument(url: pdfURL), pdfDoc.pageCount > 0 else {
            throw MediaEngineError.unreadableSource(pdfURL.lastPathComponent)
        }
        var pageImages: [CGImage] = []
        for i in 0..<pdfDoc.pageCount {
            if let page = pdfDoc.page(at: i), let cgImg = renderPDFPageToCGImage(page, dpi: dpi) {
                pageImages.append(cgImg)
            }
        }
        try writeMultiPageTIFF(images: pageImages, to: destinationURL)
        return pageImages.count
    }

    static func writeMultiPageTIFF(images: [CGImage], to destinationURL: URL) throws {
        guard !images.isEmpty else {
            throw MediaEngineError.emptyInput
        }
        guard let dest = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.tiff.identifier as CFString,
            images.count,
            nil
        ) else {
            throw MediaEngineError.destinationCreationFailed(destinationURL.lastPathComponent)
        }

        // Use LZW compression (5) so multi-page TIFF files remain compact and UYAP-friendly
        let tiffDict: [CFString: Any] = [
            kCGImagePropertyTIFFCompression: 5
        ]
        let frameProps: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: tiffDict
        ]

        for img in images {
            CGImageDestinationAddImage(dest, img, frameProps as CFDictionary)
        }

        if !CGImageDestinationFinalize(dest) {
            throw MediaEngineError.destinationCreationFailed(destinationURL.lastPathComponent)
        }
    }

    static func renderPDFPageToCGImage(_ page: PDFPage, dpi: CGFloat = 200.0) -> CGImage? {
        let pageRect = page.bounds(for: .mediaBox)
        let scale = dpi / 72.0
        let width = max(1, Int(pageRect.width * scale))
        let height = max(1, Int(pageRect.height * scale))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.saveGState()
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        ctx.restoreGState()

        return ctx.makeImage()
    }

    // MARK: - 3. Export Frames / PDF Pages to JPG or PNG

    static func exportCGImages(_ images: [CGImage], baseSourceURL: URL, utType: UTType, ext: String, quality: CGFloat = 0.88) throws -> [URL] {
        guard !images.isEmpty else { throw MediaEngineError.emptyInput }
        var written: [URL] = []

        if images.count == 1 {
            let outURL = uniqueOutputURL(nextTo: baseSourceURL, newExtension: ext)
            try writeSingleImage(images[0], to: outURL, utType: utType, quality: quality)
            written.append(outURL)
        } else {
            let folder = baseSourceURL.deletingLastPathComponent()
            let baseName = baseSourceURL.deletingPathExtension().lastPathComponent
            let outFolder = folder.appendingPathComponent("\(baseName)_\(ext.uppercased())_Sayfalar")
            try FileManager.default.createDirectory(at: outFolder, withIntermediateDirectories: true)

            for (idx, img) in images.enumerated() {
                let pageName = String(format: "%@_Sayfa_%02d.%@", baseName, idx + 1, ext)
                let pageURL = outFolder.appendingPathComponent(pageName)
                try writeSingleImage(img, to: pageURL, utType: utType, quality: quality)
                written.append(pageURL)
            }
        }
        return written
    }

    static func writeSingleImage(_ cgImage: CGImage, to url: URL, utType: UTType, quality: CGFloat = 0.88) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, utType.identifier as CFString, 1, nil) else {
            throw MediaEngineError.destinationCreationFailed(url.lastPathComponent)
        }
        let props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        if !CGImageDestinationFinalize(dest) {
            throw MediaEngineError.destinationCreationFailed(url.lastPathComponent)
        }
    }

    // MARK: - 4. Offline Turkish + English OCR via macOS Vision Framework

    static func performOCR(on url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        var images: [CGImage] = []

        if ext == "pdf" {
            guard let pdf = PDFDocument(url: url) else {
                throw MediaEngineError.unreadableSource(url.lastPathComponent)
            }
            for i in 0..<pdf.pageCount {
                if let page = pdf.page(at: i), let img = renderPDFPageToCGImage(page, dpi: 220) {
                    images.append(img)
                }
            }
        } else {
            images = try extractCGImages(from: url)
        }

        guard !images.isEmpty else {
            throw MediaEngineError.unreadableSource(url.lastPathComponent)
        }

        var pageTexts: [String] = []
        for (idx, cgImg) in images.enumerated() {
            var recognizedLines: [String] = []
            let request = VNRecognizeTextRequest { req, _ in
                guard let observations = req.results as? [VNRecognizedTextObservation] else { return }
                for obs in observations {
                    if let top = obs.topCandidates(1).first {
                        recognizedLines.append(top.string)
                    }
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["tr-TR", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImg, options: [:])
            try? handler.perform([request])

            if !recognizedLines.isEmpty {
                if images.count > 1 {
                    pageTexts.append("--- [Sayfa \(idx + 1)] ---\n" + recognizedLines.joined(separator: "\n"))
                } else {
                    pageTexts.append(recognizedLines.joined(separator: "\n"))
                }
            }
        }

        return pageTexts.joined(separator: "\n\n")
    }

    // MARK: - 5. UYAP Smart Compression (<5 MB Target)

    static func compressForUYAP(url: URL) throws -> (outputURL: URL, summary: String) {
        let origSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        let ext = url.pathExtension.lowercased()

        if ext == "pdf" {
            guard let pdf = PDFDocument(url: url), pdf.pageCount > 0 else {
                throw MediaEngineError.unreadableSource(url.lastPathComponent)
            }
            let outURL = uniqueOutputURL(nextTo: url, newSuffix: "_sikistirilmis", newExtension: "pdf")

            let compressedDoc = PDFDocument()
            for i in 0..<pdf.pageCount {
                guard let page = pdf.page(at: i),
                      let cgImg = renderPDFPageToCGImage(page, dpi: 120) else { continue }
                let nsImg = NSImage(cgImage: cgImg, size: page.bounds(for: .mediaBox).size)
                if let newPage = PDFPage(
                    image: nsImg,
                    options: [
                        .compressionQuality: 0.45,
                        .mediaBox: page.bounds(for: .mediaBox)
                    ]
                ) {
                    compressedDoc.insert(newPage, at: compressedDoc.pageCount)
                }
            }

            compressedDoc.write(to: outURL)
            var newSize = (try? FileManager.default.attributesOfItem(atPath: outURL.path)[.size] as? Int64) ?? 0

            // If original PDF was already a compact vector PDF smaller than rasterized version, keep compact vector copy
            if newSize >= origSize, let compactData = pdf.dataRepresentation() {
                try compactData.write(to: outURL, options: .atomic)
                newSize = Int64(compactData.count)
            }
            return (outURL, formatSizeComparison(before: origSize, after: newSize))
        } else if ["tif", "tiff", "jpg", "jpeg", "png", "heic", "bmp"].contains(ext) {
            let images = try extractCGImages(from: url)
            if ext == "tif" || ext == "tiff" {
                let outURL = uniqueOutputURL(nextTo: url, newSuffix: "_sikistirilmis", newExtension: "pdf")
                let compressedDoc = PDFDocument()
                for img in images {
                    let nsImg = NSImage(cgImage: img, size: NSSize(width: 595, height: 842))
                    if let newPage = PDFPage(
                        image: nsImg,
                        options: [
                            .compressionQuality: 0.48,
                            .mediaBox: CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
                        ]
                    ) {
                        compressedDoc.insert(newPage, at: compressedDoc.pageCount)
                    }
                }
                compressedDoc.write(to: outURL)
                let newSize = (try? FileManager.default.attributesOfItem(atPath: outURL.path)[.size] as? Int64) ?? 0
                return (outURL, formatSizeComparison(before: origSize, after: newSize))
            } else {
                let outURL = uniqueOutputURL(nextTo: url, newSuffix: "_sikistirilmis", newExtension: "jpg")
                try writeSingleImage(images[0], to: outURL, utType: .jpeg, quality: 0.65)
                let newSize = (try? FileManager.default.attributesOfItem(atPath: outURL.path)[.size] as? Int64) ?? 0
                return (outURL, formatSizeComparison(before: origSize, after: newSize))
            }
        } else if ext == "udf" {
            let doc = try UDFEngine.readUDF(from: url)
            let outURL = uniqueOutputURL(nextTo: url, newSuffix: "_sikistirilmis", newExtension: "udf")
            try UDFEngine.writeUDF(doc, to: outURL)
            let newSize = (try? FileManager.default.attributesOfItem(atPath: outURL.path)[.size] as? Int64) ?? 0
            return (outURL, formatSizeComparison(before: origSize, after: newSize))
        } else {
            throw MediaEngineError.unreadableSource(url.lastPathComponent)
        }
    }

    private static func formatSizeComparison(before: Int64, after: Int64) -> String {
        let fmt = ByteCountFormatter()
        fmt.countStyle = .file
        let bStr = fmt.string(fromByteCount: before)
        let aStr = fmt.string(fromByteCount: after)
        if before > 0 && after < before {
            let pct = Int(((Double(before - after) / Double(before)) * 100.0).rounded())
            return "\(bStr) → \(aStr) (%\(pct) küçüldü)"
        }
        return "\(bStr) → \(aStr)"
    }

    // MARK: - 6. Merge Any Combination of Files (UDF, TIFF, PDF, DOCX, Images) -> Single PDF

    static func mergeFilesToPDF(urls: [URL], to destinationURL: URL) throws -> Int {
        let masterPDF = PDFDocument()
        var totalPages = 0
        let fm = FileManager.default

        for url in urls {
            let ext = url.pathExtension.lowercased()
            let tempPDFURL = fm.temporaryDirectory.appendingPathComponent("merge_part_\(UUID().uuidString).pdf")
            defer { try? fm.removeItem(at: tempPDFURL) }

            let partPDF: PDFDocument?
            if ext == "pdf" {
                partPDF = PDFDocument(url: url)
            } else if ext == "udf" {
                let doc = try UDFEngine.readUDF(from: url)
                try UDFEngine.exportToPDF(doc, to: tempPDFURL)
                partPDF = PDFDocument(url: tempPDFURL)
            } else if ext == "docx" {
                let doc = try UDFEngine.importFromDOCX(url: url)
                try UDFEngine.exportToPDF(doc, to: tempPDFURL)
                partPDF = PDFDocument(url: tempPDFURL)
            } else if ["tif", "tiff", "jpg", "jpeg", "png", "heic", "webp", "bmp"].contains(ext) {
                _ = try convertImagesOrTIFFToPDF(from: [url], to: tempPDFURL)
                partPDF = PDFDocument(url: tempPDFURL)
            } else if let txt = try? String(contentsOf: url, encoding: .utf8) {
                let doc = UDFEngine.importFromText(txt)
                try UDFEngine.exportToPDF(doc, to: tempPDFURL)
                partPDF = PDFDocument(url: tempPDFURL)
            } else {
                partPDF = nil
            }

            if let validPDF = partPDF {
                for pIdx in 0..<validPDF.pageCount {
                    if let page = validPDF.page(at: pIdx) {
                        masterPDF.insert(page, at: totalPages)
                        totalPages += 1
                    }
                }
            }
        }

        guard totalPages > 0, masterPDF.write(to: destinationURL) else {
            throw MediaEngineError.destinationCreationFailed(destinationURL.lastPathComponent)
        }
        return totalPages
    }

    // MARK: - 7. Split Multi-Page PDF or Multi-Page TIFF

    static func splitPages(from url: URL) throws -> (folderURL: URL, count: Int) {
        let ext = url.pathExtension.lowercased()
        let parent = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let outFolder = parent.appendingPathComponent("\(baseName)_Sayfalar")
        try FileManager.default.createDirectory(at: outFolder, withIntermediateDirectories: true)

        if ext == "pdf" {
            guard let pdf = PDFDocument(url: url), pdf.pageCount > 0 else {
                throw MediaEngineError.unreadableSource(url.lastPathComponent)
            }
            for i in 0..<pdf.pageCount {
                if let page = pdf.page(at: i) {
                    let singleDoc = PDFDocument()
                    singleDoc.insert(page, at: 0)
                    let pageURL = outFolder.appendingPathComponent(String(format: "%@_Sayfa_%02d.pdf", baseName, i + 1))
                    singleDoc.write(to: pageURL)
                }
            }
            return (outFolder, pdf.pageCount)
        } else {
            let images = try extractCGImages(from: url)
            for (i, img) in images.enumerated() {
                let pageURL = outFolder.appendingPathComponent(String(format: "%@_Sayfa_%02d.pdf", baseName, i + 1))
                let tempImgURL = FileManager.default.temporaryDirectory.appendingPathComponent("split_\(UUID().uuidString).png")
                defer { try? FileManager.default.removeItem(at: tempImgURL) }
                try writeSingleImage(img, to: tempImgURL, utType: .png)
                _ = try convertImagesOrTIFFToPDF(from: [tempImgURL], to: pageURL)
            }
            return (outFolder, images.count)
        }
    }

    // MARK: - 8. Rotate 90° Clockwise

    static func rotate90Clockwise(url: URL) throws -> URL {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            guard let pdf = PDFDocument(url: url), pdf.pageCount > 0 else {
                throw MediaEngineError.unreadableSource(url.lastPathComponent)
            }
            for i in 0..<pdf.pageCount {
                if let page = pdf.page(at: i) {
                    page.rotation = (page.rotation + 90) % 360
                }
            }
            let outURL = uniqueOutputURL(nextTo: url, newSuffix: "_dondurulmus", newExtension: "pdf")
            pdf.write(to: outURL)
            return outURL
        } else {
            let frames = try extractCGImages(from: url)
            let rotated = frames.compactMap { rotateCGImage90Clockwise($0) }
            if ext == "tif" || ext == "tiff" {
                let outURL = uniqueOutputURL(nextTo: url, newSuffix: "_dondurulmus", newExtension: "tiff")
                try writeMultiPageTIFF(images: rotated, to: outURL)
                return outURL
            } else {
                let outURL = uniqueOutputURL(nextTo: url, newSuffix: "_dondurulmus", newExtension: ext.isEmpty ? "png" : ext)
                if let first = rotated.first {
                    let ut: UTType = (ext == "jpg" || ext == "jpeg") ? .jpeg : .png
                    try writeSingleImage(first, to: outURL, utType: ut)
                }
                return outURL
            }
        }
    }

    private static func rotateCGImage90Clockwise(_ image: CGImage) -> CGImage? {
        let newWidth = image.height
        let newHeight = image.width
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.translateBy(x: CGFloat(newWidth), y: 0)
        ctx.rotate(by: .pi / 2.0)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }

    // MARK: - 9. Master Conversion Dispatcher

    static func perform(action: ConversionAction, on urls: [URL]) throws -> [ConversionRecord] {
        guard let firstURL = urls.first else {
            throw MediaEngineError.emptyInput
        }

        // Multi-file special cases:
        // 1) Multiple TIFFs/images -> single PDF
        if action == .toPDF && urls.count > 1 {
            let imageExts: Set<String> = ["tif", "tiff", "jpg", "jpeg", "png", "heic", "webp", "bmp"]
            let allImages = urls.allSatisfy { imageExts.contains($0.pathExtension.lowercased()) }
            if allImages {
                let outURL = uniqueOutputURL(nextTo: firstURL, newSuffix: "_Birlestirilmis", newExtension: "pdf")
                let pageCount = try convertImagesOrTIFFToPDF(from: urls, to: outURL)
                return [ConversionRecord(
                    timestamp: Date(),
                    sourceURL: firstURL,
                    outputURL: outURL,
                    actionTitle: "Çoklu Görsel/TIFF → PDF",
                    detailMessage: "\(urls.count) dosya (\(pageCount) sayfa) tek PDF'e dönüştürüldü.",
                    isSuccess: true
                )]
            }
        }

        // 2) Merge to PDF tool
        if action == .mergeToPDF {
            let outURL = uniqueOutputURL(nextTo: firstURL, newSuffix: "_Birlesik", newExtension: "pdf")
            let pages = try mergeFilesToPDF(urls: urls, to: outURL)
            return [ConversionRecord(
                timestamp: Date(),
                sourceURL: firstURL,
                outputURL: outURL,
                actionTitle: "PDF Birleştir",
                detailMessage: "\(urls.count) evrak (\(pages) sayfa) birleştirildi.",
                isSuccess: true
            )]
        }

        var records: [ConversionRecord] = []
        for url in urls {
            let rec = try performSingle(action: action, on: url)
            records.append(rec)
        }
        return records
    }

    private static func performSingle(action: ConversionAction, on url: URL) throws -> ConversionRecord {
        let ext = url.pathExtension.lowercased()

        // Helper to load any document as UDFDocumentModel
        func loadAsUDFModel(_ fileURL: URL) throws -> UDFDocumentModel {
            let e = fileURL.pathExtension.lowercased()
            if e == "udf" {
                return try UDFEngine.readUDF(from: fileURL)
            } else if e == "docx" {
                return try UDFEngine.importFromDOCX(url: fileURL)
            } else if e == "pdf" {
                return try UDFEngine.importFromPDF(url: fileURL, ocrFallback: { try performOCR(on: $0) })
            } else if ["tif", "tiff", "jpg", "jpeg", "png", "heic", "webp", "bmp"].contains(e) {
                let ocrText = try performOCR(on: fileURL)
                return UDFEngine.importFromText(ocrText)
            } else if e == "rtf", let attr = try? NSAttributedString(url: fileURL, options: [:], documentAttributes: nil) {
                return UDFEngine.importFromText(attr.string)
            } else {
                let txt = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
                return UDFEngine.importFromText(txt)
            }
        }

        switch action {
        case .toPDF:
            let outURL = uniqueOutputURL(nextTo: url, newExtension: "pdf")
            if ["tif", "tiff", "jpg", "jpeg", "png", "heic", "webp", "bmp"].contains(ext) {
                let pages = try convertImagesOrTIFFToPDF(from: [url], to: outURL)
                return ConversionRecord(
                    timestamp: Date(),
                    sourceURL: url,
                    outputURL: outURL,
                    actionTitle: "\(ext.uppercased()) → PDF",
                    detailMessage: "\(pages) sayfa PDF'e çevrildi",
                    isSuccess: true
                )
            } else {
                let doc = try loadAsUDFModel(url)
                try UDFEngine.exportToPDF(doc, to: outURL)
                return ConversionRecord(
                    timestamp: Date(),
                    sourceURL: url,
                    outputURL: outURL,
                    actionTitle: "\(ext.uppercased()) → PDF",
                    detailMessage: "A4 PDF belgesi oluşturuldu",
                    isSuccess: true
                )
            }

        case .toDOCX, .ocrToDOCX:
            let outURL = uniqueOutputURL(nextTo: url, newExtension: "docx")
            let doc = try loadAsUDFModel(url)
            try UDFEngine.exportToDOCX(doc, to: outURL)
            return ConversionRecord(
                timestamp: Date(),
                sourceURL: url,
                outputURL: outURL,
                actionTitle: "\(ext.uppercased()) → Word (.docx)",
                detailMessage: "\(doc.paragraphs.count) paragraf, \(doc.tables.count) tablo aktarıldı",
                isSuccess: true
            )

        case .toUDF, .ocrToUDF:
            let outURL = uniqueOutputURL(nextTo: url, newExtension: "udf")
            let doc = try loadAsUDFModel(url)
            try UDFEngine.writeUDF(doc, to: outURL)
            return ConversionRecord(
                timestamp: Date(),
                sourceURL: url,
                outputURL: outURL,
                actionTitle: "\(ext.uppercased()) → UYAP (.udf)",
                detailMessage: "UYAP uyumlu .udf oluşturuldu",
                isSuccess: true
            )

        case .toTIFF:
            let outURL = uniqueOutputURL(nextTo: url, newExtension: "tiff")
            if ext == "pdf" {
                let pages = try convertPDFToMultiPageTIFF(from: url, to: outURL)
                return ConversionRecord(
                    timestamp: Date(),
                    sourceURL: url,
                    outputURL: outURL,
                    actionTitle: "PDF → Çok Sayfalı TIFF",
                    detailMessage: "\(pages) sayfalık TIFF oluşturuldu",
                    isSuccess: true
                )
            } else if ["jpg", "jpeg", "png", "heic", "webp", "bmp", "tif", "tiff"].contains(ext) {
                let imgs = try extractCGImages(from: url)
                try writeMultiPageTIFF(images: imgs, to: outURL)
                return ConversionRecord(
                    timestamp: Date(),
                    sourceURL: url,
                    outputURL: outURL,
                    actionTitle: "\(ext.uppercased()) → TIFF",
                    detailMessage: "\(imgs.count) kare TIFF oluşturuldu",
                    isSuccess: true
                )
            } else {
                // UDF / DOCX -> temp PDF -> Multi-page TIFF
                let tempPDF = FileManager.default.temporaryDirectory.appendingPathComponent("udf_tiff_\(UUID().uuidString).pdf")
                defer { try? FileManager.default.removeItem(at: tempPDF) }
                let doc = try loadAsUDFModel(url)
                try UDFEngine.exportToPDF(doc, to: tempPDF)
                let pages = try convertPDFToMultiPageTIFF(from: tempPDF, to: outURL)
                return ConversionRecord(
                    timestamp: Date(),
                    sourceURL: url,
                    outputURL: outURL,
                    actionTitle: "\(ext.uppercased()) → Çok Sayfalı TIFF",
                    detailMessage: "\(pages) sayfalık TIFF oluşturuldu",
                    isSuccess: true
                )
            }

        case .toJPG:
            let images: [CGImage]
            if ext == "pdf", let pdf = PDFDocument(url: url) {
                images = (0..<pdf.pageCount).compactMap { pdf.page(at: $0) }.compactMap { renderPDFPageToCGImage($0, dpi: 300) }
            } else {
                images = try extractCGImages(from: url)
            }
            let written = try exportCGImages(images, baseSourceURL: url, utType: .jpeg, ext: "jpg")
            let target = written.count == 1 ? written[0] : written[0].deletingLastPathComponent()
            return ConversionRecord(
                timestamp: Date(),
                sourceURL: url,
                outputURL: target,
                actionTitle: "\(ext.uppercased()) → JPG",
                detailMessage: "\(written.count) adet 300 DPI JPG oluşturuldu",
                isSuccess: true
            )

        case .toPNG:
            let images: [CGImage]
            if ext == "pdf", let pdf = PDFDocument(url: url) {
                images = (0..<pdf.pageCount).compactMap { pdf.page(at: $0) }.compactMap { renderPDFPageToCGImage($0, dpi: 300) }
            } else {
                images = try extractCGImages(from: url)
            }
            let written = try exportCGImages(images, baseSourceURL: url, utType: .png, ext: "png")
            let target = written.count == 1 ? written[0] : written[0].deletingLastPathComponent()
            return ConversionRecord(
                timestamp: Date(),
                sourceURL: url,
                outputURL: target,
                actionTitle: "\(ext.uppercased()) → PNG",
                detailMessage: "\(written.count) adet PNG oluşturuldu",
                isSuccess: true
            )

        case .toHTML:
            let outURL = uniqueOutputURL(nextTo: url, newExtension: "html")
            let doc = try loadAsUDFModel(url)
            let html = UDFEngine.toHTML(doc)
            try Data(html.utf8).write(to: outURL, options: .atomic)
            return ConversionRecord(
                timestamp: Date(),
                sourceURL: url,
                outputURL: outURL,
                actionTitle: "\(ext.uppercased()) → HTML",
                detailMessage: "Web görünümü (.html) kaydedildi",
                isSuccess: true
            )

        case .toTXT, .ocrExtractText:
            let outURL = uniqueOutputURL(nextTo: url, newExtension: "txt")
            let text: String
            if ["tif", "tiff", "jpg", "jpeg", "png", "heic", "webp", "bmp"].contains(ext) || action == .ocrExtractText {
                text = try performOCR(on: url)
            } else {
                let doc = try loadAsUDFModel(url)
                text = doc.plainText
            }
            try Data(text.utf8).write(to: outURL, options: .atomic)
            return ConversionRecord(
                timestamp: Date(),
                sourceURL: url,
                outputURL: outURL,
                actionTitle: action == .ocrExtractText ? "Türkçe OCR → TXT" : "\(ext.uppercased()) → TXT",
                detailMessage: "\(text.count) karakter metin çıkarıldı",
                isSuccess: true
            )

        case .toMarkdown:
            let outURL = uniqueOutputURL(nextTo: url, newExtension: "md")
            let doc = try loadAsUDFModel(url)
            let md = UDFEngine.toMarkdown(doc)
            try Data(md.utf8).write(to: outURL, options: .atomic)
            return ConversionRecord(
                timestamp: Date(),
                sourceURL: url,
                outputURL: outURL,
                actionTitle: "\(ext.uppercased()) → Markdown",
                detailMessage: "Markdown (.md) oluşturuldu",
                isSuccess: true
            )

        case .toRTF:
            let outURL = uniqueOutputURL(nextTo: url, newExtension: "rtf")
            let doc = try loadAsUDFModel(url)
            try UDFEngine.exportToRTF(doc, to: outURL)
            return ConversionRecord(
                timestamp: Date(),
                sourceURL: url,
                outputURL: outURL,
                actionTitle: "\(ext.uppercased()) → RTF",
                detailMessage: "Zengin metin (.rtf) oluşturuldu",
                isSuccess: true
            )

        case .compressUYAP:
            let res = try compressForUYAP(url: url)
            return ConversionRecord(
                timestamp: Date(),
                sourceURL: url,
                outputURL: res.outputURL,
                actionTitle: "UYAP Boyut Sıkıştırma",
                detailMessage: res.summary,
                isSuccess: true
            )

        case .splitPages:
            let res = try splitPages(from: url)
            return ConversionRecord(
                timestamp: Date(),
                sourceURL: url,
                outputURL: res.folderURL,
                actionTitle: "Sayfaları Böl",
                detailMessage: "\(res.count) sayfa ayrı dosyaya bölündü",
                isSuccess: true
            )

        case .rotate90:
            let outURL = try rotate90Clockwise(url: url)
            return ConversionRecord(
                timestamp: Date(),
                sourceURL: url,
                outputURL: outURL,
                actionTitle: "90° Döndür",
                detailMessage: "Sayfalar 90° saat yönünde döndürüldü",
                isSuccess: true
            )

        case .copyTextToClipboard:
            let doc = try loadAsUDFModel(url)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(doc.plainText, forType: .string)
            return ConversionRecord(
                timestamp: Date(),
                sourceURL: url,
                outputURL: url,
                actionTitle: "Metin Panoya Kopyalandı",
                detailMessage: "\(doc.plainText.count) karakter panoya alındı",
                isSuccess: true
            )

        case .copyFilePath:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
            return ConversionRecord(
                timestamp: Date(),
                sourceURL: url,
                outputURL: url,
                actionTitle: "Dosya Yolu Kopyalandı",
                detailMessage: url.path,
                isSuccess: true
            )

        case .revealInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return ConversionRecord(
                timestamp: Date(),
                sourceURL: url,
                outputURL: url,
                actionTitle: "Finder'da Gösterildi",
                detailMessage: url.lastPathComponent,
                isSuccess: true
            )

        case .quickPreview, .inspectUDF, .shareAirDrop, .mergeToPDF:
            return ConversionRecord(
                timestamp: Date(),
                sourceURL: url,
                outputURL: url,
                actionTitle: "İşlem Tamamlandı",
                detailMessage: url.lastPathComponent,
                isSuccess: true
            )
        }
    }
}
