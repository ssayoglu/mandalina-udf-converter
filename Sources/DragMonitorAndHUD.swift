import Foundation
import AppKit
import SwiftUI

// MARK: - Floating Toast Notification HUD

final class ToastHUDController {
    static let shared = ToastHUDController()
    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    func showToast(title: String, subtitle: String, outputURL: URL?, onPreview: ((URL) -> Void)?) {
        hideWorkItem?.cancel()

        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 68),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isFloatingPanel = true
            p.level = .statusBar
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.panel = p
        }

        guard let panel = panel else { return }

        let view = HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let url = outputURL {
                Button("Önizle") {
                    onPreview?(url)
                    self.dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    self.dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                )
        )

        panel.contentView = NSHostingView(rootView: view)
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            let x = vf.midX - 230
            let y = vf.maxY - 86
            panel.setFrame(NSRect(x: x, y: y, width: 460, height: 68), display: true)
        }
        panel.orderFrontRegardless()
        NSSound(named: "Glass")?.play()

        let work = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: work)
    }

    func dismiss() {
        panel?.orderOut(nil)
    }
}

// MARK: - Menu Bar Status Item Drag Target View

final class MenuBarDragTargetView: NSView {
    var onDragEnteredWithURLs: (([URL], NSPoint) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Let normal left/right clicks pass through to NSStatusBarButton so the menu opens normally
        return nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            onDragEnteredWithURLs?(urls, NSEvent.mouseLocation)
        }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            onDragEnteredWithURLs?(urls, NSEvent.mouseLocation)
            return true
        }
        return false
    }
}

// MARK: - Global Drag + Modifier Key Coordinator (Tangerine "Drag + Shift" Engine)

final class DragCoordinator: ObservableObject {
    static let shared = DragCoordinator()

    @Published var history: [ConversionRecord] = []

    let radialPanel = RadialWheelPanel()

    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalDragMonitor: Any?
    private var localDragMonitor: Any?
    private var globalMouseUpMonitor: Any?
    private var localMouseUpMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var dragPollTimer: Timer?

    private var lastDragPasteboardCount: Int = 0
    private var activeDraggedURLs: [URL] = []
    private var previousModifiers: NSEvent.ModifierFlags = []
    private var isProcessingAction = false

    private init() {
        lastDragPasteboardCount = NSPasteboard(name: .drag).changeCount
        setupCallbacks()
        startMonitoring()
    }

    private func setupCallbacks() {
        radialPanel.containerView.onPerformSlice = { [weak self] slice, urls in
            self?.handleSliceSelection(slice: slice, urls: urls)
        }
        radialPanel.containerView.onCancel = { [weak self] in
            self?.radialPanel.dismissWheel()
        }
    }

    func attachDragTarget(to statusButton: NSStatusBarButton) {
        let overlay = MenuBarDragTargetView(frame: statusButton.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.onDragEnteredWithURLs = { [weak self] urls, screenPt in
            guard let self = self else { return }
            self.activeDraggedURLs = urls
            self.radialPanel.present(at: screenPt, with: urls, mode: .convert)
        }
        statusButton.addSubview(overlay)
    }

    func startMonitoring() {
        // 1. Poll NSPasteboard(name: .drag) while left mouse button is down so we immediately know when a file drag starts in Finder
        dragPollTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            self?.pollDragState()
        }

        // 2. Global & Local Modifier Key Monitors (⇧ Shift, ⌘ Command, ⌃ Control)
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event.modifierFlags)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event.modifierFlags)
            return event
        }

        // 3. Global & Local Mouse Drag Monitors to update Radial Wheel hover slice live
        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .mouseMoved]) { [weak self] _ in
            self?.handleCursorMoved()
        }
        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .mouseMoved]) { [weak self] event in
            self?.handleCursorMoved()
            return event
        }

        // 4. Global & Local Mouse Up Monitors so releasing the file over a slice triggers conversion
        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.handleGlobalMouseUp()
        }
        localMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.handleGlobalMouseUp()
            return event
        }

        // 5. Local Escape key to cancel radial wheel
        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, self?.radialPanel.wheelState.isVisible == true {
                self?.radialPanel.dismissWheel()
                return nil
            }
            return event
        }
    }

    private func pollDragState() {
        let mouseDown = (NSEvent.pressedMouseButtons & 1) != 0
        let dragPB = NSPasteboard(name: .drag)

        if mouseDown {
            if dragPB.changeCount != lastDragPasteboardCount {
                lastDragPasteboardCount = dragPB.changeCount
                if let urls = dragPB.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
                   !urls.isEmpty {
                    activeDraggedURLs = urls
                }
            }
            if radialPanel.wheelState.isVisible {
                radialPanel.containerView.updateHoverFromScreenPoint(NSEvent.mouseLocation)
            }
        } else {
            // If mouse was released while a slice was hovered during a Finder drag
            if radialPanel.wheelState.isVisible,
               let hovered = radialPanel.wheelState.hoveredSlice,
               !radialPanel.wheelState.urls.isEmpty,
               !activeDraggedURLs.isEmpty {
                let urlsToRun = radialPanel.wheelState.urls
                activeDraggedURLs = []
                handleSliceSelection(slice: hovered, urls: urlsToRun)
            } else {
                activeDraggedURLs = []
            }
        }
    }

    private func handleCursorMoved() {
        guard radialPanel.wheelState.isVisible else { return }
        radialPanel.containerView.updateHoverFromScreenPoint(NSEvent.mouseLocation)
    }

    private func handleGlobalMouseUp() {
        guard radialPanel.wheelState.isVisible else { return }
        radialPanel.containerView.updateHoverFromScreenPoint(NSEvent.mouseLocation)
        if let slice = radialPanel.wheelState.hoveredSlice, !radialPanel.wheelState.urls.isEmpty {
            let urls = radialPanel.wheelState.urls
            activeDraggedURLs = []
            handleSliceSelection(slice: slice, urls: urls)
        }
    }

    private func handleFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        let clean = flags.intersection([.shift, .command, .control, .option])
        defer { previousModifiers = clean }

        let shiftJustPressed = clean.contains(.shift) && !previousModifiers.contains(.shift)
        let cmdJustPressed   = clean.contains(.command) && !previousModifiers.contains(.command)
        let ctrlJustPressed  = clean.contains(.control) && !previousModifiers.contains(.control)

        guard shiftJustPressed || cmdJustPressed || ctrlJustPressed else { return }

        let targetMode: WheelMode
        if shiftJustPressed {
            targetMode = .convert
        } else if cmdJustPressed {
            targetMode = .tools
        } else {
            targetMode = .actions
        }

        // If the radial wheel is already open, switch its mode!
        if radialPanel.wheelState.isVisible {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.76)) {
                radialPanel.wheelState.mode = targetMode
                radialPanel.wheelState.hoveredIndex = nil
            }
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            return
        }

        // Otherwise, if the user is currently dragging a file in Finder (mouse down), open the Radial Wheel at cursor!
        let mouseDown = (NSEvent.pressedMouseButtons & 1) != 0
        if mouseDown {
            var urls = activeDraggedURLs
            if urls.isEmpty {
                let dragPB = NSPasteboard(name: .drag)
                if let pbURLs = dragPB.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !pbURLs.isEmpty {
                    urls = pbURLs
                    activeDraggedURLs = pbURLs
                }
            }
            if urls.isEmpty {
                urls = queryFinderSelectionOrDemoFiles()
            }
            if !urls.isEmpty {
                radialPanel.present(at: NSEvent.mouseLocation, with: urls, mode: targetMode)
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
        }
    }

    /// Presents the Radial Wheel manually (e.g., from the Main Window Playground or Menu Bar).
    func openWheel(for urls: [URL], mode: WheelMode = .convert, at screenPoint: NSPoint? = nil) {
        guard !urls.isEmpty else { return }
        let pt = screenPoint ?? NSEvent.mouseLocation
        radialPanel.present(at: pt, with: urls, mode: mode)
    }

    // MARK: - Execute Chosen Slice Action

    func handleSliceSelection(slice: WheelSlice, urls: [URL]) {
        guard !isProcessingAction, !urls.isEmpty else { return }
        isProcessingAction = true
        radialPanel.dismissWheel()

        let firstURL = urls[0]

        // Special interactive actions (Preview, Inspect, Share)
        switch slice.action {
        case .quickPreview:
            isProcessingAction = false
            DocumentPreviewWindowController.shared.showPreview(for: firstURL, inspectMode: false) { [weak self] act, targetURL in
                self?.executeConversionInBackground(action: act, urls: [targetURL], actionLabel: "Hızlı Dönüşüm")
            }
            return

        case .inspectUDF:
            isProcessingAction = false
            DocumentPreviewWindowController.shared.showPreview(for: firstURL, inspectMode: true) { [weak self] act, targetURL in
                self?.executeConversionInBackground(action: act, urls: [targetURL], actionLabel: "Hızlı Dönüşüm")
            }
            return

        case .shareAirDrop:
            isProcessingAction = false
            if let contentView = NSApp.keyWindow?.contentView ?? radialPanel.contentView {
                let picker = NSSharingServicePicker(items: urls)
                picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
            }
            return

        default:
            break
        }

        executeConversionInBackground(action: slice.action, urls: urls, actionLabel: slice.subtitle)
    }

    func executeConversionInBackground(action: ConversionAction, urls: [URL], actionLabel: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let newRecords = try MediaConverterEngine.perform(action: action, on: urls)
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isProcessingAction = false
                    self.history.insert(contentsOf: newRecords, at: 0)
                    if let first = newRecords.first {
                        ToastHUDController.shared.showToast(
                            title: "✅ \(first.actionTitle) Tamamlandı",
                            subtitle: "\(first.outputURL.lastPathComponent) — \(first.detailMessage)",
                            outputURL: first.outputURL,
                            onPreview: { previewURL in
                                DocumentPreviewWindowController.shared.showPreview(for: previewURL) { act, u in
                                    self.executeConversionInBackground(action: act, urls: [u], actionLabel: "Dönüşüm")
                                }
                            }
                        )
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isProcessingAction = false
                    ToastHUDController.shared.showToast(
                        title: "⚠️ İşlem Hatası",
                        subtitle: error.localizedDescription,
                        outputURL: nil,
                        onPreview: nil
                    )
                }
            }
        }
    }

    /// Queries currently selected Finder files if drag pasteboard was not populated yet, or returns sample demo files.
    func queryFinderSelectionOrDemoFiles() -> [URL] {
        let scriptSrc = """
        tell application "Finder"
            set sel to selection
            set outList to {}
            repeat with f in sel
                set end of outList to POSIX path of (f as alias)
            end repeat
            return outList
        end tell
        """
        if let script = NSAppleScript(source: scriptSrc) {
            var err: NSDictionary?
            let desc = script.executeAndReturnError(&err)
            if err == nil && desc.numberOfItems > 0 {
                var urls: [URL] = []
                for i in 1...desc.numberOfItems {
                    if let path = desc.atIndex(i)?.stringValue, !path.isEmpty {
                        urls.append(URL(fileURLWithPath: path))
                    }
                }
                if !urls.isEmpty { return urls }
            }
        }
        return DemoFilesGenerator.ensureSampleFilesExist()
    }
}
