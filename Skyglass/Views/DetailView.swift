import SafariServices
import SwiftUI

struct DetailView: View {
    @Environment(SkyModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: String
    @State private var passes: [SatPass]?
    @State private var reading: LearnLink?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let info = model.info(for: id, detailed: true) {
                    VStack(spacing: 18) {
                        hero(info)
                        if let warning = info.warning { warningCard(warning) }
                        liveGrid(info)
                        if id.hasPrefix("sat:") { passesCard }
                        ForEach(info.sections) { SectionCard(section: $0) }
                        let links = model.learnLinks(for: id)
                        if !links.isEmpty { LearnMoreCard(links: links) { reading = $0 } }
                        Text("Positions are calculated on your phone from orbital elements\(id.hasPrefix("sat:") ? " published by CelesTrak" : ""), so they work offline.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(Theme.ink.opacity(0.4))
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                } else {
                    ContentUnavailableView("Not available", systemImage: "sparkles", description: Text("This object's data hasn't loaded yet."))
                        .padding(.top, 80)
                }
            }
            .scrollContentBackground(.hidden)
            .background(SpaceBackdrop(adaptive: true).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        model.select(id)
                        dismiss()
                    } label: {
                        Label("Find in sky", systemImage: "scope")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .boringMode()
        .presentationBackground(model.boringMode ? Theme.boringSheetBase : Theme.sheetBase)
        .sheet(item: $reading) { link in
            SafariView(url: link.url).ignoresSafeArea()
        }
        .task(id: id) {
            if id.hasPrefix("sat:") { passes = await model.passes(for: id) }
        }
    }

    private func hero(_ info: ObjectInfo) -> some View {
        VStack(spacing: 12) {
            ObjectGlyph(info: info, size: 92)
                .glow(info.tint, radius: 30)
                .padding(.top, 8)
                .padding(.bottom, 10)
            Text(info.name)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [Theme.ink, Theme.rose], startPoint: .top, endPoint: .bottom))
                .multilineTextAlignment(.center)
            Text(info.subtitle)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.ink.opacity(0.7))
            FlowTags(tags: info.tags)
            Text(info.blurb)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(Theme.ink.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func warningCard(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.ember)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .spacePanel(cornerRadius: 20, tint: Theme.ember)
    }

    private func liveGrid(_ info: ObjectInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(Theme.ember).frame(width: 7, height: 7).glow(Theme.ember, radius: 6)
                Text("LIVE")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Theme.accentInk)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(info.live) { StatTile(stat: $0) }
            }
        }
        .padding(16)
        .spacePanel(cornerRadius: 24)
    }

    private var passesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Upcoming passes", systemImage: "arrow.up.and.down.and.sparkles")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            if let passes {
                if passes.isEmpty {
                    Text("No passes higher than 10° in the next two days.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Theme.ink.opacity(0.6))
                }
                ForEach(passes) { pass in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Fmt.dayTime(pass.rise))
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.ink)
                            Text("\(Astro.compassPoint(pass.riseAzimuth)) → \(Astro.compassPoint(pass.setAzimuth)) · \(Int(pass.set.timeIntervalSince(pass.rise) / 60)) min")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(Theme.ink.opacity(0.6))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("max \(Fmt.deg(pass.peakAltitude, digits: 0))")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.rose)
                            Text(pass.visible ? "Visible" : "Not lit")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(pass.visible ? Theme.station : Theme.ink.opacity(0.4))
                        }
                    }
                    .padding(.vertical, 4)
                    if pass.id != passes.last?.id { Divider().overlay(Theme.ink.opacity(0.1)) }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().tint(Theme.rose)
                    Text("Predicting passes…")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Theme.ink.opacity(0.6))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spacePanel(cornerRadius: 24)
    }
}

struct SectionCard: View {
    let section: ObjectInfo.Section

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(section.title, systemImage: section.symbol)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            VStack(spacing: 0) {
                ForEach(section.rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.label)
                            .foregroundStyle(Theme.ink.opacity(0.6))
                        Spacer(minLength: 8)
                        Text(row.value)
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .padding(.vertical, 9)
                    if row.id != section.rows.last?.id { Divider().overlay(Theme.ink.opacity(0.08)) }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spacePanel(cornerRadius: 24)
    }
}

struct FlowTags: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink.opacity(0.9))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular.tint(Theme.magenta.opacity(0.2)), in: .capsule)
            }
        }
    }
}

struct LearnMoreCard: View {
    let links: [LearnLink]
    var onOpen: (LearnLink) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Learn more", systemImage: "books.vertical")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            VStack(spacing: 0) {
                ForEach(links) { link in
                    Button { onOpen(link) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: link.symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.accentInk)
                                .frame(width: 30, height: 30)
                                .background(Theme.magenta.opacity(0.15), in: .circle)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(link.title)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.ink)
                                    .multilineTextAlignment(.leading)
                                Text(link.source)
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(Theme.ink.opacity(0.5))
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.ink.opacity(0.4))
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if link.id != links.last?.id { Divider().overlay(Theme.ink.opacity(0.08)) }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spacePanel(cornerRadius: 24)
    }
}

/// In-app Safari so reading doesn't throw you out of the sky view.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(Theme.magenta)
        return vc
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
