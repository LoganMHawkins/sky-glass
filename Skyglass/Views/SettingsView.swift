import SwiftUI

struct SettingsView: View {
    @Environment(SkyModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = true

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    SettingsCard(title: "View", symbol: "camera.viewfinder") {
                        SettingsToggle("Virtual sky", symbol: "hand.draw",
                                       isOn: Binding(get: { model.simulatedSky }, set: { model.virtualSky = $0 }),
                                       detail: model.motionUnavailable
                                           ? "This device has no motion sensors, so the virtual sky is always on."
                                           : "Browse by dragging instead of pointing your phone. Turns the camera and motion sensors off.")
                            .disabled(model.motionUnavailable)
                    }

                    SettingsCard(title: "Appearance", symbol: "paintpalette") {
                        HStack(spacing: 8) {
                            ForEach(AppearanceMode.allCases) { mode in
                                let on = model.appearance == mode
                                Button {
                                    withAnimation(.easeInOut(duration: 0.25)) { model.appearance = mode }
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: mode.symbol).font(.system(size: 18, weight: .semibold))
                                        Text(mode.title).font(.system(size: 12, weight: .bold, design: .rounded))
                                    }
                                    .foregroundStyle(on ? Theme.ink : Theme.ink.opacity(0.55))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .contentShape(.rect(cornerRadius: 16))
                                }
                                .buttonStyle(.plain)
                                .glassEffect(on ? .regular.tint(Theme.magenta.opacity(0.45)).interactive() : .regular.interactive(),
                                             in: .rect(cornerRadius: 16))
                            }
                        }
                        Text("The sky view always stays dark so your eyes can adjust; this changes the panels and screens around it.")
                            .settingsFootnote()
                        SettingsToggle("Boring Mode", symbol: "circle.lefthalf.striped.horizontal", isOn: $model.boringMode,
                                       detail: "Takes all the colour away. Everything, including the camera, goes black and white.")
                    }

                    SettingsCard(title: "Sky overlay", symbol: "sparkles") {
                        SettingsToggle("Constellation lines", symbol: "point.3.connected.trianglepath.dotted", isOn: $model.showConstellations)
                        SettingsToggle("Labels", symbol: "textformat", isOn: $model.showLabels)
                        SettingsToggle("Show everything below the horizon", symbol: "arrow.down.to.line", isOn: $model.showBelowHorizon,
                                       detail: "Stars, planets and every satellite on the far side of the Earth, shown faded so you can find them through the ground.")
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Stars to show", systemImage: "star")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.ink)
                            Picker("Stars to show", selection: $model.magnitudeLimit) {
                                Text("Brightest").tag(2.0)
                                Text("City sky").tag(3.5)
                                Text("Everything").tag(5.0)
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.vertical, 6)
                    }

                    SettingsCard(title: "Satellites", symbol: "antenna.radiowaves.left.and.right") {
                        SettingsToggle("Show all active satellites", symbol: "circle.grid.cross", isOn: $model.allActiveSatellites,
                                       detail: "Adds thousands of other working satellites to the Satellites layer. Most are too faint to see by eye.")
                        SettingsToggle("Only naked-eye visible", symbol: "eye", isOn: $model.onlyVisibleSatellites,
                                       detail: "Hides satellites in Earth's shadow or in daylight.")
                        ForEach(SatGroup.allCases, id: \.self) { group in
                            HStack {
                                Text(group.title.prefix(1).uppercased() + group.title.dropFirst())
                                    .foregroundStyle(Theme.ink.opacity(0.65))
                                Spacer()
                                Text(status(for: group))
                                    .foregroundStyle(Theme.ink)
                                    .monospacedDigit()
                            }
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .padding(.vertical, 4)
                        }
                        Text("Orbits come from CelesTrak and are refreshed every two hours, then calculated on your phone.")
                            .settingsFootnote()
                    }

                    SettingsCard(title: "Device", symbol: "iphone") {
                        SettingsToggle("Keep screen awake", symbol: "sun.max", isOn: $model.keepScreenAwake,
                                       detail: "Stops the screen dimming while you're stargazing.")
                        if model.zoom > 1.01 {
                            Button {
                                model.setZoom(1)
                            } label: {
                                Label("Reset zoom (\(Fmt.number(model.zoom, digits: 1))×)", systemImage: "arrow.down.right.and.arrow.up.left")
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                            }
                            .padding(.vertical, 6)
                        }
                        if model.location.denied || model.camera.denied {
                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            } label: {
                                Label("Allow camera & location in Settings", systemImage: "gear")
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                            }
                            .padding(.vertical, 6)
                        }
                    }

                    SettingsCard(title: "About", symbol: "info.circle") {
                        Text("Positions for the Sun, Moon and planets use Paul Schlyter's orbital elements; satellites are propagated with SGP4 from CelesTrak element sets. Star data is from the bright-star catalogue.")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Theme.ink.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { hasSeenWelcome = false }
                        } label: {
                            Label("Show welcome screen", systemImage: "sparkles")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                        }
                        .padding(.top, 6)
                    }

                    Wordmark(version: version)
                        .padding(.top, 18)
                        .padding(.bottom, 30)
                }
                .padding(.horizontal, 16)
            }
            .scrollContentBackground(.hidden)
            .background(SpaceBackdrop(adaptive: true).ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .boringMode()
        .presentationBackground(model.boringMode ? Theme.boringSheetBase : Theme.sheetBase)
    }

    private func status(for group: SatGroup) -> String {
        switch model.satellites.loadState[group] {
        case .loading: return "Loading…"
        case .failed: return "Couldn't load"
        case .ready: return "\(Fmt.number(Double(model.satellites.totals[group] ?? 0))) tracked"
        case nil: return group == .active ? "Off" : "Layer off"
        }
    }
}

/// The text logo at the foot of Settings.
struct Wordmark: View {
    var version: String

    var body: some View {
        VStack(spacing: 6) {
            Text("Skyglass")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .tracking(-1)
                .foregroundStyle(LinearGradient(colors: [Theme.ember, Theme.magenta, Theme.purple], startPoint: .leading, endPoint: .trailing))
                .glow(Theme.magenta, radius: 18)
            Text("SEE WHAT'S ABOVE YOU")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(3)
                .foregroundStyle(Theme.ink.opacity(0.55))
            Text(version)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Theme.ink.opacity(0.35))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(Theme.accentInk)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spacePanel(cornerRadius: 24)
    }
}

struct SettingsToggle: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool
    var detail: String?

    init(_ title: String, symbol: String, isOn: Binding<Bool>, detail: String? = nil) {
        self.title = title
        self.symbol = symbol
        self._isOn = isOn
        self.detail = detail
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: symbol)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.ink.opacity(0.5))
                }
            }
        }
        .tint(Theme.magenta)
        .padding(.vertical, 4)
    }
}

private extension View {
    func settingsFootnote() -> some View {
        font(.system(size: 12, design: .rounded))
            .foregroundStyle(Theme.ink.opacity(0.5))
            .fixedSize(horizontal: false, vertical: true)
    }
}
