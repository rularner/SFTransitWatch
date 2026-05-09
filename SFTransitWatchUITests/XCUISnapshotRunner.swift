import XCTest
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

enum XCUISnapshotRunner {

    /// Pixels at the top of the captured screenshot to ignore when diffing.
    /// The watchOS system overlay (current time, sheet close button, etc.) sits in
    /// this band; including it would make every run produce different bytes (the
    /// time changes). Goldens still include the band so the App Store deliverable
    /// PNG looks like a real watch screen — only the byte-comparison ignores it.
    private static let topBarPixelsToIgnore: Int = 80

    /// Capture `app`, attach the full PNG to the test result, save the full PNG as
    /// the golden, and diff against the saved golden — ignoring the top-of-screen
    /// band where the watchOS time lives.
    ///
    /// - `RECORD_SNAPSHOTS=1` env (propagated via `SIMCTL_CHILD_RECORD_SNAPSHOTS=1`
    ///   from the shell) → overwrite golden, pass.
    /// - Golden missing → write golden + XCTFail "Recorded new snapshot, re-run to verify."
    /// - Cropped pixel buffers equal → pass.
    /// - Cropped pixel buffers differ → write `<output_dir>/<name>-failed.png`, XCTFail.
    static func verify(
        _ app: XCUIApplication,
        named name: String,
        in testCase: XCTestCase,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let screenshot = app.screenshot()
        let pngData = screenshot.pngRepresentation

        // Always attach the captured PNG to the test result.
        let attachment = XCTAttachment(data: pngData, uniformTypeIdentifier: UTType.png.identifier)
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        testCase.add(attachment)

        let goldenURL = goldenURL(for: name, file: file)
        let outputDir = outputDirectory(file: file)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let recording = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"

        if recording {
            try? FileManager.default.createDirectory(at: goldenURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            do {
                try pngData.write(to: goldenURL)
                NSLog("[XCUISnapshotRunner] Recorded golden: \(goldenURL.path)")
            } catch {
                XCTFail("Recording golden failed: \(error)", file: file, line: line)
            }
            return
        }

        guard FileManager.default.fileExists(atPath: goldenURL.path) else {
            try? FileManager.default.createDirectory(at: goldenURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            do {
                try pngData.write(to: goldenURL)
            } catch {
                XCTFail("Writing initial golden failed: \(error)", file: file, line: line)
                return
            }
            XCTFail("Recorded new snapshot at \(goldenURL.path). Re-run to verify.", file: file, line: line)
            return
        }

        guard let goldenData = try? Data(contentsOf: goldenURL) else {
            XCTFail("Could not read golden at \(goldenURL.path)", file: file, line: line)
            return
        }

        guard let newPixels = pixelBytesIgnoringTopBar(pngData) else {
            XCTFail("Could not decode captured screenshot for diffing", file: file, line: line)
            return
        }
        guard let goldenPixels = pixelBytesIgnoringTopBar(goldenData) else {
            XCTFail("Could not decode golden for diffing: \(goldenURL.path)", file: file, line: line)
            return
        }

        if newPixels == goldenPixels {
            return
        }

        let failedURL = outputDir.appendingPathComponent("\(name)-failed.png")
        do {
            try pngData.write(to: failedURL)
        } catch {
            NSLog("[XCUISnapshotRunner] Could not write failed render: \(error)")
        }
        XCTFail(
            "Snapshot \(name) differs from golden (top \(topBarPixelsToIgnore)px ignored). " +
            "Failed render: \(failedURL.path). " +
            "If this change is intentional, re-record with SIMCTL_CHILD_RECORD_SNAPSHOTS=1.",
            file: file,
            line: line
        )
    }

    // MARK: - Pixel comparison

    /// Decode `pngData` and return raw RGBA bytes for the image with the top
    /// `topBarPixelsToIgnore` rows of pixels excluded. Returning identical bytes
    /// from this function is the diff criterion.
    private static func pixelBytesIgnoringTopBar(_ pngData: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let width = cgImage.width
        let height = cgImage.height
        guard height > topBarPixelsToIgnore else { return nil }

        let croppedHeight = height - topBarPixelsToIgnore
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: croppedHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        // Draw the source image so that the image's TOP `topBarPixelsToIgnore` rows
        // are clipped away and the bottom `croppedHeight` rows are kept.
        //
        // Quartz draws images such that the image's top maps to the rect's
        // higher-y edge in CG coords (origin bottom-left). Drawing the full-height
        // image into a rect at `y: 0` places the image's bottom at the context's
        // bottom and the image's top above the context (rect top = height >
        // context top = croppedHeight) — so the top band is clipped, which is
        // what we want.
        context.draw(
            cgImage,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )

        guard let pixelDataPointer = context.data else { return nil }
        return Data(bytes: pixelDataPointer, count: bytesPerRow * croppedHeight)
    }

    // MARK: - Path resolution

    private static func goldenURL(for name: String, file: StaticString) -> URL {
        repoRoot(file: file)
            .appendingPathComponent("Snapshots", isDirectory: true)
            .appendingPathComponent("AppStore", isDirectory: true)
            .appendingPathComponent("\(name).png")
    }

    private static func outputDirectory(file: StaticString) -> URL {
        let env = ProcessInfo.processInfo.environment
        if let custom = env["SNAPSHOT_OUTPUT_DIR"] {
            return URL(fileURLWithPath: custom)
        }
        if let ciRepo = env["CI_PRIMARY_REPOSITORY_PATH"] {
            return URL(fileURLWithPath: ciRepo)
                .appendingPathComponent("Snapshots", isDirectory: true)
                .appendingPathComponent("AppStore", isDirectory: true)
        }
        if let srcroot = env["SRCROOT"] {
            return URL(fileURLWithPath: srcroot)
                .appendingPathComponent("Snapshots", isDirectory: true)
                .appendingPathComponent("AppStore", isDirectory: true)
        }
        return repoRoot(file: file)
            .appendingPathComponent("Snapshots", isDirectory: true)
            .appendingPathComponent("AppStore", isDirectory: true)
    }

    /// Walk up from this source file's path until we find a directory containing
    /// `SFTransitWatch.xcodeproj`. Used when `SRCROOT` isn't set.
    private static func repoRoot(file: StaticString) -> URL {
        if let srcroot = ProcessInfo.processInfo.environment["SRCROOT"] {
            return URL(fileURLWithPath: srcroot)
        }
        var dir = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        let fm = FileManager.default
        for _ in 0..<10 {
            let marker = dir.appendingPathComponent("SFTransitWatch.xcodeproj")
            if fm.fileExists(atPath: marker.path) {
                return dir
            }
            let parent = dir.deletingLastPathComponent()
            if parent == dir { break }
            dir = parent
        }
        return URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
    }
}
