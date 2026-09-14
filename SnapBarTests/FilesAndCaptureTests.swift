import AppKit
import XCTest
@testable import SnapBar

final class FileNamingTests: XCTestCase {
    func testCaptureFileNamePattern() {
        let name = FileNaming.captureFileName(for: TestCal.now)
        XCTAssertNotNil(name.range(of: #"^SnapBar \d{4}-\d{2}-\d{2} \d{2}\.\d{2}\.\d{2}\.png$"#, options: .regularExpression), name)
    }

    func testRecognizesMacScreenshotNamesInHebrewAndEnglish() {
        XCTAssertTrue(FileNaming.isNativeScreenshot(name: "צילום מסך 2026-09-09 ב-17.12.14.png"))
        XCTAssertTrue(FileNaming.isNativeScreenshot(name: "Screenshot 2026-09-09 at 17.12.14.png"))
        XCTAssertTrue(FileNaming.isNativeScreenshot(name: "Screen Shot 2020-01-01 at 10.00.00.jpg"))
        XCTAssertFalse(FileNaming.isNativeScreenshot(name: "SnapBar 2026-09-10 09.14.22.png"))
        XCTAssertFalse(FileNaming.isNativeScreenshot(name: "צילום מסך 2026-09-09 ב-17.12.14.mov"))
        XCTAssertFalse(FileNaming.isNativeScreenshot(name: ".צילום מסך temp.png"))
        XCTAssertFalse(FileNaming.isNativeScreenshot(name: "photo.png"))
    }

    func testUniqueURLAddsCounter() throws {
        let dir = TestImages.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data([1]).write(to: dir.appendingPathComponent("a.png"))
        XCTAssertEqual(FileNaming.uniqueURL(in: dir, fileName: "a.png").lastPathComponent, "a (2).png")
        XCTAssertEqual(FileNaming.uniqueURL(in: dir, fileName: "b.png").lastPathComponent, "b.png")
    }
}

final class CaptureArgumentTests: XCTestCase {
    func testAreaCaptureUsesInteractiveCrosshair() {
        XCTAssertEqual(CaptureService.arguments(mode: .area, sound: true, output: "/tmp/x.png"), ["-i", "/tmp/x.png"])
    }

    func testShutterOffAddsSilentFlag() {
        XCTAssertEqual(CaptureService.arguments(mode: .area, sound: false, output: "/tmp/x.png"), ["-i", "-x", "/tmp/x.png"])
    }

    func testWindowAndFullScreenModes() {
        XCTAssertEqual(CaptureService.arguments(mode: .window, sound: true, output: "o"), ["-i", "-W", "o"])
        XCTAssertEqual(CaptureService.arguments(mode: .fullScreen, sound: true, output: "o"), ["-m", "o"])
    }
}

final class StableFileTests: XCTestCase {
    final class SizeSequence: @unchecked Sendable {
        private var values: [Int64]
        private let lock = NSLock()
        private(set) var reads = 0

        init(_ values: [Int64]) {
            self.values = values
        }

        func next() -> Int64? {
            lock.lock()
            defer { lock.unlock() }
            reads += 1
            return values.count > 1 ? values.removeFirst() : values.first
        }
    }

    func testWaitsUntilTheFileStopsGrowing() {
        let sizes = SizeSequence([0, 100, 200, 300, 300])
        let done = expectation(description: "stable")
        StableFile.waitUntilStable(interval: 0.01, timeout: 2, queue: DispatchQueue(label: "t1"), size: { sizes.next() }) { ok in
            XCTAssertTrue(ok)
            XCTAssertEqual(sizes.reads, 5)
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
    }

    func testGivesUpWhenTheFileNeverSettles() {
        let counter = SizeSequence(Array(stride(from: Int64(1), to: 10_000, by: 1)))
        let done = expectation(description: "timeout")
        StableFile.waitUntilStable(interval: 0.01, timeout: 0.15, queue: DispatchQueue(label: "t2"), size: { counter.next() }) { ok in
            XCTAssertFalse(ok)
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
    }
}

final class PanelPlacementTests: XCTestCase {
    private let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1920, height: 1080)]

    func testPicksTheScreenUnderTheMouse() {
        XCTAssertEqual(PanelController.screenIndex(for: CGPoint(x: 2000, y: 500), frames: screens), 1)
        XCTAssertEqual(PanelController.screenIndex(for: CGPoint(x: 100, y: 100), frames: screens), 0)
    }

    func testFallsBackToTheNearestScreen() {
        XCTAssertEqual(PanelController.screenIndex(for: CGPoint(x: 5000, y: 500), frames: screens), 1)
        XCTAssertEqual(PanelController.screenIndex(for: CGPoint(x: -40, y: 10), frames: screens), 0)
        XCTAssertNil(PanelController.screenIndex(for: .zero, frames: []))
    }
}

final class ImageToolsTests: XCTestCase {
    func testFlatImageCountsAsBlank() {
        XCTAssertTrue(ImageTools.isBlank(TestImages.solid(300, 200, gray: 0)))
    }

    func testRealContentIsNotBlank() {
        let image = TestImages.make(width: 300, height: 200) { ctx in
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(CGRect(x: 40, y: 40, width: 120, height: 60))
        }
        XCTAssertFalse(ImageTools.isBlank(image))
    }

    func testDownscaleHalvesRetinaPixels() {
        let dir = TestImages.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = TestImages.writePNG(TestImages.solid(400, 200, gray: 0.5), to: dir.appendingPathComponent("r.png"))
        XCTAssertEqual(ImageTools.downscale(url: url, by: 2), CGSize(width: 200, height: 100))
        XCTAssertEqual(ImageTools.info(url: url)?.width, 200)
        XCTAssertEqual(ImageTools.info(url: url)?.height, 100)
    }
}

final class NativeLocationTests: XCTestCase {
    private let domain = "co.il.ckdigital360.snapbar.test-screencapture"

    private func read() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", domain, "location"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testSwitchWritesAndResetsTheLocation() {
        let folder = URL(fileURLWithPath: "/tmp/snapbar-location-test")
        XCTAssertTrue(NativeLocation.apply(folder: folder, domain: domain, restartUI: false))
        XCTAssertEqual(read(), folder.path)
        NativeLocation.apply(folder: nil, domain: domain, restartUI: false)
        XCTAssertNil(read())
    }
}

final class OCRTests: XCTestCase {
    func testReadsTextFromAScreenshot() {
        let dir = TestImages.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let image = TestImages.make(width: 1200, height: 300) { ctx in
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 300))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSAttributedString(string: "SNAPBAR INVOICE 2026", attributes: [
                .font: NSFont.systemFont(ofSize: 80, weight: .bold), .foregroundColor: NSColor.black,
            ]).draw(at: CGPoint(x: 40, y: 100))
            NSGraphicsContext.restoreGraphicsState()
        }
        let url = TestImages.writePNG(image, to: dir.appendingPathComponent("ocr.png"))
        let text = OCRService.recognizeSync(url: url)
        XCTAssertTrue(text.uppercased().contains("INVOICE"), text)
    }
}
