import AppKit
import SwiftUI

struct LibrarySidebar: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var store: ShotStore

    init(model: LibraryModel) {
        self.model = model
        self.store = model.store
    }

    private struct Preset: Identifiable {
        let filter: DateFilter
        let title: LocalizedStringKey
        let symbol: String
        var id: String { filter.logName }
    }

    private let presets: [Preset] = [
        Preset(filter: .all, title: "All Screenshots", symbol: "photo.on.rectangle.angled"),
        Preset(filter: .today, title: "Today", symbol: "sun.max"),
        Preset(filter: .yesterday, title: "Yesterday", symbol: "moon"),
        Preset(filter: .last7Days, title: "Last 7 Days", symbol: "calendar.badge.clock"),
        Preset(filter: .last30Days, title: "Last 30 Days", symbol: "calendar"),
        Preset(filter: .thisMonth, title: "This Month", symbol: "calendar.circle"),
    ]

    var body: some View {
        List {
            Section("Dates") {
                ForEach(presets) { preset in
                    FilterRow(symbol: preset.symbol, count: model.count(for: preset.filter),
                              active: model.query.dateFilter == preset.filter) {
                        model.setDateFilter(preset.filter)
                    } label: {
                        Text(preset.title)
                    }
                }
                FilterRow(symbol: "calendar.day.timeline.left", count: nil, active: model.query.dateFilter.isCustom) {
                    model.applyCustomRange()
                } label: {
                    Text("Custom Range")
                }
                if model.query.dateFilter.isCustom {
                    VStack(alignment: .leading, spacing: 6) {
                        DatePicker("From", selection: $model.customFrom, displayedComponents: .date)
                        DatePicker("To", selection: $model.customTo, displayedComponents: .date)
                    }
                    .datePickerStyle(.field)
                    .font(.system(size: 12))
                    .padding(.leading, 26)
                    .onChange(of: model.customFrom) { model.applyCustomRange() }
                    .onChange(of: model.customTo) { model.applyCustomRange() }
                }
            }
            Section("Source") {
                ForEach(ShotSource.allCases) { source in
                    FilterRow(symbol: source.symbol, count: model.count(for: source),
                              active: model.query.sources.contains(source), toggle: true) {
                        model.toggleSource(source)
                    } label: {
                        Text(source.title)
                    }
                }
            }
            Section("Apps") {
                let apps = model.apps
                if apps.isEmpty {
                    Text("Apps appear after your first screenshots")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(apps, id: \.name) { app in
                        FilterRow(symbol: "app", icon: model.icon(forApp: app.name), count: app.count,
                                  active: model.query.appName == app.name) {
                            model.selectApp(model.query.appName == app.name ? nil : app.name)
                        } label: {
                            Text(verbatim: app.name)
                        }
                    }
                }
            }
            Section {
                FilterRow(symbol: "star", count: model.favoritesCount, active: model.query.favoritesOnly, toggle: true) {
                    model.toggleFavoritesOnly()
                } label: {
                    Text("Favorites")
                }
            }
        }
        .listStyle(.sidebar)
        .environment(\.calendar, .snapbar)
        .frame(minWidth: 210)
    }
}

extension ShotSource {
    var title: LocalizedStringKey {
        switch self {
        case .snapbar: return "SnapBar"
        case .native: return "macOS Screenshots"
        case .imported: return "Imported"
        }
    }

    var symbol: String {
        switch self {
        case .snapbar: return "camera.viewfinder"
        case .native: return "command"
        case .imported: return "square.and.arrow.down"
        }
    }
}

private struct FilterRow<Label: View>: View {
    let symbol: String
    var icon: NSImage?
    let count: Int?
    let active: Bool
    var toggle = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var hovering = false

    init(symbol: String, icon: NSImage? = nil, count: Int?, active: Bool, toggle: Bool = false,
         action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.symbol = symbol
        self.icon = icon
        self.count = count
        self.active = active
        self.toggle = toggle
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Group {
                    if let icon {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    } else {
                        Image(systemName: active && toggle ? "checkmark.circle.fill" : symbol)
                            .foregroundStyle(active ? Color.accentColor : Color.secondary)
                    }
                }
                .frame(width: 18)
                label()
                    .fontWeight(active ? .semibold : .regular)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count {
                    Text(verbatim: "\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(active ? Color.accentColor.opacity(0.16) : (hovering ? Color.primary.opacity(0.05) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
