import Foundation
import AppKit
import PDFKit

enum UDFEngineError: LocalizedError {
    case missingContentXML
    case invalidXML(String)
    case pdfRenderFailed
    case docxParseFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingContentXML: return "UDF arşivinde 'content.xml' bulunamadı."
        case .invalidXML(let msg): return "UDF XML yapısı okunamadı: \(msg)"
        case .pdfRenderFailed: return "PDF çıktısı oluşturulamadı."
        case .docxParseFailed(let msg): return "DOCX dosyası okunamadı: \(msg)"
        }
    }
}

struct UDFEngine {

    // MARK: - 1. Read .udf -> UDFDocumentModel

    static func readUDF(from url: URL) throws -> UDFDocumentModel {
        let entries = try ZipHelper.extractEntries(from: url)

        guard let contentEntry = entries.first(where: { $0.key.lowercased().hasSuffix("content.xml") }) else {
            throw UDFEngineError.missingContentXML
        }

        var doc = try parseContentXML(contentEntry.value)

        // Check documentproperties.xml
        if let propEntry = entries.first(where: {
            let lower = $0.key.lowercased()
            return lower.hasSuffix("documentproperties.xml") || lower.hasSuffix("properties.xml")
        }) {
            parseDocumentProperties(propEntry.value, into: &doc)
        }

        // Check sign.sgn / sign.p7s
        if let sigEntry = entries.first(where: {
            let lower = $0.key.lowercased()
            return lower.hasSuffix("sign.sgn") || lower.hasSuffix("sign.p7s")
        }) {
            doc.signature = parseSignature(sigEntry.value)
        }

        return doc
    }

    private static func parseDocumentProperties(_ data: Data, into doc: inout UDFDocumentModel) {
        guard let xmlDoc = try? XMLDocument(data: data, options: [.nodePreserveAll]),
              let root = xmlDoc.rootElement() else { return }
        for node in root.elements(forName: "entry") {
            let key = node.attribute(forName: "key")?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let val = node.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if key == "uyapdogrulamakodu", !val.isEmpty {
                doc.verificationCode = val
            } else if key == "uyapsicil", !val.isEmpty {
                doc.registryNumber = val
            }
        }
    }

    private static func parseSignature(_ data: Data) -> UDFSignatureInfo {
        var info = UDFSignatureInfo()
        info.isSigned = !data.isEmpty
        info.rawBytesCount = data.count

        // Extract readable UTF-8 sequences from PKCS#7 / ASN.1 DER bytes
        let asciiText = String(decoding: data, as: UTF8.self)
        let pattern = "[A-Za-zÇĞİÖŞÜçğıöşü0-9 .,/\\-:]{5,64}"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = asciiText as NSString
            let matches = regex.matches(in: asciiText, range: NSRange(location: 0, length: ns.length))
            let candidates = matches.map { ns.substring(with: $0.range).trimmingCharacters(in: .whitespacesAndNewlines) }
            // Look for common Turkish certificate issuer / signer hints
            for item in candidates {
                let upper = item.uppercased()
                if upper.contains("TUBITAK") || upper.contains("KAMU SM") || upper.contains("E-GUVEN") || upper.contains("TURKTRUST") || upper.contains("E-TUGRA") {
                    if info.organization == nil { info.organization = item }
                } else if item.count >= 6 && item.contains(" ") && !upper.contains("OBJECT") && !upper.contains("HTTP") {
                    if info.signerName == nil { info.signerName = item }
                }
            }
        }
        if info.signerName == nil {
            info.signerName = "E-İmzalı UYAP Belgesi"
        }
        return info
    }

    private static func parseContentXML(_ data: Data) throws -> UDFDocumentModel {
        let xmlString = String(decoding: data, as: UTF8.self)

        // Extract raw CDATA text directly to preserve exact character offsets
        var cdataText = ""
        if let startRange = xmlString.range(of: "<content><![CDATA["),
           let endRange = xmlString.range(of: "]]></content>", range: startRange.upperBound..<xmlString.endIndex) {
            cdataText = String(xmlString[startRange.upperBound..<endRange.lowerBound])
        }

        let xmlDoc: XMLDocument
        do {
            xmlDoc = try XMLDocument(data: data, options: [.nodePreserveAll])
        } catch {
            throw UDFEngineError.invalidXML(error.localizedDescription)
        }

        guard let root = xmlDoc.rootElement() else {
            throw UDFEngineError.invalidXML("Kök eleman bulunamadı.")
        }

        var doc = UDFDocumentModel()
        doc.formatId = root.attribute(forName: "format_id")?.stringValue ?? "1.8"

        // If cdataText wasn't matched by regex, try XML node
        if cdataText.isEmpty, let contentEl = root.elements(forName: "content").first {
            cdataText = contentEl.stringValue ?? ""
        }
        let finalNSCData = cdataText as NSString

        // 1. Parse styles
        var styles: [String: UDFStyle] = [:]
        if let stylesEl = root.elements(forName: "styles").first {
            for sNode in stylesEl.elements(forName: "style") {
                let name = sNode.attribute(forName: "name")?.stringValue ?? ""
                let family = sNode.attribute(forName: "family")?.stringValue ?? "Times New Roman"
                let size = CGFloat(Double(sNode.attribute(forName: "size")?.stringValue ?? "12.0") ?? 12.0)
                let bold = (sNode.attribute(forName: "bold")?.stringValue?.lowercased() == "true")
                let italic = (sNode.attribute(forName: "italic")?.stringValue?.lowercased() == "true")
                let underline = (sNode.attribute(forName: "underline")?.stringValue?.lowercased() == "true")
                let fg = Int(sNode.attribute(forName: "foreground")?.stringValue ?? "")
                styles[name] = UDFStyle(name: name, family: family, size: size, bold: bold, italic: italic, underline: underline, foreground: fg)
            }
        }

        // 2. Parse pageFormat
        if let propsEl = root.elements(forName: "properties").first,
           let pfNode = propsEl.elements(forName: "pageFormat").first {
            var pf = UDFPageFormat()
            pf.mediaSizeName = Int(pfNode.attribute(forName: "mediaSizeName")?.stringValue ?? "1") ?? 1
            pf.paperOrientation = Int(pfNode.attribute(forName: "paperOrientation")?.stringValue ?? "1") ?? 1
            pf.leftMargin = CGFloat(Double(pfNode.attribute(forName: "leftMargin")?.stringValue ?? "70.875") ?? 70.875)
            pf.rightMargin = CGFloat(Double(pfNode.attribute(forName: "rightMargin")?.stringValue ?? "70.875") ?? 70.875)
            pf.topMargin = CGFloat(Double(pfNode.attribute(forName: "topMargin")?.stringValue ?? "70.875") ?? 70.875)
            pf.bottomMargin = CGFloat(Double(pfNode.attribute(forName: "bottomMargin")?.stringValue ?? "70.875") ?? 70.875)
            doc.pageFormat = pf
        }

        // 3. Parse elements in exact document order
        if let elementsEl = root.elements(forName: "elements").first {
            let defaultResolver = elementsEl.attribute(forName: "resolver")?.stringValue ?? "hvl-default"
            for child in elementsEl.children ?? [] {
                guard let el = child as? XMLElement, let tag = el.name else { continue }
                if tag == "paragraph" {
                    let p = parseParagraphNode(el, cdata: finalNSCData, styles: styles, defaultResolver: defaultResolver, fields: &doc.fields)
                    doc.elements.append(.paragraph(p))
                } else if tag == "table" {
                    let t = parseTableNode(el, cdata: finalNSCData, styles: styles, defaultResolver: defaultResolver, fields: &doc.fields)
                    doc.elements.append(.table(t))
                }
            }
        }

        // Fallback if elements was empty but raw CDATA exists
        if doc.elements.isEmpty && finalNSCData.length > 0 {
            for line in cdataText.components(separatedBy: "\n") {
                let run = UDFRun(text: line)
                doc.elements.append(.paragraph(UDFParagraph(alignment: 0, runs: [run])))
            }
        }

        return doc
    }

    private static func sliceCData(_ cdata: NSString, start: Int, length: Int) -> String {
        guard start >= 0, length > 0, start < cdata.length else { return "" }
        let safeLength = min(length, cdata.length - start)
        return cdata.substring(with: NSRange(location: start, length: safeLength))
    }

    private static func parseParagraphNode(
        _ node: XMLElement,
        cdata: NSString,
        styles: [String: UDFStyle],
        defaultResolver: String,
        fields: inout [String: String]
    ) -> UDFParagraph {
        var p = UDFParagraph()
        p.alignment = Int(node.attribute(forName: "Alignment")?.stringValue ?? "0") ?? 0
        p.leftIndent = CGFloat(Double(node.attribute(forName: "LeftIndent")?.stringValue ?? "0") ?? 0)
        p.rightIndent = CGFloat(Double(node.attribute(forName: "RightIndent")?.stringValue ?? "0") ?? 0)
        p.firstLineIndent = CGFloat(Double(node.attribute(forName: "FirstLineIndent")?.stringValue ?? "0") ?? 0)
        p.spaceAbove = CGFloat(Double(node.attribute(forName: "SpaceAbove")?.stringValue ?? "0") ?? 0)
        p.spaceBelow = CGFloat(Double(node.attribute(forName: "SpaceBelow")?.stringValue ?? "0") ?? 0)
        p.isNumbered = (node.attribute(forName: "Numbered")?.stringValue?.lowercased() == "true")
        p.isBulleted = (node.attribute(forName: "Bulleted")?.stringValue?.lowercased() == "true")

        let resolver = node.attribute(forName: "resolver")?.stringValue ?? defaultResolver

        for child in node.children ?? [] {
            guard let cEl = child as? XMLElement, let tag = cEl.name else { continue }
            let startOff = Int(cEl.attribute(forName: "startOffset")?.stringValue ?? "0") ?? 0
            let len = Int(cEl.attribute(forName: "length")?.stringValue ?? "0") ?? 0
            let text = sliceCData(cdata, start: startOff, length: len)

            let runResolver = cEl.attribute(forName: "resolver")?.stringValue ?? resolver
            let inherited = styles[runResolver]

            let bold = cEl.attribute(forName: "bold")?.stringValue.map { $0.lowercased() == "true" } ?? (inherited?.bold ?? false)
            let italic = cEl.attribute(forName: "italic")?.stringValue.map { $0.lowercased() == "true" } ?? (inherited?.italic ?? false)
            let underline = cEl.attribute(forName: "underline")?.stringValue.map { $0.lowercased() == "true" } ?? (inherited?.underline ?? false)
            let family = cEl.attribute(forName: "family")?.stringValue ?? (inherited?.family ?? "Times New Roman")
            let size = cEl.attribute(forName: "size")?.stringValue.flatMap { Double($0) }.map { CGFloat($0) } ?? (inherited?.size ?? 12.0)
            let fg = cEl.attribute(forName: "foreground")?.stringValue.flatMap { Int($0) } ?? inherited?.foreground

            var run = UDFRun(
                text: text,
                bold: bold,
                italic: italic,
                underline: underline,
                family: family,
                size: size,
                foreground: fg
            )

            if tag == "field" {
                run.isField = true
                let fName = cEl.attribute(forName: "fieldName")?.stringValue ?? ""
                run.fieldName = fName
                if !fName.isEmpty && !text.isEmpty {
                    fields[fName] = text
                }
            } else if tag == "image" {
                run.isImage = true
                run.imageDataBase64 = cEl.attribute(forName: "imageData")?.stringValue
            } else if tag == "tab" {
                run.isTab = true
                if text.isEmpty { run.text = "\t" }
            } else if tag == "space" {
                run.isSpace = true
                if text.isEmpty { run.text = " " }
            }

            p.runs.append(run)
        }

        return p
    }

    private static func parseTableNode(
        _ node: XMLElement,
        cdata: NSString,
        styles: [String: UDFStyle],
        defaultResolver: String,
        fields: inout [String: String]
    ) -> UDFTable {
        var table = UDFTable()
        table.columnCount = Int(node.attribute(forName: "columnCount")?.stringValue ?? "1") ?? 1

        for rowNode in node.elements(forName: "row") {
            var row = UDFTableRow()
            row.height = CGFloat(Double(rowNode.attribute(forName: "height")?.stringValue ?? "0") ?? 0)
            for cellNode in rowNode.elements(forName: "cell") {
                var cell = UDFTableCell()
                if let wStr = cellNode.attribute(forName: "width")?.stringValue, let w = Double(wStr) {
                    cell.width = CGFloat(w)
                }
                for pNode in cellNode.elements(forName: "paragraph") {
                    let p = parseParagraphNode(pNode, cdata: cdata, styles: styles, defaultResolver: defaultResolver, fields: &fields)
                    cell.paragraphs.append(p)
                }
                row.cells.append(cell)
            }
            table.rows.append(row)
        }
        return table
    }

    // MARK: - 2. Write UDFDocumentModel -> .udf

    static func writeUDF(_ doc: UDFDocumentModel, to destinationURL: URL) throws {
        var cdataParts: [String] = []
        var elementsXMLParts: [String] = []
        var currentOffset = 0 // Measured in UTF-16 code units (NSString.length)

        func serializeParagraph(_ p: UDFParagraph) -> String {
            var runTags: [String] = []
            for r in p.runs {
                let nsText = r.text as NSString
                let textLen = nsText.length
                guard textLen > 0 else { continue }
                cdataParts.append(r.text)

                var attrs: [String] = [
                    "startOffset=\"\(currentOffset)\"",
                    "length=\"\(textLen)\""
                ]
                if r.bold { attrs.append("bold=\"true\"") }
                if r.italic { attrs.append("italic=\"true\"") }
                if r.underline { attrs.append("underline=\"true\"") }
                if !r.family.isEmpty && r.family != "Times New Roman" {
                    attrs.append("family=\"\(escapeXMLAttr(r.family))\"")
                }
                if Int(r.size) != 12 {
                    attrs.append("size=\"\(Int(r.size))\"")
                }
                if let fg = r.foreground {
                    attrs.append("foreground=\"\(fg)\"")
                }

                if r.isField, let fName = r.fieldName {
                    attrs.append("fieldName=\"\(escapeXMLAttr(fName))\"")
                    attrs.append("fieldType=\"1\"")
                    attrs.append("isList=\"false\"")
                    runTags.append("<field \(attrs.joined(separator: " ")) />")
                } else if r.isTab {
                    runTags.append("<tab \(attrs.joined(separator: " ")) />")
                } else if r.isSpace {
                    runTags.append("<space \(attrs.joined(separator: " ")) />")
                } else {
                    runTags.append("<content \(attrs.joined(separator: " ")) />")
                }

                currentOffset += textLen
            }

            // If paragraph had no runs, insert a newline in CDATA so empty lines are preserved
            if runTags.isEmpty {
                cdataParts.append("\n")
                let attrs = "startOffset=\"\(currentOffset)\" length=\"1\""
                runTags.append("<content \(attrs) />")
                currentOffset += 1
            } else if let lastPart = cdataParts.last, !lastPart.hasSuffix("\n") {
                cdataParts.append("\n")
                currentOffset += 1
            }

            var pAttrs: [String] = ["Alignment=\"\(p.alignment)\""]
            if p.firstLineIndent > 0 { pAttrs.append("FirstLineIndent=\"\(p.firstLineIndent)\"") }
            if p.leftIndent > 0 { pAttrs.append("LeftIndent=\"\(p.leftIndent)\"") }
            if p.rightIndent > 0 { pAttrs.append("RightIndent=\"\(p.rightIndent)\"") }
            if p.spaceAbove > 0 { pAttrs.append("SpaceAbove=\"\(p.spaceAbove)\"") }
            if p.spaceBelow > 0 { pAttrs.append("SpaceBelow=\"\(p.spaceBelow)\"") }
            if p.isNumbered {
                pAttrs.append("Numbered=\"true\"")
                pAttrs.append("NumberType=\"NUMBER_TYPE_NUMBER_DOT\"")
            }
            if p.isBulleted { pAttrs.append("Bulleted=\"true\"") }

            return "<paragraph \(pAttrs.joined(separator: " "))>\(runTags.joined())</paragraph>"
        }

        for el in doc.elements {
            switch el {
            case .paragraph(let p):
                elementsXMLParts.append(serializeParagraph(p))
            case .table(let t):
                var rowStrings: [String] = []
                for r in t.rows {
                    var cellStrings: [String] = []
                    for c in r.cells {
                        let cellPs = c.paragraphs.isEmpty ? [UDFParagraph()] : c.paragraphs
                        let cellPXML = cellPs.map { serializeParagraph($0) }.joined()
                        let wAttr = c.width != nil ? " width=\"\(c.width!)\"" : ""
                        cellStrings.append("<cell\(wAttr)>\(cellPXML)</cell>")
                    }
                    rowStrings.append("<row height=\"\(r.height)\" rowType=\"dataRow\">\(cellStrings.joined())</row>")
                }
                elementsXMLParts.append("<table border=\"borderCell\" columnCount=\"\(max(1, t.columnCount))\">\(rowStrings.joined())</table>")
            }
        }

        let fullCData = cdataParts.joined()
        let pf = doc.pageFormat
        let pageFormatXML = "<properties><pageFormat mediaSizeName=\"\(pf.mediaSizeName)\" leftMargin=\"\(pf.leftMargin)\" rightMargin=\"\(pf.rightMargin)\" topMargin=\"\(pf.topMargin)\" bottomMargin=\"\(pf.bottomMargin)\" paperOrientation=\"\(pf.paperOrientation)\" headerFOffset=\"20.0\" footerFOffset=\"20.0\" /></properties>"
        let stylesXML = "<styles><style name=\"default\" description=\"Geçerli\" family=\"Dialog\" size=\"12\" bold=\"false\" italic=\"false\" foreground=\"-13421773\" /><style name=\"hvl-default\" family=\"Times New Roman\" size=\"12\" description=\"Gövde\" /></styles>"

        let contentXML = """
        <?xml version="1.0" encoding="UTF-8" ?>
        <template format_id="\(doc.formatId)">
        <content><![CDATA[\(fullCData)]]></content>\(pageFormatXML)
        <elements resolver="hvl-default">
        \(elementsXMLParts.joined(separator: "\n"))
        </elements>
        \(stylesXML)
        </template>
        """

        var entries: [String: Data] = [
            "content.xml": Data(contentXML.utf8)
        ]

        if doc.verificationCode != nil || doc.registryNumber != nil {
            let propXML = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE properties SYSTEM "http://java.sun.com/dtd/properties.dtd">
            <properties>
            <entry key="uyapdogrulamakodu">\(escapeXML(doc.verificationCode ?? ""))</entry>
            <entry key="uyapsicil">\(escapeXML(doc.registryNumber ?? ""))</entry>
            </properties>
            """
            entries["documentproperties.xml"] = Data(propXML.utf8)
        }

        try ZipHelper.createArchive(entries: entries, at: destinationURL)
    }

    // MARK: - 3. Export UDFDocumentModel -> HTML, Markdown, TXT, RTF, PDF, DOCX

    static func toHTML(_ doc: UDFDocumentModel) -> String {
        var bodyParts: [String] = []

        if doc.signature.isSigned || doc.verificationCode != nil || doc.registryNumber != nil {
            var badges: [String] = []
            if doc.signature.isSigned {
                let signer = escapeXML(doc.signature.signerName ?? "E-İmzalı")
                badges.append("<span class=\"badge sign\">🔒 \(signer)</span>")
            }
            if let code = doc.verificationCode {
                badges.append("<span class=\"badge code\">📋 Doğrulama Kodu: \(escapeXML(code))</span>")
            }
            if let sicil = doc.registryNumber {
                badges.append("<span class=\"badge sicil\">🪪 Sicil: \(escapeXML(sicil))</span>")
            }
            bodyParts.append("<div class=\"udf-header-banner\">\(badges.joined(separator: " "))</div>")
        }

        func renderParagraphHTML(_ p: UDFParagraph) -> String {
            let alignCSS: String
            switch p.alignment {
            case 1: alignCSS = "center"
            case 2: alignCSS = "right"
            case 3: alignCSS = "justify"
            default: alignCSS = "left"
            }
            var styleParts = ["text-align: \(alignCSS);"]
            if p.leftIndent > 0 { styleParts.append("margin-left: \(p.leftIndent)pt;") }
            if p.rightIndent > 0 { styleParts.append("margin-right: \(p.rightIndent)pt;") }
            if p.firstLineIndent > 0 { styleParts.append("text-indent: \(p.firstLineIndent)pt;") }

            var runHTMLs: [String] = []
            for r in p.runs {
                if r.isImage, let b64 = r.imageDataBase64 {
                    runHTMLs.append("<img src=\"data:image/png;base64,\(b64)\" style=\"max-height:28px;vertical-align:middle;\" />")
                    continue
                }
                var escaped = escapeXML(r.text)
                    .replacingOccurrences(of: "\t", with: "&emsp;&emsp;")
                    .replacingOccurrences(of: "  ", with: "&nbsp;&nbsp;")
                    .replacingOccurrences(of: "\n", with: "")
                if r.bold { escaped = "<strong>\(escaped)</strong>" }
                if r.italic { escaped = "<em>\(escaped)</em>" }
                if r.underline { escaped = "<u>\(escaped)</u>" }

                var rStyles: [String] = [
                    "font-family: '\(escapeXMLAttr(r.family))', 'Times New Roman', serif;",
                    "font-size: \(r.size)pt;"
                ]
                if let hex = r.hexColor {
                    rStyles.append("color: \(hex);")
                }
                runHTMLs.append("<span style=\"\(rStyles.joined(separator: " "))\">\(escaped)</span>")
            }

            let joined = runHTMLs.joined()
            if joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "<p style=\"\(styleParts.joined(separator: " "))\">&nbsp;</p>"
            }
            let prefix = p.isBulleted ? "• " : ""
            return "<p style=\"\(styleParts.joined(separator: " "))\">\(prefix)\(joined)</p>"
        }

        for el in doc.elements {
            switch el {
            case .paragraph(let p):
                bodyParts.append(renderParagraphHTML(p))
            case .table(let t):
                var rowsHTML: [String] = ["<table class=\"udf-table\">"]
                for r in t.rows {
                    rowsHTML.append("<tr>")
                    for c in r.cells {
                        let cellContent = c.paragraphs.map { renderParagraphHTML($0) }.joined()
                        rowsHTML.append("<td>\(cellContent)</td>")
                    }
                    rowsHTML.append("</tr>")
                }
                rowsHTML.append("</table>")
                bodyParts.append(rowsHTML.joined(separator: "\n"))
            }
        }

        return """
        <!DOCTYPE html>
        <html lang="tr">
        <head>
        <meta charset="UTF-8">
        <title>UYAP Belgesi</title>
        <style>
          @page { size: A4; margin: 20mm; }
          body {
            font-family: 'Times New Roman', Times, serif;
            font-size: 12pt;
            line-height: 1.45;
            color: #111;
            background: #ffffff;
            margin: 0;
            padding: 0;
          }
          .udf-page {
            max-width: 210mm;
            margin: 0 auto;
            padding: 18mm 20mm;
            box-sizing: border-box;
          }
          .udf-header-banner {
            background: #f4f7fb;
            border-left: 4px solid #ff731f;
            padding: 8px 12px;
            margin-bottom: 18px;
            border-radius: 4px;
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            font-size: 9.5pt;
            color: #334155;
            display: flex;
            flex-wrap: wrap;
            gap: 14px;
          }
          p { margin: 4pt 0; }
          .udf-table {
            width: 100%;
            border-collapse: collapse;
            margin: 10pt 0;
          }
          .udf-table td {
            border: 1px solid #64748b;
            padding: 5pt 8pt;
            vertical-align: top;
          }
        </style>
        </head>
        <body>
        <div class="udf-page">
        \(bodyParts.joined(separator: "\n"))
        </div>
        </body>
        </html>
        """
    }

    static func toMarkdown(_ doc: UDFDocumentModel) -> String {
        var lines: [String] = []
        if doc.signature.isSigned || doc.verificationCode != nil {
            var meta: [String] = []
            if doc.signature.isSigned {
                meta.append("🔒 **E-İmza:** \(doc.signature.signerName ?? "İmzalı")")
            }
            if let code = doc.verificationCode {
                meta.append("📋 **Doğrulama Kodu:** `\(code)`")
            }
            if let sicil = doc.registryNumber {
                meta.append("🪪 **Sicil:** `\(sicil)`")
            }
            lines.append("> " + meta.joined(separator: " | "))
            lines.append("")
        }

        for el in doc.elements {
            switch el {
            case .paragraph(let p):
                var segs: [String] = []
                for r in p.runs {
                    let clean = r.text.replacingOccurrences(of: "\n", with: "")
                    guard !clean.isEmpty else { continue }
                    var formatted = clean
                    if r.bold && r.italic {
                        formatted = "***\(clean)***"
                    } else if r.bold {
                        formatted = "**\(clean)**"
                    } else if r.italic {
                        formatted = "*\(clean)*"
                    }
                    segs.append(formatted)
                }
                let line = segs.joined()
                if p.isBulleted {
                    lines.append("- \(line)")
                } else {
                    lines.append(line)
                }
            case .table(let t):
                lines.append("")
                for (rowIdx, r) in t.rows.enumerated() {
                    let cols = r.cells.map {
                        $0.plainText.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                    }
                    lines.append("| " + cols.joined(separator: " | ") + " |")
                    if rowIdx == 0 {
                        let sep = cols.map { _ in "---" }.joined(separator: " | ")
                        lines.append("| " + sep + " |")
                    }
                }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func toAttributedString(_ doc: UDFDocumentModel, includeBadge: Bool = true) -> NSAttributedString {
        let result = NSMutableAttributedString()

        if includeBadge && (doc.signature.isSigned || doc.verificationCode != nil || doc.registryNumber != nil) {
            var badgeText = ""
            if doc.signature.isSigned {
                badgeText += "🔒 E-İmza: \(doc.signature.signerName ?? "Onaylı")   "
            }
            if let code = doc.verificationCode {
                badgeText += "📋 Doğrulama: \(code)   "
            }
            if let sicil = doc.registryNumber {
                badgeText += "🪪 Sicil: \(sicil)"
            }
            badgeText += "\n\n"
            let badgeStyle = NSMutableParagraphStyle()
            badgeStyle.alignment = .left
            badgeStyle.paragraphSpacing = 8
            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: badgeStyle
            ]
            result.append(NSAttributedString(string: badgeText, attributes: badgeAttrs))
        }

        func appendParagraph(_ p: UDFParagraph, into target: NSMutableAttributedString, tableBlock: NSTextTableBlock? = nil) {
            let pStyle = NSMutableParagraphStyle()
            switch p.alignment {
            case 1: pStyle.alignment = .center
            case 2: pStyle.alignment = .right
            case 3: pStyle.alignment = .justified
            default: pStyle.alignment = .left
            }
            pStyle.headIndent = p.leftIndent
            pStyle.firstLineHeadIndent = p.leftIndent + p.firstLineIndent
            pStyle.paragraphSpacingBefore = max(2, p.spaceAbove)
            pStyle.paragraphSpacing = max(3, p.spaceBelow)
            pStyle.lineSpacing = 2.0
            if let tb = tableBlock {
                pStyle.textBlocks = [tb]
            }

            // Configure tab stops for legal petition alignment
            var tabs: [NSTextTab] = []
            for i in 1...12 {
                tabs.append(NSTextTab(textAlignment: .left, location: CGFloat(i) * 36.0, options: [:]))
            }
            pStyle.tabStops = tabs

            let paraAttrStr = NSMutableAttributedString()
            if p.isBulleted {
                paraAttrStr.append(NSAttributedString(string: "• ", attributes: [
                    .font: NSFont(name: "Times New Roman", size: 12) ?? NSFont.systemFont(ofSize: 12),
                    .paragraphStyle: pStyle
                ]))
            }

            for r in p.runs {
                var cleanText = r.text
                if cleanText.hasSuffix("\n") {
                    cleanText.removeLast()
                }
                guard !cleanText.isEmpty else { continue }

                var font = NSFont(name: r.family, size: r.size)
                    ?? NSFont(name: "Times New Roman", size: r.size)
                    ?? NSFont.systemFont(ofSize: r.size)
                if r.bold {
                    font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                }
                if r.italic {
                    font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                }

                var attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .paragraphStyle: pStyle,
                    .foregroundColor: r.nsColor ?? NSColor.black
                ]
                if r.underline {
                    attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                paraAttrStr.append(NSAttributedString(string: cleanText, attributes: attrs))
            }

            let newlineAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont(name: "Times New Roman", size: 12) ?? NSFont.systemFont(ofSize: 12),
                .paragraphStyle: pStyle
            ]
            paraAttrStr.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
            target.append(paraAttrStr)
        }

        for el in doc.elements {
            switch el {
            case .paragraph(let p):
                appendParagraph(p, into: result)
            case .table(let t):
                let nsTable = NSTextTable()
                let cols = max(1, t.columnCount)
                nsTable.numberOfColumns = cols
                nsTable.collapsesBorders = true
                nsTable.layoutAlgorithm = .automaticLayoutAlgorithm

                for (rIdx, row) in t.rows.enumerated() {
                    for (cIdx, cell) in row.cells.enumerated() {
                        let block = NSTextTableBlock(table: nsTable, startingRow: rIdx, rowSpan: 1, startingColumn: cIdx, columnSpan: 1)
                        block.setWidth(0.75, type: .absoluteValueType, for: .border)
                        block.setBorderColor(NSColor.gray)
                        block.setWidth(5.0, type: .absoluteValueType, for: .padding)
                        let cellPs = cell.paragraphs.isEmpty ? [UDFParagraph()] : cell.paragraphs
                        for cp in cellPs {
                            appendParagraph(cp, into: result, tableBlock: block)
                        }
                    }
                }
            }
        }

        return result
    }

    /// Renders a UDFDocumentModel into a multi-page A4 vector PDF at `destinationURL`.
    static func exportToPDF(_ doc: UDFDocumentModel, to destinationURL: URL) throws {
        let attrString = toAttributedString(doc, includeBadge: true)
        try renderAttributedStringToPDF(attrString, pageFormat: doc.pageFormat, to: destinationURL)
    }

    static func renderAttributedStringToPDF(_ attrString: NSAttributedString, pageFormat: UDFPageFormat = UDFPageFormat(), to destinationURL: URL) throws {
        let isLandscape = (pageFormat.paperOrientation == 2)
        let pageWidth: CGFloat = isLandscape ? 841.89 : 595.28
        let pageHeight: CGFloat = isLandscape ? 595.28 : 841.89

        let leftMargin = max(36, pageFormat.leftMargin)
        let rightMargin = max(36, pageFormat.rightMargin)
        let topMargin = max(36, pageFormat.topMargin)
        let bottomMargin = max(36, pageFormat.bottomMargin)

        let printableWidth = pageWidth - leftMargin - rightMargin
        let printableHeight = pageHeight - topMargin - bottomMargin

        let textStorage = NSTextStorage(attributedString: attrString)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        // Create page containers until all glyphs are laid out
        var textContainers: [NSTextContainer] = []
        var SafetyCounter = 0
        while SafetyCounter < 200 {
            SafetyCounter += 1
            let container = NSTextContainer(size: NSSize(width: printableWidth, height: printableHeight))
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            textContainers.append(container)

            let glyphRange = layoutManager.glyphRange(for: container)
            if glyphRange.location + glyphRange.length >= layoutManager.numberOfGlyphs {
                break
            }
        }

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
            throw UDFEngineError.pdfRenderFailed
        }

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw UDFEngineError.pdfRenderFailed
        }

        for container in textContainers {
            let glyphRange = layoutManager.glyphRange(for: container)
            if glyphRange.length == 0 && textContainers.count > 1 { continue }

            pdfContext.beginPDFPage(nil)
            pdfContext.saveGState()

            // Flip coordinate system for AppKit text drawing (top-left origin inside printable rect)
            pdfContext.translateBy(x: leftMargin, y: pageHeight - topMargin)
            pdfContext.scaleBy(x: 1.0, y: -1.0)

            let graphicsContext = NSGraphicsContext(cgContext: pdfContext, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext

            layoutManager.drawBackground(forGlyphRange: glyphRange, at: .zero)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)

            NSGraphicsContext.restoreGraphicsState()
            pdfContext.restoreGState()
            pdfContext.endPDFPage()
        }

        pdfContext.closePDF()
        try pdfData.write(to: destinationURL, options: .atomic)
    }

    static func exportToRTF(_ doc: UDFDocumentModel, to destinationURL: URL) throws {
        let attr = toAttributedString(doc, includeBadge: true)
        let rtfData = try attr.data(
            from: NSRange(location: 0, length: attr.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        try rtfData.write(to: destinationURL, options: .atomic)
    }

    /// Builds a standards-compliant Microsoft Word (.docx) OpenXML archive from `UDFDocumentModel` preserving paragraphs, alignments, fonts, bold/italic/underline, and tables.
    static func exportToDOCX(_ doc: UDFDocumentModel, to destinationURL: URL) throws {
        let contentTypesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
          <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
        </Types>
        """

        let rootRelsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """

        let docRelsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """

        let stylesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:docDefaults>
            <w:rPrDefault>
              <w:rPr>
                <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/>
                <w:sz w:val="24"/>
                <w:szCs w:val="24"/>
              </w:rPr>
            </w:rPrDefault>
          </w:docDefaults>
        </w:styles>
        """

        func buildParagraphXML(_ p: UDFParagraph) -> String {
            let jcVal: String
            switch p.alignment {
            case 1: jcVal = "center"
            case 2: jcVal = "right"
            case 3: jcVal = "both"
            default: jcVal = "left"
            }

            var pPrParts: [String] = ["<w:jc w:val=\"\(jcVal)\"/>"]
            let leftTwips = Int(p.leftIndent * 20)
            let rightTwips = Int(p.rightIndent * 20)
            let firstLineTwips = Int(p.firstLineIndent * 20)
            if leftTwips > 0 || rightTwips > 0 || firstLineTwips > 0 {
                pPrParts.append("<w:ind w:left=\"\(leftTwips)\" w:right=\"\(rightTwips)\" w:firstLine=\"\(firstLineTwips)\"/>")
            }
            let beforeTwips = max(40, Int(p.spaceAbove * 20))
            let afterTwips = max(60, Int(p.spaceBelow * 20))
            pPrParts.append("<w:spacing w:before=\"\(beforeTwips)\" w:after=\"\(afterTwips)\" w:line=\"276\" w:lineRule=\"auto\"/>")

            var runParts: [String] = []
            for r in p.runs {
                let clean = r.text.replacingOccurrences(of: "\n", with: "")
                guard !clean.isEmpty else { continue }

                var rPr: [String] = []
                let fName = escapeXMLAttr(r.family.isEmpty ? "Times New Roman" : r.family)
                rPr.append("<w:rFonts w:ascii=\"\(fName)\" w:hAnsi=\"\(fName)\" w:cs=\"\(fName)\"/>")
                if r.bold { rPr.append("<w:b/>") }
                if r.italic { rPr.append("<w:i/>") }
                if r.underline { rPr.append("<w:u w:val=\"single\"/>") }
                let halfPt = max(12, Int(r.size * 2))
                rPr.append("<w:sz w:val=\"\(halfPt)\"/><w:szCs w:val=\"\(halfPt)\"/>")
                if let hex = r.hexColor {
                    let cleanHex = hex.replacingOccurrences(of: "#", with: "")
                    rPr.append("<w:color w:val=\"\(cleanHex)\"/>")
                }

                // Split by tab so Word renders real <w:tab/> stops
                let segments = clean.components(separatedBy: "\t")
                var innerXML: [String] = []
                for (idx, seg) in segments.enumerated() {
                    if !seg.isEmpty {
                        innerXML.append("<w:t xml:space=\"preserve\">\(escapeXML(seg))</w:t>")
                    }
                    if idx < segments.count - 1 {
                        innerXML.append("<w:tab/>")
                    }
                }
                runParts.append("<w:r><w:rPr>\(rPr.joined())</w:rPr>\(innerXML.joined())</w:r>")
            }

            return "<w:p><w:pPr>\(pPrParts.joined())</w:pPr>\(runParts.joined())</w:p>"
        }

        var bodyElements: [String] = []
        for el in doc.elements {
            switch el {
            case .paragraph(let p):
                bodyElements.append(buildParagraphXML(p))
            case .table(let t):
                var tblXML: [String] = [
                    """
                    <w:tbl>
                      <w:tblPr>
                        <w:tblW w:w="5000" w:type="pct"/>
                        <w:tblBorders>
                          <w:top w:val="single" w:sz="4" w:space="0" w:color="64748B"/>
                          <w:left w:val="single" w:sz="4" w:space="0" w:color="64748B"/>
                          <w:bottom w:val="single" w:sz="4" w:space="0" w:color="64748B"/>
                          <w:right w:val="single" w:sz="4" w:space="0" w:color="64748B"/>
                          <w:insideH w:val="single" w:sz="4" w:space="0" w:color="64748B"/>
                          <w:insideV w:val="single" w:sz="4" w:space="0" w:color="64748B"/>
                        </w:tblBorders>
                      </w:tblPr>
                    """
                ]
                for r in t.rows {
                    tblXML.append("<w:tr>")
                    for c in r.cells {
                        let cellPs = c.paragraphs.isEmpty ? [UDFParagraph()] : c.paragraphs
                        let cellPXML = cellPs.map { buildParagraphXML($0) }.joined()
                        tblXML.append("<w:tc><w:tcPr><w:tcW w:w=\"0\" w:type=\"auto\"/></w:tcPr>\(cellPXML)</w:tc>")
                    }
                    tblXML.append("</w:tr>")
                }
                tblXML.append("</w:tbl>")
                bodyElements.append(tblXML.joined())
            }
        }

        let pf = doc.pageFormat
        let isLandscape = (pf.paperOrientation == 2)
        let pgW = isLandscape ? 16838 : 11906
        let pgH = isLandscape ? 11906 : 16838
        let orientAttr = isLandscape ? " w:orient=\"landscape\"" : ""
        let lMar = Int(pf.leftMargin * 20)
        let rMar = Int(pf.rightMargin * 20)
        let tMar = Int(pf.topMargin * 20)
        let bMar = Int(pf.bottomMargin * 20)

        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            \(bodyElements.joined(separator: "\n"))
            <w:sectPr>
              <w:pgSz w:w="\(pgW)" w:h="\(pgH)"\(orientAttr)/>
              <w:pgMar w:top="\(tMar)" w:right="\(rMar)" w:bottom="\(bMar)" w:left="\(lMar)" w:header="708" w:footer="708" w:gutter="0"/>
            </w:sectPr>
          </w:body>
        </w:document>
        """

        let entries: [String: Data] = [
            "[Content_Types].xml": Data(contentTypesXML.utf8),
            "_rels/.rels": Data(rootRelsXML.utf8),
            "word/_rels/document.xml.rels": Data(docRelsXML.utf8),
            "word/styles.xml": Data(stylesXML.utf8),
            "word/document.xml": Data(documentXML.utf8)
        ]

        try ZipHelper.createArchive(entries: entries, at: destinationURL)
    }

    // MARK: - 4. Import DOCX / PDF / TXT -> UDFDocumentModel

    static func importFromDOCX(url: URL) throws -> UDFDocumentModel {
        let entries = try ZipHelper.extractEntries(from: url)
        guard let docXMLData = entries["word/document.xml"] ?? entries.first(where: { $0.key.lowercased().hasSuffix("document.xml") })?.value else {
            throw UDFEngineError.docxParseFailed("word/document.xml bulunamadı.")
        }

        let xmlDoc = try XMLDocument(data: docXMLData, options: [.nodePreserveAll])
        guard let root = xmlDoc.rootElement() else {
            throw UDFEngineError.docxParseFailed("Boş XML ağacı.")
        }

        var doc = UDFDocumentModel()

        func localName(_ node: XMLNode) -> String {
            if let l = node.localName, !l.isEmpty { return l }
            let raw = node.name ?? ""
            return raw.components(separatedBy: ":").last ?? raw
        }

        func attrVal(_ el: XMLElement, _ name: String) -> String? {
            if let a = el.attribute(forName: "w:\(name)")?.stringValue { return a }
            if let a = el.attribute(forName: name)?.stringValue { return a }
            return el.attributes?.first(where: { localName($0) == name })?.stringValue
        }

        func parseDocxRun(_ rEl: XMLElement) -> UDFRun {
            var pieces: [String] = []
            var bold = false
            var italic = false
            var underline = false
            var family = "Times New Roman"
            var size: CGFloat = 12.0

            for child in rEl.children ?? [] {
                guard let cEl = child as? XMLElement else { continue }
                let tag = localName(cEl)
                if tag == "rPr" {
                    for prop in cEl.children ?? [] {
                        guard let pEl = prop as? XMLElement else { continue }
                        let pTag = localName(pEl)
                        if pTag == "b" {
                            let v = attrVal(pEl, "val")?.lowercased() ?? "true"
                            bold = (v != "false" && v != "0")
                        } else if pTag == "i" {
                            let v = attrVal(pEl, "val")?.lowercased() ?? "true"
                            italic = (v != "false" && v != "0")
                        } else if pTag == "u" {
                            let v = attrVal(pEl, "val")?.lowercased() ?? "single"
                            underline = (v != "none" && v != "false" && v != "0")
                        } else if pTag == "rFonts" {
                            if let f = attrVal(pEl, "ascii") ?? attrVal(pEl, "hAnsi") {
                                family = f
                            }
                        } else if pTag == "sz" {
                            if let s = attrVal(pEl, "val"), let d = Double(s) {
                                size = CGFloat(d / 2.0)
                            }
                        }
                    }
                } else if tag == "t" {
                    pieces.append(cEl.stringValue ?? "")
                } else if tag == "tab" {
                    pieces.append("\t")
                } else if tag == "br" {
                    pieces.append("\n")
                }
            }

            return UDFRun(
                text: pieces.joined(),
                bold: bold,
                italic: italic,
                underline: underline,
                family: family,
                size: size
            )
        }

        func parseDocxParagraph(_ pEl: XMLElement) -> UDFParagraph {
            var p = UDFParagraph()
            for child in pEl.children ?? [] {
                guard let cEl = child as? XMLElement else { continue }
                let tag = localName(cEl)
                if tag == "pPr" {
                    for prop in cEl.children ?? [] {
                        guard let prEl = prop as? XMLElement else { continue }
                        let prTag = localName(prEl)
                        if prTag == "jc" {
                            let v = attrVal(prEl, "val")?.lowercased() ?? "left"
                            if v == "center" || v == "centre" { p.alignment = 1 }
                            else if v == "right" { p.alignment = 2 }
                            else if v == "both" || v == "justify" { p.alignment = 3 }
                            else { p.alignment = 0 }
                        } else if prTag == "ind" {
                            if let l = attrVal(prEl, "left"), let d = Double(l) { p.leftIndent = CGFloat(d / 20.0) }
                            if let r = attrVal(prEl, "right"), let d = Double(r) { p.rightIndent = CGFloat(d / 20.0) }
                            if let fl = attrVal(prEl, "firstLine"), let d = Double(fl) { p.firstLineIndent = CGFloat(d / 20.0) }
                        } else if prTag == "numPr" {
                            p.isBulleted = true
                        }
                    }
                } else if tag == "r" {
                    let run = parseDocxRun(cEl)
                    if !run.text.isEmpty {
                        p.runs.append(run)
                    }
                } else if tag == "hyperlink" {
                    for sub in cEl.children ?? [] {
                        if let subEl = sub as? XMLElement, localName(subEl) == "r" {
                            let run = parseDocxRun(subEl)
                            if !run.text.isEmpty { p.runs.append(run) }
                        }
                    }
                }
            }
            return p
        }

        func parseDocxTable(_ tblEl: XMLElement) -> UDFTable {
            var table = UDFTable()
            for child in tblEl.children ?? [] {
                guard let trEl = child as? XMLElement, localName(trEl) == "tr" else { continue }
                var row = UDFTableRow()
                for tcNode in trEl.children ?? [] {
                    guard let tcEl = tcNode as? XMLElement, localName(tcEl) == "tc" else { continue }
                    var cell = UDFTableCell()
                    for pNode in tcEl.children ?? [] {
                        if let pEl = pNode as? XMLElement, localName(pEl) == "p" {
                            cell.paragraphs.append(parseDocxParagraph(pEl))
                        }
                    }
                    row.cells.append(cell)
                }
                if !row.cells.isEmpty {
                    table.rows.append(row)
                }
            }
            table.columnCount = table.rows.map { $0.cells.count }.max() ?? 1
            return table
        }

        let bodyNodes = root.children?.compactMap { $0 as? XMLElement }.first(where: { localName($0) == "body" }) ?? root
        for child in bodyNodes.children ?? [] {
            guard let el = child as? XMLElement else { continue }
            let tag = localName(el)
            if tag == "p" {
                doc.elements.append(.paragraph(parseDocxParagraph(el)))
            } else if tag == "tbl" {
                doc.elements.append(.table(parseDocxTable(el)))
            }
        }

        return doc
    }

    static func importFromText(_ text: String) -> UDFDocumentModel {
        var doc = UDFDocumentModel()
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            var align = 0
            var isBold = false
            let fontSize: CGFloat = 12.0

            // Smart Turkish legal petition heuristics
            let upper = trimmed.uppercased(with: Locale(identifier: "tr_TR"))
            if !trimmed.isEmpty && trimmed == upper && trimmed.count < 85 && (upper.contains("MAHKEMESİ") || upper.contains("MÜDÜRLÜĞÜ") || upper.contains("BAŞKANLIĞI") || upper.contains("SAVCILIĞI") || upper.contains("DAİRESİ") || upper.contains("KONU") == false && trimmed.count < 55) {
                if upper.contains("MAHKEMESİ") || upper.contains("MÜDÜRLÜĞÜ") || upper.contains("BAŞKANLIĞI") || upper.contains("SAVCILIĞI") || upper.contains("DAİRESİ") || upper.contains("AÇIKLAMALAR") || upper.contains("SONUÇ VE İSTEM") || upper.contains("NETİCE VE TALEP") {
                    align = 1
                    isBold = true
                }
            } else if trimmed.count > 65 {
                align = 3 // Justify body paragraphs
            }

            let run = UDFRun(text: line, bold: isBold, family: "Times New Roman", size: fontSize)
            doc.elements.append(.paragraph(UDFParagraph(alignment: align, runs: [run])))
        }
        return doc
    }

    static func importFromPDF(url: URL, ocrFallback: ((URL) throws -> String)? = nil) throws -> UDFDocumentModel {
        guard let pdf = PDFDocument(url: url) else {
            throw UDFEngineError.pdfRenderFailed
        }
        var extractedPages: [String] = []
        for i in 0..<pdf.pageCount {
            if let page = pdf.page(at: i), let str = page.string, !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                extractedPages.append(str)
            }
        }
        var fullText = extractedPages.joined(separator: "\n\n")
        if fullText.trimmingCharacters(in: .whitespacesAndNewlines).count < 20, let ocr = ocrFallback {
            fullText = (try? ocr(url)) ?? fullText
        }
        return importFromText(fullText)
    }

    // MARK: - XML Escaping Helpers

    private static func escapeXML(_ str: String) -> String {
        str
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeXMLAttr(_ str: String) -> String {
        escapeXML(str)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
