import SwiftUI

struct ObjectRef: Identifiable, Hashable { let id: String }

struct RootView: View {
    @Environment(SkyModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var detail: ObjectRef?
    @State private var showSearch = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Group {
                if model.camera.isRunning && !model.simulatedSky {
                    CameraPreview(session: model.camera.session, mono: model.boringMode, monoFrames: model.camera.monoFrames)
                    CameraTint()
                } else {
                    SpaceBackdrop(dust: 0.22)
                }
            }
            .ignoresSafeArea()

            SkyOverlay()
                .ignoresSafeArea()

            Reticle()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            HUD(onDetails: { detail = ObjectRef(id: $0) }, onSearch: { showSearch = true }, onSettings: { showSettings = true })
        }
        .task { model.start() }
        .sheet(item: $detail) { ref in
            DetailView(id: ref.id)
                .environment(model)
        }
        .sheet(isPresented: $showSearch) {
            SearchView { id in
                showSearch = false
                model.select(id)
            }
            .environment(model)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(model)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.resume() } else if phase == .background { model.pause() }
        }
    }
}

struct SkyOverlay: View {
    @Environment(SkyModel.self) private var model
    @State private var dragStart: (alt: Double, az: Double)?
    @State private var zoomStart: Double?

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    SkyRenderer(model: model).draw(&ctx, size: size, date: timeline.date)
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { model.handleTap($0.location) })
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        guard model.simulatedSky else { return }
                        let start = dragStart ?? (model.orientation.simAltitude, model.orientation.simAzimuth)
                        dragStart = start
                        let degPerPoint = model.verticalFOV / Double(geo.size.height)
                        model.orientation.simAzimuth = Astro.norm360(start.az - Double(value.translation.width) * degPerPoint)
                        model.orientation.simAltitude = min(89, max(-89, start.alt + Double(value.translation.height) * degPerPoint))
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let start = zoomStart ?? model.zoom
                        zoomStart = start
                        model.setZoom(start * Double(value.magnification))
                    }
                    .onEnded { _ in zoomStart = nil }
            )
        }
    }
}

struct Reticle: View {
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.white.opacity(0.4), lineWidth: 1)
                .frame(width: 20, height: 20)
            ForEach(0..<4) { i in
                Capsule()
                    .fill(Theme.rose.opacity(0.85))
                    .frame(width: 1.5, height: 4)
                    .offset(y: -14)
                    .rotationEffect(.degrees(Double(i) * 90))
            }
            Circle().fill(Theme.rose).frame(width: 2, height: 2)
        }
        .glow(Theme.magenta, radius: 6)
    }
}
