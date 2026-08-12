import AppKit
import EnglishCompanionCore
import SwiftUI

private struct ProviderSettingsView: View {
    @ObservedObject var model: ProviderSettingsViewModel

    var body: some View {
        Form {
            LabeledContent("Provider") {
                Text("DeepSeek")
            }
            TextField("Model", text: $model.model)
            SecureField("API key (leave blank to keep existing)", text: $model.apiKey)
            HStack {
                if let statusMessage = model.statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Save") { model.save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(width: 440, height: 220)
    }
}

@MainActor
final class ProviderSettingsWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: ProviderSettingsViewModel

    init(
        settingsRepository: any ProviderSettingsRepository,
        settingsService: ProviderSettingsService
    ) {
        viewModel = ProviderSettingsViewModel(
            settingsRepository: settingsRepository,
            settingsService: settingsService
        )
        let hostingView = NSHostingView(rootView: ProviderSettingsView(model: viewModel))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "English Companion Settings"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    func windowWillClose(_ notification: Notification) {
        viewModel.dismiss()
    }

    func present() {
        viewModel.prepareForPresentation()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
