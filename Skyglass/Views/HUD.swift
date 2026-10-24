import SwiftUI

struct HUD: View {
    @Environment(SkyModel.self) private var model
    var onDetails: (String) -> Void
    var onSearch: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            TopBar(onSearch: onSearch)
            StatusChips()
            Spacer(minLength: 0)
            if let id = model.focusID, let info = model.info(for: id) {
                GlanceCard(info: info, locked: model.selectedID != nil,
                           onDetails: { onDetails(id) },
                           onClose: { withAnimation(.spring(duration: 0.35)) { model.select(nil) } })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            LayerBar()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .animation(.spring(duration: 0.4, bounce: 0.2), value: model.focusID)
    }
}

// MARK: Top bar

struct TopBar: View {
    @Environment(SkyModel.self) private var model
    var onSearch: () -> Void

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 10) {
            HeadingPill()
            Spacer(minLength: 0)
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: onSearch) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)

                    Menu {
                        Section("Overlay") {
                            Toggle("Constellation lines", systemImage: "point.3.connected.trianglepath.dotted", isOn: $model.showConstellations)
                            Toggle("Labels", systemImage: "textformat", isOn: $model.showLabels)
                            Toggle("Only naked-eye satellites", systemImage: "eye", isOn: $model.onlyVisibleSatellites)
                        }
                        Picker("Stars", systemImage: "star", selection: $model.magnitudeLimit) {
                            Text("Brightest only").tag(2.0)
                            Text("City sky").tag(3.5)
                            Text("All in catalogue").tag(5.0)
                        }
                        if model.zoom > 1.01 {
                            Button("Reset zoom", systemImage: "arrow.down.right.and.arrow.up.left") { model.setZoom(1) }
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 46, height: 46)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                }
            }
            .foregroundStyle(.white)
        }
    }
}

struct HeadingPill: View {
    @Environment(SkyModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            let look = model.lookDirection
            HStack(spacing: 9) {
                Image(systemName: "location.north.fill")
                    .foregroundStyle(Theme.ember)
                    .rotationEffect(.degrees(-look.azimuth))
                Text("\(Astro.compassPoint(look.azimuth)) \(Int(look.azimuth.rounded()) % 360)°")
                Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 14)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.rose)
                Text("\(Int(look.altitude.rounded()))°")
                if model.zoom > 1.01 {
                    Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 14)
                    Text("\(Fmt.number(model.zoom, digits: 1))×")
                }
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 46)
            .glassEffect(.regular, in: .capsule)
        }
    }
}

// MARK: Status

struct StatusChips: View {
    @Environment(SkyModel.self) private var model

    var body: some View {
        VStack(spacing: 6) {
            if model.simulatedSky {
                Chip(text: "Virtual sky — drag to look around", symbol: "hand.draw")
            } else if model.camera.denied {
                Chip(text: "Camera off — showing a virtual sky", symbol: "camera")
            }
            if model.compassNeedsCalibration {
                Chip(text: "Wave your phone in a figure-8 to calibrate", symbol: "location.north.line")
            }
            if !model.location.hasFix {
                Chip(text: model.location.denied ? "Location off — using an approximate position" : "Finding your location…", symbol: "location")
            }
            ForEach(model.activeSatGroups, id: \.self) { group in
                switch model.satellites.loadState[group] {
                case .loading: Chip(text: "Loading \(group.title)…", symbol: nil)
                case .failed:
                    Button { model.satellites.retryFailed() } label: {
                        Chip(text: "Couldn't load \(group.title) — tap to retry", symbol: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                default: EmptyView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.satellites.loadState)
    }
}

struct Chip: View {
    let text: String
    let symbol: String?

    var body: some View {
        HStack(spacing: 7) {
            if let symbol {
                Image(systemName: symbol).foregroundStyle(Theme.rose)
            } else {
                ProgressView().controlSize(.mini).tint(Theme.rose)
            }
            Text(text)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}

// MARK: Layers

struct LayerBar: View {
    @Environment(SkyModel.self) private var model

    private func count(_ layer: SkyLayer) -> String {
        switch layer {
        case .sky: return "\(model.skyObjectsUp) up"
        case .satellites, .starlink:
            let groups = layer.groups
            if groups.contains(where: { model.satellites.loadState[$0] == .loading }) { return "loading" }
            let n = groups.reduce(0) { $0 + (model.satellites.aboveHorizon[$1] ?? 0) }
            return model.layers.contains(layer) ? "\(n) up" : "off"
        }
    }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(SkyLayer.allCases) { layer in
                    let on = model.layers.contains(layer)
                    Button {
                        withAnimation(.spring(duration: 0.3)) { model.toggle(layer) }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: layer.symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .symbolEffect(.bounce, value: on)
                            Text(layer.title)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            Text(count(layer))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .opacity(0.7)
                        }
                        .foregroundStyle(on ? .white : .white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(on ? .regular.tint(layer.tint.opacity(0.5)).interactive() : .regular.interactive(), in: .capsule)
                }
            }
        }
    }
}

// MARK: Glance card

struct GlanceCard: View {
    let info: ObjectInfo
    let locked: Bool
    var onDetails: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ObjectGlyph(info: info, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.name)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(info.subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if locked {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.8))
                    .glassEffect(.regular.interactive(), in: .circle)
                } else {
                    Image(systemName: "scope")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.rose.opacity(0.8))
                }
            }

            HStack(spacing: 8) {
                ForEach(info.glance) { StatTile(stat: $0) }
            }

            Button(action: onDetails) {
                Label("Full overview", systemImage: "sparkle.magnifyingglass")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.magenta)
            .controlSize(.large)
        }
        .padding(16)
        .spacePanel()
        .shadow(color: Theme.magenta.opacity(0.35), radius: 26, y: 10)
    }
}

struct StatTile: View {
    let stat: ObjectInfo.Stat

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(stat.label.uppercased())
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Theme.rose.opacity(0.8))
            Text(stat.value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }
}

struct ObjectGlyph: View {
    let info: ObjectInfo
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [info.tint.opacity(0.55), info.tint.opacity(0)], center: .center, startRadius: 0, endRadius: size * 0.8))
                .frame(width: size * 1.6, height: size * 1.6)
            if let symbol = info.symbol {
                Circle()
                    .fill(Theme.void.opacity(0.55))
                    .overlay(Circle().strokeBorder(LinearGradient(colors: [info.tint.opacity(0.9), Theme.magenta.opacity(0.4)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                    .frame(width: size, height: size)
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(info.tint)
            } else {
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.95), info.tint, info.tint.opacity(0.35)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.65))
                    .frame(width: size, height: size)
                if info.ringed {
                    Ellipse()
                        .stroke(info.tint.opacity(0.9), lineWidth: max(1.5, size * 0.04))
                        .frame(width: size * 1.55, height: size * 0.42)
                        .rotationEffect(.degrees(-18))
                }
            }
        }
        .frame(width: size, height: size)
    }
}
