import SwiftUI

struct SearchView: View {
    @Environment(SkyModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onPick: (String) -> Void

    @State private var query = ""
    @State private var layer: SkyLayer? = nil

    private var items: [SkyModel.SearchItem] {
        let all = model.searchItems(for: layer)
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(all.prefix(400)) }
        // Name matches first, then matches on the catalogue line.
        let byName = all.filter { $0.name.localizedCaseInsensitiveContains(q) }
        let byDetail = all.filter { !$0.name.localizedCaseInsensitiveContains(q) && $0.detail.localizedCaseInsensitiveContains(q) }
        return Array((byName + byDetail).prefix(400))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Layer", selection: $layer) {
                        Text("All").tag(SkyLayer?.none)
                        ForEach(SkyLayer.allCases) { Text($0.title).tag(SkyLayer?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                ForEach(items) { item in
                    Button { onPick(item.id) } label: { row(item) }
                        .listRowBackground(Color.white.opacity(0.05))
                }
            }
            .scrollContentBackground(.hidden)
            .background(SpaceBackdrop().ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Stars, planets, ISS, Starlink…")
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationBackground(Theme.void)
    }

    private func row(_ item: SkyModel.SearchItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(item.tint.opacity(0.14)).frame(width: 34, height: 34)
                if let art = item.art {
                    ArtView(art: art, size: 24)
                } else {
                    Image(systemName: item.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(item.tint)
                }
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(item.detail)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            if let alt = item.altitude {
                Text(alt > 0 ? "↑ \(Int(alt.rounded()))°" : "below")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(alt > 0 ? Theme.rose : .white.opacity(0.35))
            }
        }
        .contentShape(Rectangle())
    }
}
