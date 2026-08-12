import AppKit
import EnglishCompanionCore
import SwiftUI

final class QuickPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            orderOut(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

@MainActor
final class QuickPanelViewModel: ObservableObject {
    @Published var mode: CompanionMode = .translate
    @Published var source = "Selection"
    @Published var input = ""
    @Published var output = CompanionOutput(primary: "", secondaryTitle: "", secondary: "")
    @Published var unavailableMessage: String?

    var onRun: (() -> Void)?
    var onCopy: (() -> Void)?
    var onHide: (() -> Void)?
    var onPlaceholderAction: (() -> Void)?
}

@MainActor
final class QuickPanelController: NSWindowController {
    private let processor = MockProcessor()
    private let historyStore: SQLiteHistoryStore?
    private let viewModel = QuickPanelViewModel()
    private var escapeMonitor: Any?

    init(historyStore: SQLiteHistoryStore?) {
        self.historyStore = historyStore
        let panel = QuickPanel(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 414),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        super.init(window: panel)

        viewModel.onRun = { [weak self] in self?.runMock() }
        viewModel.onCopy = { [weak self] in self?.copyPrimary() }
        viewModel.onHide = { [weak self] in self?.hide() }
        viewModel.onPlaceholderAction = { NSSound.beep() }

        let hostingView = NSHostingView(rootView: QuickPanelView(model: viewModel))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hostingView

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, self?.window?.isVisible == true else { return event }
            self?.hide()
            return nil
        }
    }

    required init?(coder: NSCoder) { nil }

    func show(mode: CompanionMode, text: String, source: SelectionSource) {
        show(mode: mode, text: text, source: source, presentation: .userResult)
    }

    func showDemo() {
        show(
            mode: .translate,
            text: "这个方案我需要再看一下，晚点回复你。",
            source: .accessibility,
            presentation: .demo
        )
    }

    private func show(
        mode: CompanionMode,
        text: String,
        source: SelectionSource,
        presentation: HistoryPresentation
    ) {
        viewModel.mode = mode
        viewModel.input = text
        viewModel.source = source == .accessibility ? "Selection" : "Clipboard"
        viewModel.unavailableMessage = nil
        viewModel.output = processor.process(mode: mode, text: text)
        saveHistory(presentation: presentation)
        present()
    }

    func showUnavailable(mode: CompanionMode, reason: InvocationUnavailableReason) {
        viewModel.mode = mode
        viewModel.source = "No selection"
        viewModel.input = ""
        viewModel.unavailableMessage = reason == .permissionRequired
            ? "Accessibility permission is required to read selected text from another app."
            : "No new selected text was found. The previous clipboard was not reused."
        viewModel.output = CompanionOutput(
            primary: viewModel.unavailableMessage ?? "",
            secondaryTitle: "SAFE FALLBACK",
            secondary: "Select text in Chrome, Preview, or Obsidian, then press the global shortcut again."
        )
        present()
    }

    private func runMock() {
        guard let request = QuickPanelRunPolicy.request(for: viewModel.input) else { return }
        viewModel.input = request.text
        viewModel.source = request.sourceLabel
        viewModel.unavailableMessage = nil
        viewModel.output = processor.process(mode: viewModel.mode, text: request.text)
        saveHistory(presentation: .userResult)
    }

    private func copyPrimary() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(viewModel.output.primary, forType: .string)
    }

    private func saveHistory(presentation: HistoryPresentation) {
        guard let historyStore else { return }
        let record = HistoryRecord(
            mode: viewModel.mode,
            source: viewModel.input,
            result: viewModel.output.primary,
            createdAt: Date().timeIntervalSince1970
        )
        try? HistoryPersistencePolicy.record(record, presentation: presentation) {
            try historyStore.append($0)
        }
    }

    private func hide() {
        window?.orderOut(nil)
    }

    private func present() {
        guard let panel = window as? NSPanel,
              let screen = NSScreen.main else { return }
        let size = NSSize(width: 780, height: 414)
        let visible = screen.visibleFrame
        panel.setFrame(
            NSRect(
                x: visible.midX - size.width / 2,
                y: visible.maxY - size.height - 72,
                width: size.width,
                height: size.height
            ),
            display: true
        )
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}
