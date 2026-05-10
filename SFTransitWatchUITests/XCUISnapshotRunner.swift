import XCTest
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

enum XCUISnapshotRunner {

    /// Pixels at the top of the captured screenshot to ignore when diffing.
    /// Above this band are: (1) the watchOS system time (changes every run),
    /// (2) the sheet close-X / chevron back button, and (3) the navigation
    /// title row. The nav title shifts ~1px when the time width changes
    /// (e.g. "3:57" -> "10:43"), so even though the title text is identical,
    /// pixel comparison sees it as different. Excluding the full title row
    /// keeps the diff focused on body content. 200 covers all four observed
    /// layouts on Apple Watch SE 3 44mm at 368x448. Goldens still include
    /// this band so the App Store deliverable PNG looks like a real watch
    /// screen.
    private static let topBarPixelsToIgnore: Int = 200

    /// Capture `app`, attach the full PNG to the test result, and diff against
    /// the bundled golden — ignoring the top-of-screen band where the watchOS
    /// time lives.
    ///
    /// Goldens live at `SFTransitWatchUITests/Goldens/<name>.png` in the source
    /// tree and ride inside the test bundle as resources, so the test process
    /// finds them via `Bundle(for:)` regardless of host filesystem layout. This
    /// is what makes the tests work on Xcode Cloud, where the build step's
    /// source paths and env vars don't propagate to the test step.
    ///
    /// - `RECORD_SNAPSHOTS=1` env (propagated via `SIMCTL_CHILD_RECORD_SNAPSHOTS=1`
    ///   from the shell) → write golden to the source tree, pass. Local-only;
    ///   on Xcode Cloud the source tree isn't reachable.
    /// - Bundled golden missing → XCTFail telling the user to record locally.
    /// - Cropped pixel buffers equal → pass.
    /// - Cropped pixel buffers differ → write `<name>-failed.png` and `<name>-diff.png`
    ///   to a temp dir, attach both, fail with pixel count + bounding box.
    static func verify(
        _ app: XCUIApplication,
        named name: String,
        in testCase: XCTestCase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let screenshot = app.screenshot()
        let pngData = screenshot.pngRepresentation

        let attachment = XCTAttachment(data: pngData, uniformTypeIdentifier: UTType.png.identifier)
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        testCase.add(attachment)

        let recording = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"

        if recording {
            let recordURL = sourceGoldenURL(for: name, file: file)
            try? FileManager.default.createDirectory(
                at: recordURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            do {
                try pngData.write(to: recordURL)
                NSLog("[XCUISnapshotRunner] Recorded golden: \(recordURL.path)")
            } catch {
                XCTFail("Recording golden to \(recordURL.path) failed: \(error)", file: file, line: line)
            }
            return
        }

        guard let goldenURL = bundledGoldenURL(for: name, testCase: testCase) else {
            XCTFail(
                """
                No bundled golden for \(name).png. Goldens live at \
                SFTransitWatchUITests/Goldens/<name>.png and ride in the test bundle. \
                Record locally with `RECORD_SNAPSHOTS=1 bin/run-watch-snapshot-tests.sh`, \
                then commit the regenerated PNGs.
                """,
                file: file,
                line: line
            )
            return
        }

        guard let goldenData = try? Data(contentsOf: goldenURL) else {
            XCTFail("Could not read bundled golden at \(goldenURL.path)", file: file, line: line)
            return
        }

        guard let new = decodeAndCropTopBar(pngData) else {
            XCTFail("Could not decode captured screenshot for diffing", file: file, line: line)
            return
        }
        guard let golden = decodeAndCropTopBar(goldenData) else {
            XCTFail("Could not decode bundled golden for diffing: \(goldenURL.path)", file: file, line: line)
            return
        }

        guard new.width == golden.width, new.height == golden.height else {
            XCTFail("""
                Snapshot \(name) dimensions differ from golden after cropping:
                  new:    \(new.width)x\(new.height)
                  golden: \(golden.width)x\(golden.height)
                """, file: file, line: line)
            return
        }

        if new.pixels == golden.pixels {
            return
        }

        let diff = computeDiff(new: new.pixels, golden: golden.pixels, width: new.width, height: new.height)

        let outputDir = outputDirectory()
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let failedURL = outputDir.appendingPathComponent("\(name)-failed.png")
        try? pngData.write(to: failedURL)

        let diffURL = outputDir.appendingPathComponent("\(name)-diff.png")
        if let diffPng = encodeRGBA(diff.diffImage, width: new.width, height: new.height) {
            try? diffPng.write(to: diffURL)
            let diffAttachment = XCTAttachment(data: diffPng, uniformTypeIdentifier: UTType.png.identifier)
            diffAttachment.name = "\(name)-diff.png"
            diffAttachment.lifetime = .keepAlways
            testCase.add(diffAttachment)
        }

        let totalPixels = new.width * new.height
        let percent = Double(diff.count) / Double(totalPixels) * 100.0
        XCTFail("""
            Snapshot \(name) differs from golden (top \(topBarPixelsToIgnore)px ignored).
              \(diff.count) / \(totalPixels) pixels differ (\(String(format: "%.3f", percent))%)
              Diff bounds (cropped coords, +y down from top of compared region): \
              x=\(diff.minX)-\(diff.maxX), y=\(diff.minY)-\(diff.maxY)
              Failed render: \(failedURL.path)
              Diff highlight: \(diffURL.path)
              Re-record (if intentional): SIMCTL_CHILD_RECORD_SNAPSHOTS=1
            """,
            file: file,
            line: line
        )
    }

    // MARK: - Decoding

    private struct CroppedImage {
        let pixels: Data
        let width: Int
        let height: Int
    }

    /// Decode `pngData` and return raw RGBA bytes for the image with the top
    /// `topBarPixelsToIgnore` rows of pixels excluded.
    private static func decodeAndCropTopBar(_ pngData: Data) -> CroppedImage? {
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
        // CG draws with origin bottom-left: drawing the full-height image at y:0
        // places its bottom flush with the context bottom and pushes its top above
        // the context's top edge, where it gets clipped.
        context.draw(
            cgImage,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )

        guard let pixelDataPointer = context.data else { return nil }
        let pixels = Data(bytes: pixelDataPointer, count: bytesPerRow * croppedHeight)
        return CroppedImage(pixels: pixels, width: width, height: croppedHeight)
    }

    // MARK: - Diff

    private struct DiffResult {
        let count: Int
        let minX: Int
        let maxX: Int
        let minY: Int
        let maxY: Int
        /// RGBA buffer, same dimensions as the inputs. Differing pixels are painted
        /// magenta; unchanged pixels are dimmed to ~33% brightness for context.
        let diffImage: Data
    }

    private static func computeDiff(new: Data, golden: Data, width: Int, height: Int) -> DiffResult {
        var count = 0
        var minX = width
        var maxX = -1
        var minY = height
        var maxY = -1
        var diff = Data(count: new.count)

        new.withUnsafeBytes { (newRaw: UnsafeRawBufferPointer) in
            golden.withUnsafeBytes { (goldenRaw: UnsafeRawBufferPointer) in
                diff.withUnsafeMutableBytes { (diffRaw: UnsafeMutableRawBufferPointer) in
                    let newPtr = newRaw.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    let goldenPtr = goldenRaw.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    let diffPtr = diffRaw.baseAddress!.assumingMemoryBound(to: UInt8.self)

                    for y in 0..<height {
                        for x in 0..<width {
                            let idx = (y * width + x) * 4
                            let differs =
                                newPtr[idx]     != goldenPtr[idx] ||
                                newPtr[idx + 1] != goldenPtr[idx + 1] ||
                                newPtr[idx + 2] != goldenPtr[idx + 2] ||
                                newPtr[idx + 3] != goldenPtr[idx + 3]

                            if differs {
                                count += 1
                                if x < minX { minX = x }
                                if x > maxX { maxX = x }
                                if y < minY { minY = y }
                                if y > maxY { maxY = y }
                                // Magenta highlight on differing pixels.
                                diffPtr[idx]     = 255
                                diffPtr[idx + 1] = 0
                                diffPtr[idx + 2] = 255
                                diffPtr[idx + 3] = 255
                            } else {
                                // Dim the original to ~33% so diffs stand out.
                                diffPtr[idx]     = newPtr[idx] / 3
                                diffPtr[idx + 1] = newPtr[idx + 1] / 3
                                diffPtr[idx + 2] = newPtr[idx + 2] / 3
                                diffPtr[idx + 3] = 255
                            }
                        }
                    }
                }
            }
        }

        return DiffResult(
            count: count,
            minX: minX, maxX: maxX,
            minY: minY, maxY: maxY,
            diffImage: diff
        )
    }

    // MARK: - PNG encoding

    private static func encodeRGBA(_ rgba: Data, width: Int, height: Int) -> Data? {
        let bytesPerRow = width * 4
        let totalBytes = bytesPerRow * height
        guard rgba.count >= totalBytes else { return nil }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: totalBytes)
        defer { buffer.deallocate() }
        _ = rgba.copyBytes(to: UnsafeMutableBufferPointer(start: buffer, count: totalBytes))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ),
        let cgImage = context.makeImage() else {
            return nil
        }

        let result = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(result, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return result as Data
    }

    // MARK: - Path resolution

    /// Locate the golden inside the test bundle. Synced groups can flatten
    /// resource subdirs or preserve them depending on Xcode behavior, so try
    /// both shapes.
    private static func bundledGoldenURL(for name: String, testCase: XCTestCase) -> URL? {
        let bundle = Bundle(for: type(of: testCase))
        if let url = bundle.url(forResource: name, withExtension: "png") {
            return url
        }
        return bundle.url(forResource: name, withExtension: "png", subdirectory: "Goldens")
    }

    /// Source-tree path for golden recording. Only meaningful locally —
    /// `RECORD_SNAPSHOTS=1` is the only caller and Xcode Cloud doesn't record.
    private static func sourceGoldenURL(for name: String, file: StaticString) -> URL {
        repoRoot(file: file)
            .appendingPathComponent("SFTransitWatchUITests", isDirectory: true)
            .appendingPathComponent("Goldens", isDirectory: true)
            .appendingPathComponent("\(name).png")
    }

    /// Where to drop diagnostic `*-failed.png` / `*-diff.png` artifacts. The
    /// canonical copy is the XCTAttachment; the on-disk write is for local
    /// inspection. Temp dir is writable everywhere (host, simulator, CI).
    private static func outputDirectory() -> URL {
        if let custom = ProcessInfo.processInfo.environment["SNAPSHOT_OUTPUT_DIR"] {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SFTransitWatchSnapshots", isDirectory: true)
    }

    /// Resolve the project's repo root for golden *recording* (write side).
    /// Read side uses `Bundle(for:)` and never calls this.
    ///
    /// Walks up from `#filePath` (the literal compile-time path) looking for
    /// `SFTransitWatch.xcodeproj`. Locally this succeeds; on Xcode Cloud it
    /// may not — but recording isn't done there.
    private static func repoRoot(file: StaticString) -> URL {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
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
