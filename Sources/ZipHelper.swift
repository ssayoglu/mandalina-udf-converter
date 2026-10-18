import Foundation

enum ZipHelperError: LocalizedError {
    case extractionFailed(String)
    case archiveFailed(String)
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .extractionFailed(let msg): return "Arşiv açılamadı: \(msg)"
        case .archiveFailed(let msg): return "Arşiv oluşturulamadı: \(msg)"
        case .fileNotFound(let msg): return "Dosya bulunamadı: \(msg)"
        }
    }
}

struct ZipHelper {
    /// Extracts all files from a ZIP archive (e.g. .udf or .docx) into a temporary directory and returns a map of relative path -> Data.
    static func extractEntries(from archiveURL: URL) throws -> [String: Data] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: archiveURL.path) else {
            throw ZipHelperError.fileNotFound(archiveURL.lastPathComponent)
        }

        // Check if the file starts with 'PK' (ZIP header) or '<?xml' / '<template' (raw XML UDF)
        let rawData = try Data(contentsOf: archiveURL)
        if rawData.count >= 4 {
            let prefix = [UInt8](rawData.prefix(4))
            if prefix[0] != 0x50 || prefix[1] != 0x4B {
                // Might be raw XML content.xml saved with .udf extension
                if let str = String(data: rawData.prefix(256), encoding: .utf8),
                   (str.contains("<template") || str.contains("<?xml")) {
                    return ["content.xml": rawData]
                }
            }
        }

        let tempDir = fm.temporaryDirectory.appendingPathComponent("tangerine_unzip_\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-x", "-k", archiveURL.path, tempDir.path]
        let errPipe = Pipe()
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()

        if proc.terminationStatus != 0 {
            // Fallback to /usr/bin/unzip -q
            let unzipProc = Process()
            unzipProc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProc.arguments = ["-o", "-q", archiveURL.path, "-d", tempDir.path]
            try unzipProc.run()
            unzipProc.waitUntilExit()
        }

        var entries: [String: Data] = [:]
        if let enumerator = fm.enumerator(at: tempDir, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let fileURL as URL in enumerator {
                if let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]), vals.isRegularFile == true {
                    let relPath = fileURL.path.replacingOccurrences(of: tempDir.path + "/", with: "")
                    if let d = try? Data(contentsOf: fileURL) {
                        entries[relPath] = d
                    }
                }
            }
        }

        if entries.isEmpty {
            throw ZipHelperError.extractionFailed("Arşiv boş veya geçersiz ZIP yapısı.")
        }
        return entries
    }

    /// Creates a ZIP archive (.udf or .docx) at `destinationURL` from a dictionary of relative path -> Data.
    static func createArchive(entries: [String: Data], at destinationURL: URL) throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("tangerine_zip_\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        for (relPath, data) in entries {
            let targetURL = tempDir.appendingPathComponent(relPath)
            let parentDir = targetURL.deletingLastPathComponent()
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try data.write(to: targetURL)
        }

        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }

        // Use /usr/bin/zip -r -q so that paths are stored relative to tempDir root without __MACOSX resource forks
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.currentDirectoryURL = tempDir
        proc.arguments = ["-r", "-q", "-X", destinationURL.path, "."]
        let errPipe = Pipe()
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()

        if proc.terminationStatus != 0 || !fm.fileExists(atPath: destinationURL.path) {
            let errMsg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Bilinmeyen hata"
            throw ZipHelperError.archiveFailed(errMsg)
        }
    }
}
