import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main Studio ViewModel (Avoids SwiftUIMacros @State plugin dependency on standalone CLT)

final class MainStudioViewModel: ObservableObject {
    static let shared = MainStudioViewModel()

    @Published var sampleFiles: [URL] = []
    @Published var selectedFileURLs: [URL] = []
    @Published var selectedBentoCategory: FileCategory = .udf
    @Published var isDropTargeted: Bool = false

    private init() {
        refreshSampleFiles()
    }

    func refreshSampleFiles() {
        sampleFiles = DemoFilesGenerator.ensureSampleFilesExist()
        if selectedFileURLs.isEmpty, let first = sampleFiles.first {
            selectedFileURLs = [first]
        }
    }
}

// MARK: - Main Studio SwiftUI View (Tangerine Aesthetic)

struct MainStudioView: View {
    @ObservedObject var coordinator = DragCoordinator.shared
    @ObservedObject var vm = MainStudioViewModel.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                // 1. Header Bar
                headerSection

                // 2. Hero Interactive Stage & Drop Zone (Tangerine Playground)
                heroPlaygroundSection

                // 3. Quick Stats Row (Like Tangerine's 275 / 26 / 6 stats)
                statsRowSection

                // 4. Bento Tabs & Interactive Wheel Preview
                bentoExplorerSection

                // 5. Recent Conversions History
                historySection
            }
            .padding(28)
        }
        .frame(minWidth: 940, minHeight: 720)
        .background(
            LinearGradient(
                colors: [
                    Color(NSColor.windowBackgroundColor),
                    Color.orange.opacity(0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onAppear {
            vm.refreshSampleFiles()
        }
    }

    // MARK: - 1. Header

    private var headerSection: some View {
        HStack(spacing: 14) {
            if let appIcon = NSImage(named: "AppIcon") ?? Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap({ NSImage(contentsOf: $0) }) {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 46, height: 46)
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange, Color(red: 1.0, green: 0.35, blue: 0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 42, height: 42)
                    Text("🍊")
                        .font(.system(size: 21))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Mandalina")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                    Text("v1.0.0")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                    Text("UYAP UDF & Çok Sayfalı TIFF Dönüştürücü")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .cornerRadius(6)
                }
                Text("Dosyayı sürükleyin, ⇧ Shift'e dokunun ve bırakın. Tüm dönüşümler %100 Mac'inizde yerel çalışır.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                AppUpdater.runOneClickUpdate()
            } label: {
                Label("Güncelle", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
            .help("GitHub üzerinden en son sürüme tek tıkla güncelle")

            Button {
                openFilePicker()
            } label: {
                Label("Dosya Seç...", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
    }

    // MARK: - 2. Hero Playground & Drag Stage

    private var heroPlaygroundSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.13, green: 0.16, blue: 0.24),
                            Color(red: 0.20, green: 0.25, blue: 0.36),
                            Color(red: 0.96, green: 0.52, blue: 0.22).opacity(0.82)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(vm.isDropTargeted ? Color.white : Color.white.opacity(0.18), lineWidth: vm.isDropTargeted ? 3 : 1)
                )
                .shadow(color: .black.opacity(0.16), radius: 18, y: 8)

            VStack(spacing: 20) {
                // Hero Headline
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        keyCapBadge(symbol: "⇧", label: "Shift: Dönüştür")
                        keyCapBadge(symbol: "⌘", label: "Command: Araçlar")
                        keyCapBadge(symbol: "⌃", label: "Control: İşlemler")
                    }

                    Text("Sürükle, ⇧ Shift'e Dokun ve Bırak.")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)

                    Text("Finder'dan herhangi bir .udf, .tiff, .pdf, .docx veya görsel dosyasını buraya (veya üst menü çubuğundaki 🍊 Mandalina simgesine) sürükleyin; ya da aşağıdaki hazır örnek dosyalara tıklayarak çarkı deneyin.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.88))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 680)
                }

                // Sample Interactive File Cards on Stage
                HStack(spacing: 14) {
                    ForEach(vm.sampleFiles, id: \.path) { url in
                        let isSelected = (vm.selectedFileURLs.first == url)
                        let cat = FileCategory.detect(from: [url])
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: cat.iconName)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(.orange)
                                Spacer()
                                Text(url.pathExtension.uppercased())
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.orange)
                                    .foregroundColor(.white)
                                    .cornerRadius(5)
                            }

                            Text(url.lastPathComponent)
                                .font(.system(size: 12.5, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)

                            Text(cat.rawValue)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.72))

                            HStack(spacing: 6) {
                                Button {
                                    vm.selectedFileURLs = [url]
                                    coordinator.openWheel(for: [url], mode: .convert)
                                } label: {
                                    Text("⇧ Çarkı Aç")
                                        .font(.system(size: 11, weight: .bold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 5)
                                        .background(Color.orange)
                                        .foregroundColor(.white)
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    DocumentPreviewWindowController.shared.showPreview(for: url) { act, u in
                                        coordinator.executeConversionInBackground(action: act, urls: [u], actionLabel: "Dönüşüm")
                                    }
                                } label: {
                                    Image(systemName: "eye.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .padding(6)
                                        .background(Color.white.opacity(0.18))
                                        .foregroundColor(.white)
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .help("Belgeyi Önizle")
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.black.opacity(isSelected ? 0.48 : 0.30))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(isSelected ? Color.orange : Color.white.opacity(0.16), lineWidth: isSelected ? 2 : 1)
                                )
                        )
                        .onDrag {
                            vm.selectedFileURLs = [url]
                            return NSItemProvider(object: url as NSURL)
                        }
                        .onTapGesture {
                            vm.selectedFileURLs = [url]
                            coordinator.openWheel(for: [url], mode: .convert)
                        }
                    }
                }
                .padding(.horizontal, 16)

                // Active file bar
                if !vm.selectedFileURLs.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.orange)
                        Text("Seçili Evrak: \(vm.selectedFileURLs.map { $0.lastPathComponent }.joined(separator: ", "))")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Spacer()

                        Button {
                            coordinator.openWheel(for: vm.selectedFileURLs, mode: .convert)
                        } label: {
                            Text("⇧ Format Dönüştür")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        Button {
                            coordinator.openWheel(for: vm.selectedFileURLs, mode: .tools)
                        } label: {
                            Text("⌘ Dosya Araçları")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        Button {
                            coordinator.openWheel(for: vm.selectedFileURLs, mode: .actions)
                        } label: {
                            Text("⌃ İşlemler")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.85))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.35))
                    )
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 26)
        }
        .onDrop(of: [.fileURL], isTargeted: $vm.isDropTargeted) { providers in
            extractDroppedURLs(from: providers) { urls in
                guard !urls.isEmpty else { return }
                vm.selectedFileURLs = urls
                coordinator.openWheel(for: urls, mode: .convert)
            }
            return true
        }
    }

    private func keyCapBadge(symbol: String, label: String) -> some View {
        HStack(spacing: 6) {
            Text(symbol)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.22))
                .cornerRadius(5)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.28)))
    }

    // MARK: - 3. Quick Stats Row

    private var statsRowSection: some View {
        HStack(spacing: 16) {
            statCard(
                number: "UDF ↔ Tüm Formatlar",
                title: "UYAP Tam Uyumlu Dönüşüm",
                desc: "UDF dosyalarını PDF, Word (.docx), Çok Sayfalı TIFF, HTML, Markdown ve RTF'e; Word ve PDF'i de doğrudan UYAP .udf formatına çevirin."
            )
            statCard(
                number: "Çok Sayfalı TIFF",
                title: "TIFF ↔ PDF & Türkçe OCR",
                desc: "İcra ve mahkeme dosyalarındaki çok sayfalı .tiff taramalarını tek tıkla PDF'e çevirin veya Apple Vision OCR ile UYAP UDF / Word'e aktarın."
            )
            statCard(
                number: "%100 Çevrimdışı",
                title: "Gizlilik & UYAP Araçları",
                desc: "Evraklarınız asla internete yüklenmez. UYAP boyut sıkıştırma (<5MB), PDF birleştirme, sayfa bölme ve e-imza doğrulama yerel çalışır."
            )
        }
    }

    private func statCard(number: String, title: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(number)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(.orange)
            Text(title)
                .font(.system(size: 14, weight: .bold))
            Text(desc)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - 4. Bento Category Explorer & One-Click Action Grid

    private var bentoExplorerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Dosya Türüne Göre Dönüşüm & Araçlar")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Text("Aşağıdaki butonlara tıklayarak seçili evrakı anında dönüştürebilirsiniz")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // Category Pills
            HStack(spacing: 8) {
                ForEach([FileCategory.udf, .tiff, .pdf, .word, .image]) { cat in
                    let isSelected = (vm.selectedBentoCategory == cat)
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            vm.selectedBentoCategory = cat
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: cat.iconName)
                            Text(cat.rawValue)
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.orange : Color(NSColor.controlBackgroundColor))
                        )
                        .foregroundColor(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Action Grid for Selected Category
            let dummyURL = sampleURL(for: vm.selectedBentoCategory)
            let convertSlices = FileCategory.slices(for: [dummyURL], mode: .convert)
            let toolSlices = FileCategory.slices(for: [dummyURL], mode: .tools)

            HStack(alignment: .top, spacing: 16) {
                // Convert Formats Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("⇧")
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                        Text("\(vm.selectedBentoCategory.rawValue) — Format Dönüşümleri")
                            .font(.system(size: 14, weight: .bold))
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(convertSlices) { slice in
                            Button {
                                let targetURLs = !vm.selectedFileURLs.isEmpty ? vm.selectedFileURLs : [dummyURL]
                                coordinator.handleSliceSelection(slice: slice, urls: targetURLs)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: slice.iconName)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.orange)
                                        .frame(width: 26)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(slice.title)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.primary)
                                        Text(slice.subtitle)
                                            .font(.system(size: 10.5))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(NSColor.windowBackgroundColor))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                )

                // Advanced Tools Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("⌘")
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                        Text("Gelişmiş UYAP & Evrak Araçları")
                            .font(.system(size: 14, weight: .bold))
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(toolSlices) { slice in
                            Button {
                                let targetURLs = !vm.selectedFileURLs.isEmpty ? vm.selectedFileURLs : [dummyURL]
                                coordinator.handleSliceSelection(slice: slice, urls: targetURLs)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: slice.iconName)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.blue)
                                        .frame(width: 26)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(slice.title)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.primary)
                                        Text(slice.subtitle)
                                            .font(.system(size: 10.5))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(NSColor.windowBackgroundColor))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            }
        }
    }

    // MARK: - 5. Recent Conversions History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Son Dönüştürülen Evraklar")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button("Örnek Dosyalar Klasörünü Aç") {
                    NSWorkspace.shared.open(DemoFilesGenerator.demoDirectoryURL)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if coordinator.history.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 22))
                        .foregroundColor(.secondary)
                    Text("Henüz bir dönüşüm yapılmadı. Yukarıdaki örnek dosyalardan birine tıklayıp dilim seçin veya Finder'dan bir dosya sürükleyin.")
                        .font(.system(size: 12.5))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(coordinator.history.prefix(10)) { rec in
                        HStack(spacing: 14) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.green)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(rec.outputURL.lastPathComponent)
                                        .font(.system(size: 13, weight: .bold))
                                    Text(rec.actionTitle)
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.16))
                                        .foregroundColor(.orange)
                                        .cornerRadius(4)
                                }
                                Text("\(rec.detailMessage) · \(rec.outputURL.path)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button("Önizle") {
                                DocumentPreviewWindowController.shared.showPreview(for: rec.outputURL) { act, u in
                                    coordinator.executeConversionInBackground(action: act, urls: [u], actionLabel: "Dönüşüm")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Finder'da Göster") {
                                NSWorkspace.shared.activateFileViewerSelecting([rec.outputURL])
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func sampleURL(for category: FileCategory) -> URL {
        switch category {
        case .udf:
            return vm.sampleFiles.first(where: { $0.pathExtension.lowercased() == "udf" }) ?? DemoFilesGenerator.demoDirectoryURL.appendingPathComponent("Ornek_Dava_Dilekcesi.udf")
        case .tiff:
            return vm.sampleFiles.first(where: { $0.pathExtension.lowercased() == "tiff" }) ?? DemoFilesGenerator.demoDirectoryURL.appendingPathComponent("Tebligat_3_Sayfa.tiff")
        case .pdf:
            return vm.sampleFiles.first(where: { $0.pathExtension.lowercased() == "pdf" }) ?? DemoFilesGenerator.demoDirectoryURL.appendingPathComponent("Bilirkisi_Raporu.pdf")
        case .word:
            return vm.sampleFiles.first(where: { $0.pathExtension.lowercased() == "docx" }) ?? DemoFilesGenerator.demoDirectoryURL.appendingPathComponent("Sozlesme_Taslagi.docx")
        default:
            return vm.sampleFiles.first(where: { $0.pathExtension.lowercased() == "tiff" }) ?? DemoFilesGenerator.demoDirectoryURL.appendingPathComponent("Tebligat_3_Sayfa.tiff")
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.title = "Dönüştürülecek Dosyaları Seçin"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            vm.selectedFileURLs = panel.urls
            coordinator.openWheel(for: panel.urls, mode: .convert)
        }
    }

    private func extractDroppedURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        lock.lock()
                        urls.append(url)
                        lock.unlock()
                    } else if let url = item as? URL {
                        lock.lock()
                        urls.append(url)
                        lock.unlock()
                    }
                }
            }
        }

        group.notify(queue: .main) {
            completion(urls)
        }
    }
}

// MARK: - In-App One-Click Updater

struct AppUpdater {
    static let updateScriptURL = "https://raw.githubusercontent.com/ssayoglu/mandalina-udf-converter/main/update.sh"

    static func runOneClickUpdate() {
        ToastHUDController.shared.showToast(
            title: "🔄 Güncelleme Denetleniyor...",
            subtitle: "GitHub üzerinden en son Mandalina sürümü kontrol ediliyor.",
            outputURL: nil,
            onPreview: nil
        )

        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = ["-c", "curl -fsSL \(updateScriptURL) | bash"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            do {
                try proc.run()
                proc.waitUntilExit()
                DispatchQueue.main.async {
                    if proc.terminationStatus == 0 {
                        ToastHUDController.shared.showToast(
                            title: "✅ Mandalina Güncellendi!",
                            subtitle: "En güncel sürüm başarıyla kuruldu.",
                            outputURL: nil,
                            onPreview: nil
                        )
                    } else {
                        ToastHUDController.shared.showToast(
                            title: "ℹ️ Sürüm Güncel (v1.0.0)",
                            subtitle: "Zaten en son Mandalina sürümünü kullanıyorsunuz.",
                            outputURL: nil,
                            onPreview: nil
                        )
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    ToastHUDController.shared.showToast(
                        title: "⚠️ Güncelleme Bağlantı Hatası",
                        subtitle: error.localizedDescription,
                        outputURL: nil,
                        onPreview: nil
                    )
                }
            }
        }
    }
}

// MARK: - AppDelegate & Menu Bar Controller

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var mainWindow: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImg = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImg
        }
        _ = DemoFilesGenerator.ensureSampleFilesExist()
        _ = DragCoordinator.shared

        setupMenuBar()
        setupMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            mainWindow.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        if !urls.isEmpty {
            DragCoordinator.shared.openWheel(for: urls, mode: .convert)
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.title = "🍊 Mandalina"
            btn.toolTip = "Mandalina — Dosyayı buraya sürükleyin veya tıklayın"
            DragCoordinator.shared.attachDragTarget(to: btn)
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Mandalina Stüdyo'yu Aç", action: #selector(openStudioWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Seçili Finder Dosyası İçin Çarkı Aç (⇧)", action: #selector(openWheelForFinderSelection), keyEquivalent: "k"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Örnek Dosyalar Klasörünü Aç", action: #selector(openDemoFolder), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "Güncellemeleri Denetle / Güncelle", action: #selector(triggerUpdate), keyEquivalent: "u"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Mandalina'dan Çık", action: #selector(quitApp), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    private func setupMainWindow() {
        let contentView = MainStudioView()
        mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1020, height: 780),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        mainWindow.center()
        mainWindow.title = "Mandalina — UYAP (.udf) & Çok Sayfalı TIFF Dönüştürücü"
        mainWindow.contentView = NSHostingView(rootView: contentView)
        mainWindow.isReleasedWhenClosed = false
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openStudioWindow() {
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openWheelForFinderSelection() {
        let urls = DragCoordinator.shared.queryFinderSelectionOrDemoFiles()
        DragCoordinator.shared.openWheel(for: urls, mode: .convert)
    }

    @objc private func openDemoFolder() {
        NSWorkspace.shared.open(DemoFilesGenerator.demoDirectoryURL)
    }

    @objc private func triggerUpdate() {
        AppUpdater.runOneClickUpdate()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

@main
struct MandalinaApp {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            runSelfTest()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    static func runSelfTest() {
        print("🍊 Mandalina — Otomatik Dönüşüm Testi Başlatılıyor...")
        let sampleURLs = DemoFilesGenerator.ensureSampleFilesExist()
        for u in sampleURLs {
            print("  • Örnek dosya hazır: \(u.lastPathComponent)")
        }

        guard let udfURL = sampleURLs.first(where: { $0.pathExtension == "udf" }),
              let tiffURL = sampleURLs.first(where: { $0.pathExtension == "tiff" }),
              let docxURL = sampleURLs.first(where: { $0.pathExtension == "docx" }),
              let pdfURL = sampleURLs.first(where: { $0.pathExtension == "pdf" }) else {
            print("❌ Örnek dosyalar oluşturulamadı!")
            exit(1)
        }

        do {
            // 1. UDF -> PDF, DOCX, HTML, MD, TXT, RTF
            for act in [ConversionAction.toPDF, .toDOCX, .toHTML, .toMarkdown, .toTXT, .toRTF] {
                let res = try MediaConverterEngine.perform(action: act, on: [udfURL])
                print("  ✅ [UDF] \(res[0].actionTitle): \(res[0].outputURL.lastPathComponent) (\(res[0].detailMessage))")
            }

            // 2. Multi-Page TIFF (3 pages) -> PDF & OCR to UDF
            let tiffToPDF = try MediaConverterEngine.perform(action: .toPDF, on: [tiffURL])
            print("  ✅ [TIFF -> PDF] \(tiffToPDF[0].outputURL.lastPathComponent) (\(tiffToPDF[0].detailMessage))")

            let tiffToUDF = try MediaConverterEngine.perform(action: .ocrToUDF, on: [tiffURL])
            print("  ✅ [TIFF -> UDF (OCR)] \(tiffToUDF[0].outputURL.lastPathComponent) (\(tiffToUDF[0].detailMessage))")

            // 3. DOCX -> UDF & PDF -> UDF
            let docxToUDF = try MediaConverterEngine.perform(action: .toUDF, on: [docxURL])
            print("  ✅ [DOCX -> UDF] \(docxToUDF[0].outputURL.lastPathComponent) (\(docxToUDF[0].detailMessage))")

            let pdfToUDF = try MediaConverterEngine.perform(action: .toUDF, on: [pdfURL])
            print("  ✅ [PDF -> UDF] \(pdfToUDF[0].outputURL.lastPathComponent) (\(pdfToUDF[0].detailMessage))")

            // 4. Advanced Tools: UYAP Compress & Merge
            let comp = try MediaConverterEngine.perform(action: .compressUYAP, on: [pdfURL])
            print("  ✅ [UYAP Sıkıştır] \(comp[0].outputURL.lastPathComponent) (\(comp[0].detailMessage))")

            let merged = try MediaConverterEngine.perform(action: .mergeToPDF, on: [udfURL, tiffURL])
            print("  ✅ [PDF Birleştir (UDF + 3 Sayfa TIFF)] \(merged[0].outputURL.lastPathComponent) (\(merged[0].detailMessage))")

            print("🎉 Tüm dönüşüm ve araç testleri başarıyla tamamlandı!")
        } catch {
            print("❌ Test Hatası: \(error.localizedDescription)")
            exit(1)
        }
    }
}
