import AppKit
import EnglishCompanionCore
import SwiftUI

struct QuickPanelView: View {
    @ObservedObject var model: QuickPanelViewModel

    private let panel = Color(hex: 0x12141B).opacity(0.96)
    private let footer = Color(hex: 0x0B0D12).opacity(0.88)
    private let border = Color.white.opacity(0.105)
    private let borderSoft = Color.white.opacity(0.07)
    private let text = Color(hex: 0xF5F3FB)
    private let muted = Color(hex: 0xA09BAA)
    private let accent = Color(hex: 0xB99CFF)
    private let green = Color(hex: 0x7BD9AD)

    var body: some View {
        VStack(spacing: 0) {
            inputShell
            divider
            sourcePreview
            divider
            resultRegion
            divider
            statusBar
        }
        .frame(width: 780, height: CGFloat(QuickPanelInputPresentation.panelHeight))
        .background(
            ZStack {
                AppKitVisualEffect(material: .hudWindow, blendingMode: .behindWindow)
                panel
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.52), radius: 50, x: 0, y: 26)
        .environment(\.colorScheme, .dark)
    }

    private var inputShell: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(model.mode == .translate ? "译" : "优")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(model.mode == .translate ? Color(hex: 0xE9DEFF) : Color(hex: 0xD8FFF1))
                .frame(width: 40, height: 40)
                .background(
                    LinearGradient(
                        colors: model.mode == .translate
                            ? [accent.opacity(0.25), Color(hex: 0x7252C4).opacity(0.12)]
                            : [green.opacity(0.20), Color(hex: 0x287A60).opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(model.mode == .translate ? accent.opacity(0.28) : green.opacity(0.28), lineWidth: 1)
                )

            TextField("Enter or paste text", text: $model.input)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(text)
                .lineLimit(QuickPanelInputPresentation.editorLineLimit)
                .truncationMode(.tail)
                .disabled(model.isLoading)
                .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .center)

            Button(action: { model.onRun?() }) {
                HStack(spacing: 8) {
                    Text(model.isLoading ? "Running…" : "Run")
                    keycap("⌘↵")
                }
                .frame(height: 34)
                .padding(.horizontal, 11)
            }
            .buttonStyle(PanelButtonStyle(accent: true))
            .disabled(model.isLoading)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(height: 72)
    }

    private var sourcePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(QuickPanelInputPresentation.previewTitle, primary: false)
            ScrollView {
                Text(model.input)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(hex: 0xD8D3DE))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .frame(height: 96, alignment: .topLeading)
        .background(Color.black.opacity(0.08))
    }

    private var resultRegion: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionLabel(primaryTitle, primary: true)
                    Spacer()
                    Button(action: { model.onCopy?() }) {
                        HStack(spacing: 6) {
                            Text("Copy")
                            if let shortcutKeycap = QuickPanelResultPresentation.copyButtonKeycap {
                                keycap(shortcutKeycap)
                            }
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                    }
                    .buttonStyle(PanelButtonStyle())
                    .disabled(!model.isCopyEnabled)
                }
                if !model.output.primary.isEmpty {
                    Text(model.output.primary)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(text)
                        .lineSpacing(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if model.isLoading {
                    ProgressView("Processing with DeepSeek…")
                        .controlSize(.small)
                        .foregroundStyle(muted)
                }
            }

            divider

            VStack(alignment: .leading, spacing: 10) {
                sectionLabel(model.output.secondaryTitle, primary: false)
                Text(model.output.secondary)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color(hex: 0xDDD9E3))
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                actionChip("Make shorter")
                actionChip("More polite")
                actionChip("Explain wording")
                Spacer()
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(ResultTextSelectionModifier())
    }

    private var statusBar: some View {
        HStack(spacing: 5) {
            statusPill(model.mode == .translate ? "Translate" : "Improve", accent: true)
            statusPill(model.source)
            HStack(spacing: 6) {
                Circle().fill(green).frame(width: 6, height: 6)
                Text("DeepSeek")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(muted)
            .padding(.horizontal, 7)
            .frame(height: 28)

            Spacer(minLength: 10)

            Button("●  Review  17") { model.onPlaceholderAction?() }
                .buttonStyle(FooterButtonStyle(accent: true))
            Button("⌘O  Open in Window") { model.onPlaceholderAction?() }
                .buttonStyle(FooterButtonStyle())
            Button("Esc  Hide") { model.onHide?() }
                .buttonStyle(FooterButtonStyle())
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(footer)
    }

    private var primaryTitle: String {
        QuickPanelResultPresentation.primaryTitle(
            mode: model.mode,
            inputUnavailable: model.unavailableMessage != nil
        )
    }

    private var divider: some View {
        Rectangle().fill(borderSoft).frame(height: 1)
    }

    private func sectionLabel(_ value: String, primary: Bool) -> some View {
        Text(value.uppercased())
            .font(.system(size: 12, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(primary ? Color(hex: 0xCFC0FB) : Color(hex: 0xB2ABB9))
    }

    private func actionChip(_ title: String) -> some View {
        Button(title) { model.onPlaceholderAction?() }
            .buttonStyle(ChipButtonStyle())
            .disabled(model.isLoading || model.output.primary.isEmpty)
    }

    private func statusPill(_ title: String, accent isAccent: Bool = false) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isAccent ? Color(hex: 0xC5B4F1) : muted)
            .padding(.horizontal, 7)
            .frame(height: 28)
            .background(isAccent ? accent.opacity(0.07) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func keycap(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color(hex: 0xC7C1D0))
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct ResultTextSelectionModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if QuickPanelResultPresentation.textSelectionEnabled {
            content.textSelection(.enabled)
        } else {
            content.textSelection(.disabled)
        }
    }
}

private struct PanelButtonStyle: ButtonStyle {
    var accent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(accent ? Color(hex: 0xE1D7F4) : Color(hex: 0xBBB5C5))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent ? Color(hex: 0xB99CFF).opacity(configuration.isPressed ? 0.18 : 0.10) : Color.white.opacity(configuration.isPressed ? 0.09 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(accent ? Color(hex: 0xB99CFF).opacity(0.28) : Color.white.opacity(0.105), lineWidth: 1)
            )
    }
}

private struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color(hex: 0xBBB4C2))
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(Color.white.opacity(configuration.isPressed ? 0.07 : 0.025))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.105), lineWidth: 1))
    }
}

private struct FooterButtonStyle: ButtonStyle {
    var accent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(accent ? Color(hex: 0xD0C2F4) : Color(hex: 0xB2ABB8))
            .padding(.horizontal, 7)
            .frame(height: 28)
            .background(accent ? Color(hex: 0xB99CFF).opacity(0.075) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct AppKitVisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

private extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
