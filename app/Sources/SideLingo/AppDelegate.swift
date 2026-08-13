import AppKit
import Carbon
import SideLingoCore
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: SideLingoIdentity.bundleIdentifier, category: "invocation")
    private let coordinator = InvocationCoordinator()
    private let selectionProvider = AXSelectedTextProvider()
    private let permissionManager = AccessibilityPermissionManager()
    private let pasteboardCapture = PasteboardCaptureCoordinator(
        pasteboard: SystemPasteboardAccess(),
        sendCopy: { CopyCommandSender().send() }
    )
    private var providerSettings: SQLiteProviderStore?
    private var quickPanel: QuickPanelController!
    private var settingsWindow: ProviderSettingsWindowController!
    private var hotKeys: GlobalHotKeyMonitor?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = ApplicationMenuFactory.makeMainMenu(
            applicationName: SideLingoIdentity.productName
        )
        NSApp.setActivationPolicy(.accessory)
        guard let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            logger.fault("Application Support is unavailable.")
            NSApp.terminate(nil)
            return
        }
        do {
            try ApplicationSupportMigrator().migrate(in: applicationSupportDirectory)
        } catch {
            logger.fault("Application Support migration failed.")
            NSApp.terminate(nil)
            return
        }
        guard let providerSettings = try? makeProviderSettingsStore(
            in: applicationSupportDirectory
        ) else {
            logger.fault("Provider settings database is unavailable.")
            NSApp.terminate(nil)
            return
        }
        self.providerSettings = providerSettings
        let processor = ConfiguredProviderProcessor(
            settingsStore: providerSettings
        )
        quickPanel = QuickPanelController(
            processor: processor,
            historyStore: makeHistoryStore(in: applicationSupportDirectory)
        )
        settingsWindow = ProviderSettingsWindowController(
            settingsService: ProviderSettingsService(store: providerSettings)
        )
        installStatusItem()
        installHotKeys()
        if permissionManager.requestIfNeeded() != .granted {
            quickPanel.showUnavailable(mode: .translate, reason: .permissionRequired)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func invokeTranslate() {
        invoke(.translate)
    }

    @objc private func invokeImprove() {
        invoke(.improve)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func enableAccessibility() {
        if permissionManager.requestIfNeeded() != .granted {
            quickPanel.showUnavailable(mode: .translate, reason: .permissionRequired)
        }
    }

    @objc private func openSettings() {
        settingsWindow.present()
    }

    private func invoke(_ mode: CompanionMode) {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let accessibility = selectionProvider.capture(frontmostPID: frontmostPID)
        logger.notice("invocation mode=\(mode.rawValue, privacy: .public) ax=\(self.accessibilityCategory(accessibility), privacy: .public)")

        let clipboardFallback: ClipboardFallback
        if case .selected = accessibility {
            clipboardFallback = .unavailable
            logger.notice("clipboard fallback=skipped-ax-selected")
        } else {
            let outcome = pasteboardCapture.capture()
            clipboardFallback = outcome.clipboardFallback
            logger.notice("clipboard fallback=\(outcome.diagnosticCategory, privacy: .public)")
        }

        let result = coordinator.resolve(
            mode: mode,
            accessibility: accessibility,
            clipboardFallback: clipboardFallback
        )
        switch result {
        case let .ready(mode, text, source):
            logger.notice("invocation result=ready source=\(self.selectionSourceCategory(source), privacy: .public) chars=\(text.count, privacy: .public)")
            quickPanel.show(mode: mode, text: text, source: source)
        case let .unavailable(mode, reason):
            logger.error("invocation result=unavailable reason=\(self.unavailableReasonCategory(reason), privacy: .public)")
            quickPanel.showUnavailable(mode: mode, reason: reason)
        }
    }

    private func accessibilityCategory(_ selection: AccessibilitySelection) -> String {
        switch selection {
        case .selected: "selected"
        case .noSelection: "no-selection"
        case .permissionRequired: "permission-required"
        case .unsupported: "unsupported"
        }
    }

    private func selectionSourceCategory(_ source: SelectionSource) -> String {
        source == .accessibility ? "accessibility" : "clipboard"
    }

    private func unavailableReasonCategory(_ reason: InvocationUnavailableReason) -> String {
        switch reason {
        case .permissionRequired: "permission-required"
        case .noSelection: "no-selection"
        case .unsupported: "unsupported"
        }
    }

    private func installHotKeys() {
        do {
            let monitor = try GlobalHotKeyMonitor()
            let modifiers = UInt32(cmdKey | optionKey | controlKey)
            try monitor.register(identifier: 1, keyCode: UInt32(kVK_ANSI_1), modifiers: modifiers) { [weak self] in
                self?.invoke(.translate)
            }
            try monitor.register(identifier: 2, keyCode: UInt32(kVK_ANSI_2), modifiers: modifiers) { [weak self] in
                self?.invoke(.improve)
            }
            hotKeys = monitor
        } catch {
            quickPanel.showUnavailable(mode: .translate, reason: .unsupported)
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = SideLingoIdentity.statusItemTitle
        item.button?.toolTip = SideLingoIdentity.productName
        let menu = NSMenu()
        menu.addItem(withTitle: "Translate", action: #selector(invokeTranslate), keyEquivalent: "")
        menu.addItem(withTitle: "Improve", action: #selector(invokeImprove), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Enable Accessibility…", action: #selector(enableAccessibility), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    private func makeHistoryStore(in applicationSupportDirectory: URL) -> SQLiteHistoryStore? {
        let directory = applicationSupportDirectory.appendingPathComponent(
            SideLingoIdentity.applicationSupportDirectoryName,
            isDirectory: true
        )
        return try? SQLiteHistoryStore(path: directory.appendingPathComponent("history.sqlite").path)
    }

    private func makeProviderSettingsStore(
        in applicationSupportDirectory: URL
    ) throws -> SQLiteProviderStore {
        let directory = applicationSupportDirectory.appendingPathComponent(
            SideLingoIdentity.applicationSupportDirectoryName,
            isDirectory: true
        )
        return try SQLiteProviderStore(
            path: directory.appendingPathComponent("provider.sqlite").path
        )
    }
}
