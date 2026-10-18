import Foundation
import AppKit

struct DemoFilesGenerator {

    static var demoDirectoryURL: URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let folder = docs.appendingPathComponent("Mandalina_Ornek_Dosyalar")
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func ensureSampleFilesExist() -> [URL] {
        let dir = demoDirectoryURL
        let udfURL = dir.appendingPathComponent("Ornek_Dava_Dilekcesi.udf")
        let tiffURL = dir.appendingPathComponent("Tebligat_3_Sayfa.tiff")
        let docxURL = dir.appendingPathComponent("Sozlesme_Taslagi.docx")
        let pdfURL = dir.appendingPathComponent("Bilirkisi_Raporu.pdf")

        if !FileManager.default.fileExists(atPath: udfURL.path) {
            try? createSampleUDF(at: udfURL)
        }
        if !FileManager.default.fileExists(atPath: tiffURL.path) {
            try? createSampleMultiPageTIFF(at: tiffURL)
        }
        if !FileManager.default.fileExists(atPath: docxURL.path),
           let doc = try? UDFEngine.readUDF(from: udfURL) {
            try? UDFEngine.exportToDOCX(doc, to: docxURL)
        }
        if !FileManager.default.fileExists(atPath: pdfURL.path),
           let doc = try? UDFEngine.readUDF(from: udfURL) {
            try? UDFEngine.exportToPDF(doc, to: pdfURL)
        }

        return [udfURL, tiffURL, docxURL, pdfURL].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func createSampleUDF(at url: URL) throws {
        var doc = UDFDocumentModel()
        doc.verificationCode = "TR-UYAP-2026-8841920"
        doc.registryNumber = "AB149283"
        doc.signature = UDFSignatureInfo(isSigned: true, signerName: "Av. Serkan Sayoğlu", organization: "TÜBİTAK Kamu SM", signingTime: "2026-10-18", rawBytesCount: 4096)

        // Heading
        doc.elements.append(.paragraph(UDFParagraph(alignment: 1, spaceBelow: 10, runs: [
            UDFRun(text: "İSTANBUL NÖBETÇİ ASLİYE TİCARET MAHKEMESİ BAŞKANLIĞINA", bold: true, size: 13)
        ])))

        // Parties
        let metaLines: [(String, String)] = [
            ("DAVACI\t\t: ", "Mandalina Teknoloji ve Yazılım A.Ş. (VKN: 6120948120)"),
            ("VEKİLİ\t\t: ", "Av. Serkan Sayoğlu - İstanbul Barosu"),
            ("DAVALI\t\t: ", "Örnek Lojistik ve Taşımacılık Tic. Ltd. Şti."),
            ("KONU\t\t: ", "Ticari satım sözleşmesinden kaynaklanan 245.000,00 TL alacağın tahsili talebidir."),
            ("HARCA ESAS DEĞER\t: ", "245.000,00 TL")
        ]
        for (lbl, val) in metaLines {
            doc.elements.append(.paragraph(UDFParagraph(alignment: 0, spaceBelow: 3, runs: [
                UDFRun(text: lbl, bold: true, size: 12),
                UDFRun(text: val, bold: false, size: 12)
            ])))
        }

        // Section Header
        doc.elements.append(.paragraph(UDFParagraph(alignment: 1, spaceAbove: 10, spaceBelow: 6, runs: [
            UDFRun(text: "AÇIKLAMALAR", bold: true, underline: true, size: 12)
        ])))

        let body1 = "1. Müvekkil şirket ile davalı şirket arasında 15.03.2026 tarihli Lojistik ve Yazılım Entegrasyon Sözleşmesi akdedilmiştir. Müvekkil şirket sözleşme kapsamındaki tüm edimlerini eksiksiz yerine getirerek faturalarını davalı yana tebliğ etmiştir."
        doc.elements.append(.paragraph(UDFParagraph(alignment: 3, firstLineIndent: 24, spaceBelow: 6, runs: [
            UDFRun(text: body1, size: 12)
        ])))

        let body2 = "2. Aşağıdaki tabloda detayları gösterilen fatura kalemlerine ilişkin davalı yan herhangi bir itirazda bulunmamış, ancak ihtarnameye rağmen ödeme de gerçekleştirmemiştir:"
        doc.elements.append(.paragraph(UDFParagraph(alignment: 3, firstLineIndent: 24, spaceBelow: 8, runs: [
            UDFRun(text: body2, size: 12)
        ])))

        // Table
        let table = UDFTable(columnCount: 3, rows: [
            UDFTableRow(height: 22, cells: [
                UDFTableCell(paragraphs: [UDFParagraph(alignment: 1, runs: [UDFRun(text: "Fatura No", bold: true)])]),
                UDFTableCell(paragraphs: [UDFParagraph(alignment: 1, runs: [UDFRun(text: "Vade Tarihi", bold: true)])]),
                UDFTableCell(paragraphs: [UDFParagraph(alignment: 1, runs: [UDFRun(text: "Tutar (TL)", bold: true)])])
            ]),
            UDFTableRow(height: 20, cells: [
                UDFTableCell(paragraphs: [UDFParagraph(alignment: 0, runs: [UDFRun(text: "MND-2026-00142")])]),
                UDFTableCell(paragraphs: [UDFParagraph(alignment: 1, runs: [UDFRun(text: "01.05.2026")])]),
                UDFTableCell(paragraphs: [UDFParagraph(alignment: 2, runs: [UDFRun(text: "145.000,00 TL")])])
            ]),
            UDFTableRow(height: 20, cells: [
                UDFTableCell(paragraphs: [UDFParagraph(alignment: 0, runs: [UDFRun(text: "MND-2026-00189")])]),
                UDFTableCell(paragraphs: [UDFParagraph(alignment: 1, runs: [UDFRun(text: "15.06.2026")])]),
                UDFTableCell(paragraphs: [UDFParagraph(alignment: 2, runs: [UDFRun(text: "100.000,00 TL")])])
            ]),
            UDFTableRow(height: 22, cells: [
                UDFTableCell(paragraphs: [UDFParagraph(alignment: 0, runs: [UDFRun(text: "TOPLAM ALACAK", bold: true)])]),
                UDFTableCell(paragraphs: [UDFParagraph(alignment: 1, runs: [UDFRun(text: "-")])]),
                UDFTableCell(paragraphs: [UDFParagraph(alignment: 2, runs: [UDFRun(text: "245.000,00 TL", bold: true)])])
            ])
        ])
        doc.elements.append(.table(table))

        doc.elements.append(.paragraph(UDFParagraph(alignment: 1, spaceAbove: 10, spaceBelow: 6, runs: [
            UDFRun(text: "SONUÇ VE İSTEM", bold: true, underline: true, size: 12)
        ])))

        let conclusion = "Yukarıda arz ve izah edilen nedenlerle; fazlaya ilişkin dava ve talep haklarımız saklı kalmak kaydıyla 245.000,00 TL asıl alacağın temerrüt tarihinden itibaren işleyecek avans faiziyle birlikte davalıdan tahsiline, yargılama giderleri ve vekalet ücretinin davalı yana yükletilmesine karar verilmesini vekaleten arz ve talep ederiz. 18.10.2026"
        doc.elements.append(.paragraph(UDFParagraph(alignment: 3, firstLineIndent: 24, spaceBelow: 16, runs: [
            UDFRun(text: conclusion, size: 12)
        ])))

        doc.elements.append(.paragraph(UDFParagraph(alignment: 2, runs: [
            UDFRun(text: "Davacı Vekili\nAv. Serkan Sayoğlu\n(E-İmzalıdır)", bold: true, size: 12)
        ])))

        try UDFEngine.writeUDF(doc, to: url)
    }

    static func createSampleMultiPageTIFF(at url: URL) throws {
        let pagesText = [
            "T.C.\nİSTANBUL 4. İCRA DAİRESİ\n2026/14920 ESAS\n\nTEBLİGAT MAZBATASI - SAYFA 1 / 3\n\nBorçlu şirkete gönderilen ödeme emri 12.09.2026 tarihinde elektronik tebligat adresi üzerinden tebliğ edilmiştir.\n\nBu belge çok sayfalı (Multi-Page) TIFF formatındadır. Mandalina ile tek hareketle çok sayfalı PDF, UYAP UDF (OCR) veya Word belgesine dönüştürebilirsiniz.",
            "T.C.\nİSTANBUL 4. İCRA DAİRESİ\n2026/14920 ESAS\n\nHACİZ TUTANAĞI EKİ - SAYFA 2 / 3\n\n1. 34 MND 2026 plakalı ticari araç kaydına UYAP üzerinden yakalama ve haciz şerhi işlenmiştir.\n2. Banka genel müdürlüklerine 89/1 haciz ihbarnamesi müzekkeresi gönderilmiştir.",
            "T.C.\nİSTANBUL 4. İCRA DAİRESİ\n2026/14920 ESAS\n\nKAPAK HESABI TABLOSU - SAYFA 3 / 3\n\nAsıl Alacak: 245.000,00 TL\nİşlemiş Faiz: 38.420,00 TL\nİcra Vekalet Ücreti: 39.200,00 TL\nTahsil Harcı: 11.147,50 TL\nTOPLAM BORÇ: 333.767,50 TL"
        ]

        var cgImages: [CGImage] = []
        let width = 1240
        let height = 1754 // ~150 DPI A4

        for (idx, text) in pagesText.enumerated() {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { continue }

            // White paper background
            ctx.setFillColor(CGColor(red: 0.99, green: 0.99, blue: 0.98, alpha: 1.0))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

            // Subtle page border
            ctx.setStrokeColor(CGColor(red: 0.80, green: 0.82, blue: 0.86, alpha: 1.0))
            ctx.setLineWidth(4)
            ctx.stroke(CGRect(x: 60, y: 60, width: width - 120, height: height - 120))

            // Draw text using NSGraphicsContext
            ctx.saveGState()
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1.0, y: -1.0)
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx

            let pStyle = NSMutableParagraphStyle()
            pStyle.alignment = .left
            pStyle.lineSpacing = 12

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont(name: "Times New Roman", size: 30) ?? NSFont.systemFont(ofSize: 30),
                .foregroundColor: NSColor.black,
                .paragraphStyle: pStyle
            ]
            let attrStr = NSAttributedString(string: text, attributes: attrs)
            attrStr.draw(in: CGRect(x: 120, y: 140, width: width - 240, height: height - 280))

            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 22),
                .foregroundColor: NSColor.darkGray
            ]
            let footer = "Çok Sayfalı TIFF Örneği — Sayfa \(idx + 1) / \(pagesText.count)" as NSString
            footer.draw(at: NSPoint(x: 120, y: height - 120), withAttributes: footerAttrs)

            NSGraphicsContext.restoreGraphicsState()
            ctx.restoreGState()

            if let cgImg = ctx.makeImage() {
                cgImages.append(cgImg)
            }
        }

        try MediaConverterEngine.writeMultiPageTIFF(images: cgImages, to: url)
    }
}
