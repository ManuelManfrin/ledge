import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum PanelTab: String, CaseIterable, Identifiable {
    case edges = "Bordi"
    case corners = "Angoli"
    var id: String { rawValue }
}

struct PopoverRoot: View {
    @ObservedObject private var settings = LedgeSettings.shared
    @ObservedObject private var model = AppModel.shared
    @State private var tab: PanelTab = .edges

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Picker("Sezione", selection: $tab) {
                ForEach(PanelTab.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch tab {
            case .edges:
                edges
            case .corners:
                corners
            }

            Button("Esci") { NSApp.terminate(nil) }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(width: 340)
    }

    private var edges: some View {
        VStack(alignment: .leading, spacing: 16) {
            TrackpadDiagram(
                edge: settings.edgeWidth,
                reach: settings.twoFingerEdge,
                bottomEdge: settings.bottomEdge,
                bottomReach: settings.bottomReach,
                bottomOwnsCorners: settings.cornerPriority == .bottom
            )
            if !model.note.isEmpty {
                Text(model.note)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            card {
                toggleRow(
                    "Gesti attivi",
                    "Due dita sul bordo, un dito resta il puntatore",
                    $settings.enabled
                )
                toggleRow(
                    "Richiedi ⌘",
                    "I gesti partono solo con Comando premuto",
                    $settings.requireCommand
                )
                toggleRow(
                    "Feedback aptico",
                    "Un tocco molto lieve a ogni tacca",
                    $settings.hapticsEnabled
                )
                loginRow
            }
            sliders
        }
    }

    private var corners: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Doppio tap con un dito. Play e pausa stanno sul bordo in basso, non qui.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(TrackCorner.allCases) { corner in
                VStack(alignment: .leading, spacing: 6) {
                    Text(corner.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker(corner.title, selection: settings.binding(for: corner)) {
                        ForEach(CornerAction.allCases) { action in
                            Text(action.title).tag(action)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if settings.action(for: corner) == .openApp {
                        Button(appTitle(settings.appPath(for: corner))) {
                            chooseApp(for: corner)
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 12))
                    }
                }
            }
        }
    }

    private func appTitle(_ path: String?) -> String {
        guard let path else { return "Scegli un'app…" }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    private func chooseApp(for corner: TrackCorner) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Scegli"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            settings.setAppPath(url.path, for: corner)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(width: 36, height: 36)
                .overlay(TrackpadMark().frame(width: 22, height: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text("Ledge")
                    .font(.system(size: 17, weight: .semibold))
                Text(settings.enabled ? "Lati per i livelli, basso per i media" : "In pausa")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var sliders: some View {
        VStack(alignment: .leading, spacing: 14) {
            sliderRow("Bordo laterale", value: "\(Int((settings.edgeWidth * 100).rounded()))%") {
                Slider(value: $settings.edgeWidth, in: 0.04...0.16)
            }
            sliderRow("Seconda dita, lati", value: "\(Int((settings.twoFingerEdge * 100).rounded()))%") {
                Slider(value: $settings.twoFingerEdge, in: 0.12...0.45)
            }
            sliderRow("Spessore in basso", value: "\(Int((settings.bottomEdge * 100).rounded()))%") {
                Slider(value: $settings.bottomEdge, in: 0.04...0.16)
            }
            sliderRow("Seconda dita, in basso", value: "\(Int((settings.bottomReach * 100).rounded()))%") {
                Slider(value: $settings.bottomReach, in: 0.12...0.45)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Negli angoli in basso")
                    .font(.system(size: 13))
                Text("Chi comanda dove le barre si incrociano.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Priorità", selection: $settings.cornerPriority) {
                    ForEach(CornerBarPriority.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            sliderRow("Sensibilità", value: String(format: "%.1f", settings.sensitivity)) {
                Slider(value: $settings.sensitivity, in: 0.8...3.0)
            }
            Text("⌥ durante lo slide sposta il livello di un decimo.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var loginRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            toggleRow(
                "Apri al login",
                "Resta nella barra dei menu",
                Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                )
            )
            if let loginError = settings.loginError {
                Text(loginError)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
    }

    private func sliderRow<Control: View>(_ title: String, value: String, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                Text(value)
                    .font(.system(size: 12, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            control()
                .controlSize(.small)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func toggleRow(_ title: String, _ detail: String, _ binding: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: binding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct TrackpadDiagram: View {
    var edge: Double
    var reach: Double
    var bottomEdge: Double
    var bottomReach: Double
    var bottomOwnsCorners: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                GeometryReader { geo in
                    let width = geo.size.width
                    let height = geo.size.height
                    let edgeW = max(6, width * edge)
                    let reachW = max(edgeW + 4, width * reach)
                    let edgeH = max(6, height * bottomEdge)
                    let reachH = max(edgeH + 4, height * bottomReach)
                    let sides = HStack(spacing: 0) {
                        zone(reachW, edgeW, height, Color(red: 0.92, green: 0.58, blue: 0.16), leading: true)
                        Spacer(minLength: 0)
                        zone(reachW, edgeW, height, Color(red: 0.28, green: 0.46, blue: 0.90), leading: false)
                    }
                    let bottom = ZStack(alignment: Alignment.bottom) {
                        Rectangle()
                            .fill(Color(red: 0.18, green: 0.62, blue: 0.48).opacity(0.22))
                            .frame(height: reachH)
                        Rectangle()
                            .fill(Color(red: 0.18, green: 0.62, blue: 0.48).opacity(0.9))
                            .frame(height: edgeH)
                    }
                    ZStack(alignment: .bottom) {
                        if bottomOwnsCorners {
                            sides
                            bottom
                        } else {
                            bottom
                            sides
                        }
                    }
                }
            }
            .frame(height: 126)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack {
                Text("Luminosità")
                Spacer()
                Text("Media")
                Spacer()
                Text("Volume")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    private func zone(_ reach: Double, _ edge: Double, _ height: Double, _ color: Color, leading: Bool) -> some View {
        ZStack(alignment: leading ? .leading : .trailing) {
            Rectangle().fill(color.opacity(0.18)).frame(width: reach, height: height)
            Rectangle().fill(color.opacity(0.9)).frame(width: edge, height: height)
        }
        .frame(width: reach, height: height)
    }
}

private struct TrackpadMark: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.primary, lineWidth: 1.2)
                HStack {
                    Capsule().frame(width: 2)
                    Spacer()
                    Capsule().frame(width: 2)
                }
                .padding(.horizontal, 2)
                .padding(.vertical, h * 0.22)
            }
            .frame(width: w, height: h)
        }
    }
}
