import Foundation
import AppKit
import SwiftUI

final class DocumentPreviewViewModel: ObservableObject {
    let fileURL: URL
    let onTriggerAction: (ConversionAction, URL) -> Void

    @Published var udfDoc: UDFDocumentModel? = nil
    @Published var tiffFrames: [NSImage] = []
    @Published var currentFrameIndex: Int = 0
    @Published var errorText: String? = nil
    @Published var showInspector: Bool = false

    init(fileURL: URL, initialInspectTab: Bool, onTriggerAction: @escaping (ConversionAction, URL) -> Void) {
        self.fileURL = fileURL
        self.showInspector = initialInspectTab
        self.onTriggerAction = onTriggerAction
        loadFile()
    }

    func loadFile() {
        let ext = fileURL.pathExtension.lowercased()
        if ext == "udf" {
            do {
                udfDoc = try UDFEngine.readUDF(from: fileURL)
            } catch {
                errorText = error.localizedDescription
            }
        } else if ext == "docx" {
            do {
                udfDoc = try UDFEngine.importFromDOCX(url: fileURL)
            } catch {
                errorText = error.localizedDescription
            }
        } else {
            if let cgImgs = try? MediaConverterEngine.extractCGImages(from: fileURL), !cgImgs.isEmpty {
                tiffFrames = cgImgs.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
                currentFrameIndex = 0
            } else if let doc = try? UDFEngine.importFromPDF(url: fileURL) {
                udfDoc = doc
            } else {
                errorText = "Bu dosya türü için önizleme oluşturulamadı."
            }
        }
    }
}

final class DocumentPreviewWindowController: NSObject {
    static let shared = DocumentPreviewWindowController()
    private var window: NSWindow?

    func showPreview(for url: URL, inspectMode: Bool = false, onTriggerAction: @escaping (ConversionAction, URL) -> Void) {
        let vm = DocumentPreviewViewModel(
            fileURL: url,
            initialInspectTab: inspectMode,
            onTriggerAction: onTriggerAction
        )
        let contentView = DocumentPreviewRootView(vm: vm)

        if let existing = window {
            existing.contentView = NSHostingView(rootView: contentView)
            existing.title = "Mandalina Önizleme — \(url.lastPathComponent)"
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.center()
        win.title = "Mandalina Önizleme — \(url.lastPathComponent)"
        win.contentView = NSHostingView(rootView: contentView)
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }
}

struct DocumentPreviewRootView: View {
    @ObservedObject var vm: DocumentPreviewViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar
            HStack(spacing: 12) {
                Image(systemName: FileCategory.detect(from: [vm.fileURL]).iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.fileURL.lastPathComponent)
                        .font(.system(size: 14, weight: .bold))
                    Text(vm.fileURL.path)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if vm.udfDoc != nil {
                    Button {
                        vm.showInspector.toggle()
                    } label: {
                        Label("E-İmza & Künye", systemImage: "checkmark.seal.fill")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    vm.onTriggerAction(.toPDF, vm.fileURL)
                } label: {
                    Label("PDF'e Çevir", systemImage: "doc.richtext.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                if vm.fileURL.pathExtension.lowercased() == "udf" {
                    Button {
                        vm.onTriggerAction(.toDOCX, vm.fileURL)
                    } label: {
                        Label("Word (.docx)", systemImage: "doc.text.fill")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        vm.onTriggerAction(.toUDF, vm.fileURL)
                    } label: {
                        Label("UDF'ye Çevir", systemImage: "doc.badge.gearshape.fill")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if let doc = vm.udfDoc {
                // E-signature & Verification Banner
                if doc.signature.isSigned || doc.verificationCode != nil || vm.showInspector {
                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            Image(systemName: doc.signature.isSigned ? "lock.shield.fill" : "exclamationmark.shield")
                                .foregroundColor(doc.signature.isSigned ? .green : .secondary)
                            Text(doc.signature.isSigned ? "E-İmzalı: \(doc.signature.signerName ?? "Onaylı")" : "İmzasız UDF")
                                .font(.system(size: 12, weight: .semibold))
                        }

                        if let org = doc.signature.organization {
                            Text("• \(org)")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }

                        if let code = doc.verificationCode {
                            Text("📋 Doğrulama: \(code)")
                                .font(.system(size: 12, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12))
                                .cornerRadius(4)
                        }

                        if let sicil = doc.registryNumber {
                            Text("🪪 Sicil: \(sicil)")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                        Text("\(doc.paragraphs.count) Paragraf · \(doc.tables.count) Tablo")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.08))
                    Divider()
                }

                // Rich Attributed Text Viewer for UDF
                AttributedTextScrollView(attributedString: UDFEngine.toAttributedString(doc, includeBadge: false))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.underPageBackgroundColor))

            } else if !vm.tiffFrames.isEmpty {
                VStack(spacing: 0) {
                    if vm.tiffFrames.count > 1 {
                        HStack(spacing: 14) {
                            Button {
                                if vm.currentFrameIndex > 0 { vm.currentFrameIndex -= 1 }
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            .disabled(vm.currentFrameIndex == 0)

                            Text("Sayfa \(vm.currentFrameIndex + 1) / \(vm.tiffFrames.count) (Çok Sayfalı Görsel / TIFF)")
                                .font(.system(size: 12, weight: .semibold))

                            Button {
                                if vm.currentFrameIndex < vm.tiffFrames.count - 1 { vm.currentFrameIndex += 1 }
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .disabled(vm.currentFrameIndex >= vm.tiffFrames.count - 1)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(Color.secondary.opacity(0.1))
                        Divider()
                    }

                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: vm.tiffFrames[vm.currentFrameIndex])
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 740)
                            .padding(24)
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.underPageBackgroundColor))
                }
            } else if let err = vm.errorText {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.orange)
                    Text(err)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("Belge yükleniyor...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct AttributedTextScrollView: NSViewRepresentable {
    let attributedString: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .white
        textView.textContainerInset = NSSize(width: 44, height: 36)
        textView.textStorage?.setAttributedString(attributedString)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? NSTextView {
            textView.textStorage?.setAttributedString(attributedString)
        }
    }
}
