import SwiftUI

/// First-launch welcome: what Skyglass does, in three lines, then straight to the sky.
struct WelcomeView: View {
    var onContinue: () -> Void

    var body: some View {
        GeometryReader { geo in
            ViewThatFits(in: .vertical) {
                content(compact: false)
                content(compact: true)
            }
            .frame(maxWidth: 520)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(SpaceBackdrop(dust: 0.6).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func content(compact: Bool) -> some View {
        VStack(spacing: compact ? 18 : 28) {
            Spacer(minLength: 0)

            OrbitingIcon(size: compact ? 76 : 96)
                .modifier(WelcomeEntrance(order: 0))
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Welcome to Skyglass")
                    .font(.system(compact ? .title : .largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                    .modifier(WelcomeEntrance(order: 1))
                Text("The sky above you, explained.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .modifier(WelcomeEntrance(order: 1.4))
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: compact ? 16 : 22) {
                feature("camera.viewfinder", Theme.rose, "Point and discover",
                        "Hold up your phone to name every star, planet and galaxy.", order: 2)
                feature("antenna.radiowaves.left.and.right", Theme.blue, "Track what's flying",
                        "The ISS, thousands of satellites and every Starlink, live.", order: 3)
                feature("globe.americas.fill", Theme.purple, "See the whole planet",
                        "Spin the globe to find any satellite, anywhere.", order: 4)
            }
            .frame(maxWidth: 420, alignment: .leading)

            Spacer(minLength: 0)

            VStack(spacing: 14) {
                Label("Your camera and location never leave your phone.", systemImage: "lock.fill")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .modifier(WelcomeEntrance(order: 5))
                Button(action: onContinue) {
                    Text("Look Up")
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.purple)
                .controlSize(.large)
                .modifier(WelcomeEntrance(order: 6))
            }
            .frame(maxWidth: 420)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, compact ? 20 : 32)
    }

    private func feature(_ symbol: String, _ tint: Color, _ title: String, _ detail: String, order: Int) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(.title2, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .modifier(WelcomeSymbolEntrance(order: order))
                .frame(width: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                    .modifier(WelcomeEntrance(order: Double(order)))
                Text(detail)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .modifier(WelcomeEntrance(order: Double(order) + 0.4))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The app icon with a satellite tracing a tilted orbit around it.
private struct OrbitingIcon: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let angle = t * 0.9
            let rx = size * 0.95, ry = size * 0.3, tilt = -0.35
            // Point on a tilted ellipse; the far half passes behind the icon.
            let px = rx * cos(angle), py = ry * sin(angle)
            let x = px * cos(tilt) - py * sin(tilt), y = px * sin(tilt) + py * cos(tilt)
            let behind = sin(angle) < 0
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Theme.magenta.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: size))
                    .frame(width: size * 2, height: size * 2)
                Ellipse()
                    .stroke(Theme.rose.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .frame(width: rx * 2, height: ry * 2)
                    .rotationEffect(.radians(tilt))
                if behind { satellite.offset(x: x, y: y) }
                Image("AppIconPreview")
                    .resizable()
                    .frame(width: size, height: size)
                    .clipShape(.rect(cornerRadius: size * 0.225, style: .continuous))
                    .shadow(color: Theme.magenta.opacity(0.4), radius: 18, y: 6)
                    .offset(y: reduceMotion ? 0 : sin(t * 1.2) * 3)
                if !behind { satellite.offset(x: x, y: y) }
            }
            .frame(width: size * 2, height: size * 1.3)
        }
    }

    private var satellite: some View {
        Canvas { ctx, s in
            SatelliteArt.draw(.generic, in: &ctx, at: CGPoint(x: s.width / 2, y: s.height / 2), halfWidth: 9, angle: 0.4, opacity: 1, detailed: true)
        }
        .frame(width: 22, height: 22)
        .shadow(color: Theme.station.opacity(0.8), radius: 6)
    }
}

/// Fade and rise in, staggered by `order`.
private struct WelcomeEntrance: ViewModifier {
    let order: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 10)
            .task {
                do {
                    if !reduceMotion { try await Task.sleep(for: .seconds(0.35 + order * 0.14)) }
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.65)) { visible = true }
                } catch {
                    // Dismissal cancels the entrance.
                }
            }
    }
}

/// Draw each feature symbol on just after its title starts to appear.
private struct WelcomeSymbolEntrance: ViewModifier {
    let order: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    func body(content: Content) -> some View {
        content
            .symbolEffect(.drawOn.byLayer, options: .speed(1.0), isActive: !revealed && !reduceMotion)
            .task {
                guard !reduceMotion else {
                    revealed = true
                    return
                }
                do {
                    try await Task.sleep(for: .seconds(0.49 + Double(order) * 0.3))
                    revealed = true
                } catch {
                    // Dismissal cancels the entrance.
                }
            }
    }
}
