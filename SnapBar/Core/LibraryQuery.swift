import Foundation

extension Calendar {
    /// Screenshots are filed by ordinary dates. The Mac's region may prefer the Hebrew calendar,
    /// which would otherwise show "28 באלול 5786" and group "this month" by the Hebrew month.
    static let snapbar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = .current
        c.timeZone = .current
        return c
    }()
}

enum DateFilter: Hashable, Sendable {
    case all, today, yesterday, last7Days, last30Days, thisMonth
    case custom(from: Date, to: Date)

    static let presets: [DateFilter] = [.all, .today, .yesterday, .last7Days, .last30Days, .thisMonth]

    func contains(_ date: Date, now: Date = Date(), calendar: Calendar = .snapbar) -> Bool {
        switch self {
        case .all:
            return true
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .yesterday:
            guard let y = calendar.date(byAdding: .day, value: -1, to: now) else { return false }
            return calendar.isDate(date, inSameDayAs: y)
        case .last7Days:
            return date >= DateFilter.startOfDay(daysAgo: 6, now: now, calendar: calendar)
        case .last30Days:
            return date >= DateFilter.startOfDay(daysAgo: 29, now: now, calendar: calendar)
        case .thisMonth:
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        case .custom(let from, let to):
            let lower = calendar.startOfDay(for: min(from, to))
            let upperDay = calendar.startOfDay(for: max(from, to))
            guard let upper = calendar.date(byAdding: .day, value: 1, to: upperDay) else { return false }
            return date >= lower && date < upper
        }
    }

    private static func startOfDay(daysAgo: Int, now: Date, calendar: Calendar) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return calendar.startOfDay(for: day)
    }
}

enum ShotSort: String, CaseIterable, Identifiable, Sendable {
    case newestFirst, oldestFirst, largestFirst
    var id: String { rawValue }
}

struct ShotSection: Identifiable, Sendable {
    let id: String
    let day: Date?
    let shots: [Shot]
}

/// Everything the library sidebar and toolbar can narrow by. Pure, so it is unit tested.
struct LibraryQuery: Equatable, Sendable {
    var dateFilter: DateFilter = .all
    var sources: Set<ShotSource> = []
    var appName: String?
    var favoritesOnly = false
    var searchText = ""
    var sort: ShotSort = .newestFirst

    func apply(to shots: [Shot], now: Date = Date(), calendar: Calendar = .snapbar) -> [Shot] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = shots.filter { shot in
            guard dateFilter.contains(shot.createdAt, now: now, calendar: calendar) else { return false }
            if !sources.isEmpty && !sources.contains(shot.source) { return false }
            if let app = appName, shot.appName != app { return false }
            if favoritesOnly && !shot.favorite { return false }
            if !needle.isEmpty && !LibraryQuery.matches(shot, needle) { return false }
            return true
        }
        return LibraryQuery.sorted(filtered, by: sort)
    }

    static func matches(_ shot: Shot, _ needle: String) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let haystacks = [shot.ocrText ?? "", shot.fileName, shot.appName ?? ""]
        return haystacks.contains { $0.range(of: needle, options: options) != nil }
    }

    static func sorted(_ shots: [Shot], by sort: ShotSort) -> [Shot] {
        switch sort {
        case .newestFirst:
            return shots.sorted { $0.createdAt > $1.createdAt }
        case .oldestFirst:
            return shots.sorted { $0.createdAt < $1.createdAt }
        case .largestFirst:
            return shots.sorted { ($0.fileSize, $0.createdAt) > ($1.fileSize, $1.createdAt) }
        }
    }

    /// Day sections for date sorts; one flat section when sorting by size.
    static func sections(_ shots: [Shot], sort: ShotSort, calendar: Calendar = .snapbar) -> [ShotSection] {
        guard sort != .largestFirst else {
            return shots.isEmpty ? [] : [ShotSection(id: "all", day: nil, shots: shots)]
        }
        var result: [ShotSection] = []
        var currentDay: Date?
        var bucket: [Shot] = []
        for shot in shots {
            let day = calendar.startOfDay(for: shot.createdAt)
            if let current = currentDay, current != day {
                result.append(ShotSection(id: "\(Int(current.timeIntervalSince1970))", day: current, shots: bucket))
                bucket = []
            }
            currentDay = day
            bucket.append(shot)
        }
        if let current = currentDay {
            result.append(ShotSection(id: "\(Int(current.timeIntervalSince1970))", day: current, shots: bucket))
        }
        return result
    }

    static func appCounts(_ shots: [Shot]) -> [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for shot in shots {
            if let app = shot.appName, !app.isEmpty { counts[app, default: 0] += 1 }
        }
        return counts.map { (name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }

    /// Shots older than the retention window. Favorites are never expired.
    static func expired(_ shots: [Shot], now: Date = Date(), retentionDays: Int) -> [Shot] {
        guard retentionDays > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        return shots.filter { $0.createdAt < cutoff && !$0.favorite }
    }
}
