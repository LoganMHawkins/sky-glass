#if DEBUG
import SwiftUI

/// Every piece of artwork side by side, for tuning the designs.
/// Launch with the `-artGallery` argument to open it instead of the sky.
struct ArtGallery: View {
    private let bodies: [(String, ObjectArt)] = [
        ("Sun", .sun), ("Moon 70%", .moon(illumination: 0.7, waxing: true)), ("Mercury", .planet(.mercury, ringTilt: 0)),
        ("Venus", .planet(.venus, ringTilt: 0)), ("Mars", .planet(.mars, ringTilt: 0)), ("Jupiter", .planet(.jupiter, ringTilt: 0)),
        ("Saturn 2026", .planet(.saturn, ringTilt: -4)), ("Saturn open", .planet(.saturn, ringTilt: 26)), ("Uranus", .planet(.uranus, ringTilt: 0)),
        ("Neptune", .planet(.neptune, ringTilt: 0)),
    ]
    private let stars: [(String, String)] = [("O9.5Ib", "Alnitak"), ("B8Ia", "Rigel"), ("A1V", "Sirius"), ("F5IV", "Procyon"),
                                             ("G2V", "Sun-like"), ("K1.5III", "Arcturus"), ("K5III", "Aldebaran"), ("M1Ia", "Betelgeuse")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section("Solar System") {
                    ForEach(bodies, id: \.0) { item in tile(item.0) { ArtView(art: item.1, size: 64) } }
                }
                section("Stars") {
                    ForEach(stars, id: \.0) { item in tile("\(item.1)\n\(item.0)") { ArtView(art: .star(StarColor.color(item.0)), size: 64) } }
                }
                section("Spacecraft") {
                    ForEach(SatDesign.allCases, id: \.self) { d in
                        tile(d.title) {
                            ZStack {
                                Circle().fill(Theme.void.opacity(0.6)).frame(width: 64, height: 64)
                                ArtView(art: .satellite(d), size: 64)
                            }
                        }
                    }
                }
                section("Overlay size") {
                    ForEach(SatDesign.allCases, id: \.self) { d in
                        tile(d.title) {
                            Canvas { ctx, size in
                                SatelliteArt.draw(d, in: &ctx, at: CGPoint(x: size.width / 2, y: size.height / 2),
                                                  halfWidth: d.overlayHalfWidth, angle: 0.3, opacity: 1, detailed: false,
                                                  silhouette: d.isStarlink ? Theme.starlink : Theme.satellite)
                            }
                            .frame(width: 64, height: 40)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(SpaceBackdrop().ignoresSafeArea())
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(Theme.rose)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 18, content: content)
        }
    }

    private func tile<Art: View>(_ name: String, @ViewBuilder art: () -> Art) -> some View {
        VStack(spacing: 8) {
            art().frame(width: 72, height: 72)
            Text(name).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center).lineLimit(2)
        }
    }
}
#endif
