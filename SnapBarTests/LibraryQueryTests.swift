import XCTest
@testable import SnapBar

final class LibraryQueryTests: XCTestCase {
    private let now = TestCal.now
    private let cal = TestCal.calendar

    private func shot(_ hoursAgo: Double, _ source: ShotSource = .snapbar, app: String? = nil, size: Int64 = 100,
                      favorite: Bool = false, ocr: String? = nil, name: String? = nil) -> Shot {
        Shot(path: "/tmp/\(name ?? UUID().uuidString).png", createdAt: now.addingTimeInterval(-hoursAgo * 3600),
             source: source, appName: app, fileSize: size, ocrText: ocr, favorite: favorite)
    }

    private func run(_ query: LibraryQuery, _ shots: [Shot]) -> [Shot] {
        query.apply(to: shots, now: now, calendar: cal)
    }

    func testSourceFilter() {
        let shots = [shot(1, .snapbar), shot(2, .native), shot(3, .imported)]
        var q = LibraryQuery()
        q.sources = [.native, .imported]
        XCTAssertEqual(run(q, shots).map(\.source), [.native, .imported])
    }

    func testAppFilter() {
        let shots = [shot(1, app: "Safari"), shot(2, app: "Slack"), shot(3, app: "Safari")]
        var q = LibraryQuery()
        q.appName = "Safari"
        XCTAssertEqual(run(q, shots).count, 2)
    }

    func testFavoritesOnly() {
        let shots = [shot(1, favorite: true), shot(2), shot(3, favorite: true)]
        var q = LibraryQuery()
        q.favoritesOnly = true
        XCTAssertEqual(run(q, shots).count, 2)
    }

    func testDateSourceAndAppCombine() {
        let match = shot(2, .native, app: "Slack")
        let shots = [match, shot(2, .snapbar, app: "Slack"), shot(2, .native, app: "Mail"), shot(60, .native, app: "Slack")]
        var q = LibraryQuery()
        q.dateFilter = .today
        q.sources = [.native]
        q.appName = "Slack"
        XCTAssertEqual(run(q, shots).map(\.id), [match.id])
    }

    func testSearchFindsTextInsideThePictureIgnoringCase() {
        let hit = shot(1, ocr: "Invoice total 480 ILS\nחשבונית מס")
        let shots = [hit, shot(2, ocr: "dashboard"), shot(3)]
        var q = LibraryQuery()
        q.searchText = "INVOICE"
        XCTAssertEqual(run(q, shots).map(\.id), [hit.id])
        q.searchText = "חשבונית"
        XCTAssertEqual(run(q, shots).map(\.id), [hit.id])
    }

    func testThreeSortOrders() {
        let old = shot(30, size: 900)
        let mid = shot(10, size: 100)
        let new = shot(1, size: 500)
        let shots = [mid, old, new]
        XCTAssertEqual(LibraryQuery.sorted(shots, by: .newestFirst).map(\.id), [new.id, mid.id, old.id])
        XCTAssertEqual(LibraryQuery.sorted(shots, by: .oldestFirst).map(\.id), [old.id, mid.id, new.id])
        XCTAssertEqual(LibraryQuery.sorted(shots, by: .largestFirst).map(\.id), [old.id, new.id, mid.id])
    }

    func testSectionsGroupByDay() {
        let shots = LibraryQuery.sorted([shot(1), shot(2), shot(26), shot(27), shot(60)], by: .newestFirst)
        let sections = LibraryQuery.sections(shots, sort: .newestFirst, calendar: cal)
        XCTAssertEqual(sections.map(\.shots.count), [2, 2, 1])
        XCTAssertEqual(Set(sections.map(\.id)).count, 3)
    }

    func testSizeSortIsOneFlatSection() {
        let sections = LibraryQuery.sections([shot(1), shot(40)], sort: .largestFirst, calendar: cal)
        XCTAssertEqual(sections.count, 1)
        XCTAssertNil(sections.first?.day)
    }

    func testAppCountsMostUsedFirst() {
        let shots = [shot(1, app: "Slack"), shot(2, app: "Safari"), shot(3, app: "Slack"), shot(4)]
        let counts = LibraryQuery.appCounts(shots)
        XCTAssertEqual(counts.map(\.name), ["Slack", "Safari"])
        XCTAssertEqual(counts.map(\.count), [2, 1])
    }

    func testRetentionKeepsFavoritesAndRecentShots() {
        let old = shot(24 * 40)
        let oldFavorite = shot(24 * 40, favorite: true)
        let recent = shot(24 * 5)
        let expired = LibraryQuery.expired([old, oldFavorite, recent], now: now, retentionDays: 30)
        XCTAssertEqual(expired.map(\.id), [old.id])
        XCTAssertTrue(LibraryQuery.expired([old], now: now, retentionDays: 0).isEmpty)
    }
}
