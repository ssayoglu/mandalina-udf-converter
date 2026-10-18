import Foundation
import AppKit
import SwiftUI

// MARK: - Wedge Shape for Radial Fan Menu

struct RadialWedgeShape: Shape {
    var startAngle: Angle
    var endAngle: Angle
    var innerRadius: CGFloat
    var outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()

        let startRad = CGFloat(startAngle.radians)
        let endRad = CGFloat(endAngle.radians)

        let innerStart = CGPoint(
            x: center.x + innerRadius * cos(startRad),
            y: center.y + innerRadius * sin(startRad)
        )
        let outerStart = CGPoint(
            x: center.x + outerRadius * cos(startRad),
            y: center.y + outerRadius * sin(startRad)
        )
        let innerEnd = CGPoint(
            x: center.x + innerRadius * cos(endRad),
            y: center.y + innerRadius * sin(endRad)
        )

        path.move(to: innerStart)
        path.addLine(to: outerStart)
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        path.addLine(to: innerEnd)
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Radial Wheel Observable State

final class RadialWheelState: ObservableObject {
    @Published var urls: [URL] = []
    @Published var mode: WheelMode = .convert
    @Published var hoveredIndex: Int? = nil
    @Published var isVisible: Bool = false

    var slices: [WheelSlice] {
        FileCategory.slices(for: urls, mode: mode)
    }

    var hoveredSlice: WheelSlice? {
        guard let idx = hoveredIndex, idx >= 0, idx < slices.count else { return nil }
        return slices[idx]
    }

    func updateHover(at localPoint: CGPoint, in size: CGSize) {
        let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        let dx = localPoint.x - center.x
        let dy = localPoint.y - center.y
        let dist = hypot(dx, dy)

        let count = slices.count
        guard count > 0, dist >= 38, dist <= 185 else {
            if hoveredIndex != nil {
                hoveredIndex = nil
            }
            return
        }

        // Normalize angle with -90° (top) as 0°
        var deg = atan2(dy, dx) * 180.0 / .pi + 90.0
        if deg < 0 { deg += 360.0 }

        let sliceAngle = 360.0 / Double(count)
        let idx = Int(deg / sliceAngle) % count
        if hoveredIndex != idx {
            hoveredIndex = idx
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}

// MARK: - SwiftUI Radial Wheel View

struct RadialWheelView: View {
    @ObservedObject var state: RadialWheelState
    var onSelectSlice: (WheelSlice) -> Void
    var onClose: () -> Void

    private let wheelSize: CGFloat = 340
    private let innerRadius: CGFloat = 56
    private let outerRadius: CGFloat = 152

    var body: some View {
        VStack(spacing: 10) {
            // Top Modifier Switcher Pill (⇧ Convert | ⌘ Tools | ⌃ Actions)
            HStack(spacing: 6) {
                ForEach(WheelMode.allCases) { m in
                    let isSelected = (state.mode == m)
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
                            state.mode = m
                            state.hoveredIndex = nil
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(m.keySymbol)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(isSelected ? Color.white.opacity(0.25) : Color.primary.opacity(0.08))
                                .cornerRadius(4)
                            Text(m.title)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color(m.accentColor) : Color.clear)
                        )
                        .foregroundColor(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
            )

            // Circular Fan / Radial Wheel
            ZStack {
                let items = state.slices
                let count = max(1, items.count)
                let stepDeg = 360.0 / Double(count)
                let gapDeg = count > 1 ? 2.6 : 0.0

                // Backdrop glow ring
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(state.mode.accentColor).opacity(0.18), Color.clear],
                            center: .center,
                            startRadius: 30,
                            endRadius: 175
                        )
                    )
                    .frame(width: wheelSize, height: wheelSize)

                ForEach(Array(items.enumerated()), id: \.element.id) { index, slice in
                    let isHovered = (state.hoveredIndex == index)
                    let startDeg = -90.0 + Double(index) * stepDeg + gapDeg / 2.0
                    let endDeg = -90.0 + Double(index + 1) * stepDeg - gapDeg / 2.0
                    let midRad = ((startDeg + endDeg) / 2.0) * .pi / 180.0
                    let curInner = isHovered ? innerRadius + 3 : innerRadius
                    let curOuter = isHovered ? outerRadius + 9 : outerRadius
                    let labelRadius = (curInner + curOuter) / 2.0

                    ZStack {
                        RadialWedgeShape(
                            startAngle: .degrees(startDeg),
                            endAngle: .degrees(endDeg),
                            innerRadius: curInner,
                            outerRadius: curOuter
                        )
                        .fill(
                            isHovered
                                ? Color(state.mode.accentColor)
                                : Color(NSColor.windowBackgroundColor).opacity(0.94)
                        )
                        .overlay(
                            RadialWedgeShape(
                                startAngle: .degrees(startDeg),
                                endAngle: .degrees(endDeg),
                                innerRadius: curInner,
                                outerRadius: curOuter
                            )
                            .stroke(
                                isHovered
                                    ? Color.white.opacity(0.85)
                                    : Color.primary.opacity(0.14),
                                lineWidth: isHovered ? 2.0 : 1.0
                            )
                        )
                        .shadow(
                            color: isHovered ? Color(state.mode.accentColor).opacity(0.45) : .black.opacity(0.15),
                            radius: isHovered ? 12 : 5,
                            y: 2
                        )

                        // Slice Icon + Format Label positioned at midpoint of wedge
                        VStack(spacing: 3) {
                            Image(systemName: slice.iconName)
                                .font(.system(size: isHovered ? 19 : 16, weight: .semibold))
                                .foregroundColor(isHovered ? .white : Color(state.mode.accentColor))
                            Text(slice.title)
                                .font(.system(size: isHovered ? 12.5 : 11.5, weight: .bold, design: .rounded))
                                .foregroundColor(isHovered ? .white : .primary)
                                .lineLimit(1)
                        }
                        .position(
                            x: wheelSize / 2.0 + labelRadius * CGFloat(cos(midRad)),
                            y: wheelSize / 2.0 + labelRadius * CGFloat(sin(midRad))
                        )
                    }
                    .frame(width: wheelSize, height: wheelSize)
                    .contentShape(
                        RadialWedgeShape(
                            startAngle: .degrees(startDeg),
                            endAngle: .degrees(endDeg),
                            innerRadius: curInner,
                            outerRadius: curOuter
                        )
                    )
                    .onTapGesture {
                        onSelectSlice(slice)
                    }
                    .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
                }

                // Center Hub Circle
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: innerRadius * 1.88, height: innerRadius * 1.88)
                        .overlay(
                            Circle()
                                .stroke(Color(state.mode.accentColor).opacity(0.55), lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 6)

                    if let active = state.hoveredSlice {
                        VStack(spacing: 2) {
                            Text(active.badgeText)
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Color(state.mode.accentColor))
                                .foregroundColor(.white)
                                .cornerRadius(4)
                            Text(active.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Text("Bırak / Tıkla")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(6)
                    } else {
                        let cat = FileCategory.detect(from: state.urls)
                        VStack(spacing: 3) {
                            Image(systemName: cat.iconName)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(Color(state.mode.accentColor))
                            Text(state.urls.count > 1 ? "\(state.urls.count) Dosya" : (state.urls.first?.pathExtension.uppercased() ?? "DOSYA"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.primary)
                            Text("Dilim Seçin")
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .frame(width: wheelSize, height: wheelSize)

            // Bottom Active Slice Subtitle Pill
            Text(state.hoveredSlice?.subtitle ?? "⇧ Dönüştür · ⌘ Araçlar · ⌃ İşlemler — Dilimin üzerine bırakın")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                )
        }
        .padding(12)
    }
}

// MARK: - AppKit Drag-Receiving View Wrapping the Radial Wheel

final class RadialWheelContainerNSView: NSView {
    let state: RadialWheelState
    var onPerformSlice: ((WheelSlice, [URL]) -> Void)?
    var onCancel: (() -> Void)?

    private var hostingView: NSHostingView<RadialWheelView>!
    private var trackingArea: NSTrackingArea?

    init(state: RadialWheelState) {
        self.state = state
        super.init(frame: NSRect(x: 0, y: 0, width: 380, height: 440))
        setupView()
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        let rootView = RadialWheelView(
            state: state,
            onSelectSlice: { [weak self] slice in
                guard let self = self else { return }
                self.onPerformSlice?(slice, self.state.urls)
            },
            onClose: { [weak self] in
                self?.onCancel?()
            }
        )
        hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        updateHoverFromViewPoint(loc)
    }

    func updateHoverFromScreenPoint(_ screenPoint: NSPoint) {
        guard let win = window else { return }
        let winPoint = win.convertPoint(fromScreen: screenPoint)
        let viewPoint = convert(winPoint, from: nil)
        updateHoverFromViewPoint(viewPoint)
    }

    private func updateHoverFromViewPoint(_ viewPoint: NSPoint) {
        // Flip Y so top is 0 matching SwiftUI geometry, centered on the wheel
        let flippedY = bounds.height - viewPoint.y
        // Wheel center in the 380x440 container is at (190, 224)
        let wheelLocal = CGPoint(x: viewPoint.x - (bounds.width / 2.0 - 170.0), y: flippedY - 54.0)
        state.updateHover(at: wheelLocal, in: CGSize(width: 340, height: 340))
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = extractFileURLs(from: sender.draggingPasteboard)
        if !urls.isEmpty {
            state.urls = urls
        }
        let loc = convert(sender.draggingLocation, from: nil)
        updateHoverFromViewPoint(loc)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let loc = convert(sender.draggingLocation, from: nil)
        updateHoverFromViewPoint(loc)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        state.hoveredIndex = nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let droppedURLs = extractFileURLs(from: sender.draggingPasteboard)
        if !droppedURLs.isEmpty {
            state.urls = droppedURLs
        }
        let loc = convert(sender.draggingLocation, from: nil)
        updateHoverFromViewPoint(loc)

        if let slice = state.hoveredSlice, !state.urls.isEmpty {
            onPerformSlice?(slice, state.urls)
            return true
        }
        return false
    }

    func extractFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return urls
        }
        return []
    }
}

// MARK: - Floating Radial Wheel NSPanel

final class RadialWheelPanel: NSPanel {
    let wheelState = RadialWheelState()
    private(set) var containerView: RadialWheelContainerNSView!

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 440),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .popUpMenu
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        containerView = RadialWheelContainerNSView(state: wheelState)
        self.contentView = containerView
    }

    override var canBecomeKey: Bool { true }

    func present(at screenPoint: NSPoint, with urls: [URL], mode: WheelMode) {
        wheelState.urls = urls
        wheelState.mode = mode
        wheelState.hoveredIndex = nil
        wheelState.isVisible = true

        // Position panel so the wheel center aligns right under `screenPoint`
        let panelWidth: CGFloat = 380
        let panelHeight: CGFloat = 440
        var originX = screenPoint.x - panelWidth / 2.0
        var originY = screenPoint.y - panelHeight / 2.0

        if let screen = NSScreen.screens.first(where: { NSMouseInRect(screenPoint, $0.frame, false) }) ?? NSScreen.main {
            let vf = screen.visibleFrame
            originX = max(vf.minX + 8, min(originX, vf.maxX - panelWidth - 8))
            originY = max(vf.minY + 8, min(originY, vf.maxY - panelHeight - 8))
        }

        setFrame(NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight), display: true)
        orderFrontRegardless()
    }

    func dismissWheel() {
        wheelState.isVisible = false
        wheelState.hoveredIndex = nil
        orderOut(nil)
    }
}
