import AppKit
import XCTest
@testable import SnapBar

@MainActor
final class StoreTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = TestImages.tempDir()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func image(_ name: String) -> URL {
        TestImages.writePNG(TestImages.solid(20, 10, gray: 0.4), to: dir.appendingPathComponent(name))
    }

    private func shot(_ url: URL, _ source: ShotSource = .snapbar) -> Shot {
        Shot(path: url.path, createdAt: Date(), source: source)
    }

    func testIndexSurvivesARestart() {
        let index = dir.appendingPathComponent("history.json")
        let store = ShotStore(indexURL: index)
        store.add(shot(image("a.png")))
        store.add(shot(image("b.png")))
        store.saveNowAndWait()
        let reopened = ShotStore(indexURL: index)
        reopened.load()
        XCTAssertEqual(reopened.shots.count, 2)
    }

    func testFilesDeletedOutsideSnapBarDropOut() throws {
        let index = dir.appendingPathComponent("history.json")
        let store = ShotStore(indexURL: index)
        let keep = image("keep.png")
        let gone = image("gone.png")
        store.add(shot(keep))
        store.add(shot(gone))
        store.saveNowAndWait()
        try FileManager.default.removeItem(at: gone)
        let reopened = ShotStore(indexURL: index)
        reopened.load()
        XCTAssertEqual(reopened.shots.map(\.path), [keep.path])
    }

    func testFavoritesPersist() {
        let index = dir.appendingPathComponent("history.json")
        let store = ShotStore(indexURL: index)
        let s = shot(image("fav.png"))
        store.add(s)
        store.setFavorite([s.id], true)
        store.saveNowAndWait()
        let reopened = ShotStore(indexURL: index)
        reopened.load()
        XCTAssertEqual(reopened.shots.first?.favorite, true)
    }

    func testOnlyImageFilesAreIndexed() {
        let store = ShotStore(indexURL: dir.appendingPathComponent("history.json"))
        store.add(Shot(path: dir.appendingPathComponent("notes.txt").path, createdAt: Date(), source: .snapbar))
        store.add(shot(image("pic.png")))
        XCTAssertEqual(store.shots.count, 1)
    }

    func testImportMovesScreenshotsAndSkipsOtherFiles() throws {
        let source = dir.appendingPathComponent("Desktop", isDirectory: true)
        let dest = dir.appendingPathComponent("Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        for i in 1...5 {
            TestImages.writePNG(TestImages.solid(10, 10, gray: 0.2), to: source.appendingPathComponent("צילום מסך 2026-09-0\(i) ב-10.00.0\(i).png"))
        }
        try Data("x".utf8).write(to: source.appendingPathComponent("notes.txt"))
        let candidates = ShotStore.importCandidates(in: source)
        XCTAssertEqual(candidates.count, 5)
        let store = ShotStore(indexURL: dir.appendingPathComponent("history.json"))
        let added = store.importFiles(candidates, into: dest)
        XCTAssertEqual(added.count, 5)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dest.path).count, 5)
        XCTAssertEqual(ShotStore.importCandidates(in: source).count, 0)
        XCTAssertTrue(store.shots.allSatisfy { $0.source == .imported })
    }
}

@MainActor
final class SettingsTests: XCTestCase {
    private var suite = ""

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func fresh() -> UserDefaults {
        suite = "co.il.ckdigital360.snapbar.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    func testFreshInstallDefaults() {
        let settings = AppSettings(defaults: fresh())
        XCTAssertEqual(settings.captureAreaHotkey, .defaultCaptureArea)
        XCTAssertEqual(settings.libraryHotkey, .defaultLibrary)
        XCTAssertFalse(settings.redirectNativeLocation)
        XCTAssertTrue(settings.watchNativeScreenshots)
        XCTAssertTrue(settings.panelEnabled)
        XCTAssertEqual(settings.panelAutoHideSeconds, 0)
        XCTAssertEqual(settings.panelCorner, .bottomLeft)
        XCTAssertFalse(settings.downscaleRetina)
        XCTAssertTrue(settings.shutterSound)
        XCTAssertEqual(settings.retentionDays, 0)
        XCTAssertTrue(settings.saveFolderPath.hasSuffix("Pictures/Screenshots"))
    }

    func testClearedShortcutStaysCleared() {
        let defaults = fresh()
        let settings = AppSettings(defaults: defaults)
        settings.captureAreaHotkey = nil
        XCTAssertNil(AppSettings(defaults: defaults).captureAreaHotkey)
    }

    func testChangesPersist() {
        let defaults = fresh()
        let settings = AppSettings(defaults: defaults)
        settings.panelCorner = .topRight
        settings.panelAutoHideSeconds = 5
        settings.retentionDays = 30
        let reopened = AppSettings(defaults: defaults)
        XCTAssertEqual(reopened.panelCorner, .topRight)
        XCTAssertEqual(reopened.panelAutoHideSeconds, 5)
        XCTAssertEqual(reopened.retentionDays, 30)
    }
}

final class EditorTests: XCTestCase {
    func testTwentyStepsUndoAndRedoCompletely() {
        var history = EditHistory(0)
        for i in 1...20 { history.commit(i) }
        XCTAssertEqual(history.current, 20)
        for _ in 0..<20 { XCTAssertTrue(history.undo()) }
        XCTAssertEqual(history.current, 0)
        XCTAssertFalse(history.undo())
        for _ in 0..<20 { XCTAssertTrue(history.redo()) }
        XCTAssertEqual(history.current, 20)
        XCTAssertFalse(history.redo())
    }

    func testNewEditClearsRedo() {
        var history = EditHistory(0)
        history.commit(1)
        history.commit(2)
        history.undo()
        history.commit(9)
        XCTAssertFalse(history.canRedo)
        XCTAssertEqual(history.current, 9)
    }

    func testRendererKeepsPixelSizeAndDrawsInImageCoordinates() throws {
        let base = TestImages.solid(200, 100, gray: 1)
        let mark = Annotation(kind: .rectangle(CGRect(x: 20, y: 20, width: 60, height: 40)), color: RGBA.palette[0], lineWidth: 4)
        let out = try XCTUnwrap(AnnotationRenderer.render(image: base, state: EditorState(annotations: [mark])))
        XCTAssertEqual(out.width, 200)
        XCTAssertEqual(out.height, 100)
        let edge = TestImages.pixel(out, x: 20, y: 40)
        XCTAssertGreaterThan(edge.r, 200)
        XCTAssertLessThan(edge.g, 120)
        let inside = TestImages.pixel(out, x: 50, y: 40)
        XCTAssertGreaterThan(inside.g, 240)
        let outside = TestImages.pixel(out, x: 150, y: 80)
        XCTAssertGreaterThan(outside.g, 240)
    }

    func testCropSetsOutputSize() throws {
        let base = TestImages.solid(200, 100, gray: 1)
        var state = EditorState()
        state.crop = CGRect(x: 10, y: 10, width: 100, height: 50)
        let out = try XCTUnwrap(AnnotationRenderer.render(image: base, state: state))
        XCTAssertEqual(out.width, 100)
        XCTAssertEqual(out.height, 50)
    }

    func testBlurHidesDetail() throws {
        let stripes = TestImages.make(width: 120, height: 120) { ctx in
            for x in stride(from: 0, to: 120, by: 2) {
                ctx.setFillColor(CGColor(gray: x % 4 == 0 ? 0 : 1, alpha: 1))
                ctx.fill(CGRect(x: x, y: 0, width: 2, height: 120))
            }
        }
        let blur = Annotation(kind: .blur(CGRect(x: 0, y: 0, width: 120, height: 120)), color: RGBA.palette[0], lineWidth: 4)
        let out = try XCTUnwrap(AnnotationRenderer.render(image: stripes, state: EditorState(annotations: [blur])))
        let a = TestImages.pixel(out, x: 1, y: 60)
        let b = TestImages.pixel(out, x: 3, y: 60)
        XCTAssertLessThan(abs(a.r - b.r), 40)
    }

    func testToolKeys() {
        XCTAssertEqual(EditorTool.tool(forKey: "a"), .arrow)
        XCTAssertEqual(EditorTool.tool(forKey: "R"), .rectangle)
        XCTAssertEqual(EditorTool.tool(forKey: "o"), .ellipse)
        XCTAssertEqual(EditorTool.tool(forKey: "p"), .pen)
        XCTAssertEqual(EditorTool.tool(forKey: "t"), .text)
        XCTAssertEqual(EditorTool.tool(forKey: "b"), .blur)
        XCTAssertEqual(EditorTool.tool(forKey: "c"), .crop)
        XCTAssertNil(EditorTool.tool(forKey: "z"))
    }

    func testStepNumbersCountUp() {
        var state = EditorState()
        XCTAssertEqual(state.nextStepNumber, 1)
        state.annotations.append(Annotation(kind: .step(1, at: .zero), color: RGBA.palette[0], lineWidth: 4))
        state.annotations.append(Annotation(kind: .step(2, at: .zero), color: RGBA.palette[0], lineWidth: 4))
        XCTAssertEqual(state.nextStepNumber, 3)
    }
}
