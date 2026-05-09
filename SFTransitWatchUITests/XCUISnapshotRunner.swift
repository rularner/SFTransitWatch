import XCTest

enum XCUISnapshotRunner {

    /// Capture the app's element contents (excluding the watchOS system time bar),
    /// attach to the test result, and diff against `Snapshots/AppStore/<name>.png`.
    ///
    /// - `RECORD_SNAPSHOTS=1` env (propagated via `SIMCTL_CHILD_RECORD_SNAPSHOTS=1` from
    ///   the shell) → overwrite golden, pass.
    /// - Golden missing → write golden + XCTFail "Recorded new snapshot, re-run to verify."
    /// - Bytes equal → pass.
    /// - Bytes differ → write `<output_dir>/<name>-failed.png`, XCTFail with diff message.
    ///
    /// Note: we screenshot `app` (the XCUIApplication) rather than `XCUIScreen.main`
    /// because the watchOS system status bar (which shows the live time) sits outside
    /// the app's element bounds. Using `XCUIScreen.main.screenshot()` would include the
    /// time and produce non-deterministic byte diffs across runs.
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
        let attachment = XCTAttachment(data: pngData, uniformTypeIdentifier: "public.png")
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

        if pngData == goldenData {
            return
        }

        let failedURL = outputDir.appendingPathComponent("\(name)-failed.png")
        do {
            try pngData.write(to: failedURL)
        } catch {
            NSLog("[XCUISnapshotRunner] Could not write failed render: \(error)")
        }
        XCTFail(
            "Snapshot \(name) differs from golden. Failed render: \(failedURL.path). " +
            "If this change is intentional, re-record with SIMCTL_CHILD_RECORD_SNAPSHOTS=1.",
            file: file,
            line: line
        )
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
