import AppKit
import Combine
import SideLingoCore
import SwiftUI

@MainActor
private final class SystemDictionarySpeaker {
    private let synthesizer = NSSpeechSynthesizer()

    func speak(_ text: String) {
        synthesizer.stopSpeaking()
        synthesizer.startSpeaking(text)
    }

    func stop() {
        synthesizer.stopSpeaking()
    }
}

final class QuickPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            onCancel?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

@MainActor
final class QuickPanelViewModel: ObservableObject {
    @Published var mode: CompanionMode = .translate
    @Published var source = "Selection"
    @Published var input = ""
    @Published var output = CompanionOutput(primary: "", secondaryTitle: "", secondary: "")
    @Published var dictionary: DictionaryPresentation?
    @Published var unavailableMessage: String?
    @Published var isLoading = false
    @Published var isCopyEnabled = false

    var onRun: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSpeak: (() -> Void)?
    var onHide: (() -> Void)?
    var onPlaceholderAction: (() -> Void)?
}

@MainActor
final class QuickPanelController: NSWindowController {
    private let processingSession: QuickPanelProcessingSession
    private let speaker = SystemDictionarySpeaker()
    private let viewModel = QuickPanelViewModel()
    private var escapeMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    init(
        processor: any ProviderStreaming,
        dictionary: (any DictionaryLookupProviding)?,
        historyStore: SQLiteHistoryStore?
    ) {
        processingSession = QuickPanelProcessingSession(
            processor: processor,
            dictionary: dictionary,
            historyRecorder: historyStore
        )
        let panelHeight = CGFloat(QuickPanelInputPresentation.panelHeight)
        let panel = QuickPanel(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: panelHeight),
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

        viewModel.onRun = { [weak self] in self?.run() }
        viewModel.onCopy = { [weak self] in self?.copyPrimary() }
        viewModel.onSpeak = { [weak self] in self?.speakDictionaryWord() }
        viewModel.onHide = { [weak self] in self?.hide() }
        viewModel.onPlaceholderAction = { NSSound.beep() }
        panel.onCancel = { [weak self] in self?.hide() }

        let hostingView = NSHostingView(rootView: QuickPanelView(model: viewModel))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hostingView

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, self?.window?.isVisible == true else { return event }
            self?.hide()
            return nil
        }

        processingSession.$state
            .sink { [weak self] state in self?.apply(state) }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) { nil }

    func show(mode: CompanionMode, text: String, source: SelectionSource) {
        speaker.stop()
        viewModel.mode = mode
        viewModel.input = text
        viewModel.source = source == .accessibility ? "Selection" : "Clipboard"
        viewModel.unavailableMessage = nil
        viewModel.dictionary = nil
        viewModel.output = CompanionOutput(primary: "", secondaryTitle: "", secondary: "")
        processingSession.submit(mode: mode, text: text)
        present()
    }

    func showUnavailable(mode: CompanionMode, reason: InvocationUnavailableReason) {
        speaker.stop()
        processingSession.cancel()
        viewModel.mode = mode
        viewModel.source = "No selection"
        viewModel.input = ""
        viewModel.dictionary = nil
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

    private func run() {
        guard let request = QuickPanelRunPolicy.request(for: viewModel.input) else { return }
        speaker.stop()
        viewModel.input = request.text
        viewModel.source = request.sourceLabel
        viewModel.unavailableMessage = nil
        viewModel.dictionary = nil
        viewModel.output = CompanionOutput(primary: "", secondaryTitle: "", secondary: "")
        processingSession.submit(mode: viewModel.mode, text: request.text)
    }

    private func copyPrimary() {
        guard viewModel.isCopyEnabled else { return }
        let value = viewModel.dictionary?.copyText ?? viewModel.output.primary
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private func speakDictionaryWord() {
        guard let text = viewModel.dictionary?.speechText else { return }
        speaker.speak(text)
    }

    private func apply(_ state: QuickPanelProcessingState) {
        if case .streaming = state {
            viewModel.isLoading = true
        } else {
            viewModel.isLoading = false
        }
        switch state {
        case .idle:
            viewModel.dictionary = nil
            viewModel.isCopyEnabled = false
        case let .streaming(partial):
            viewModel.dictionary = nil
            viewModel.unavailableMessage = nil
            viewModel.output = QuickPanelResultPresentation.output(for: partial)
            viewModel.isCopyEnabled = false
        case let .success(output):
            viewModel.dictionary = nil
            viewModel.unavailableMessage = nil
            viewModel.output = output
            viewModel.isCopyEnabled = processingSession.isCopyEnabled
        case let .dictionary(lookup):
            viewModel.unavailableMessage = nil
            viewModel.dictionary = DictionaryPresentation(lookup: lookup)
            viewModel.output = CompanionOutput(primary: "", secondaryTitle: "", secondary: "")
            viewModel.isCopyEnabled = processingSession.isCopyEnabled
        case let .error(message):
            viewModel.dictionary = nil
            viewModel.unavailableMessage = message
            viewModel.isCopyEnabled = false
            viewModel.output = CompanionOutput(
                primary: message,
                secondaryTitle: "PROVIDER ERROR",
                secondary: "Open Settings to configure DeepSeek, then run the request again."
            )
        }
    }

    private func hide() {
        speaker.stop()
        processingSession.cancel()
        window?.orderOut(nil)
    }

    private func present() {
        guard let panel = window as? NSPanel,
              let screen = NSScreen.main else { return }
        let size = NSSize(
            width: 780,
            height: CGFloat(QuickPanelInputPresentation.panelHeight)
        )
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
