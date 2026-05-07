import XCTest
import SwiftUI
import UniformTypeIdentifiers
import ImageIO

/// Apple Watch screenshot pixel sizes (App Store Connect spec).
/// Verify current requirement at https://developer.apple.com/help/app-store-connect/
/// reference/screenshot-specifications/ before bootstrapping goldens.
enum WatchDevice {
    /// Apple Watch Ultra (49mm): 410 × 502 pixels.
    static let ultra49mm = CGSize(width: 410, height: 502)
}

enum SnapshotRunner {

    /// Render `view` to a PNG, attach to the test result, and diff against a committed
    /// golden image at `Snapshots/AppStore/<name>.png`.
    ///
    /// - Golden missing → write golden + XCTFail with "recorded new snapshot, re-run to verify".
    /// - `RECORD_SNAPSHOTS=1` env var set → overwrite golden, pass.
    /// - Bytes equal → pass.
    /// - Bytes differ → write `<output_dir>/<name>-failed.png`, XCTFail with diff message.
    @MainActor
    static func verify<V: View>(
        _ view: V,
        named name: String,
        size: CGSize = WatchDevice.ultra49mm,
        in testCase: XCTestCase,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        // 1. Render at scale=1 so PNG pixel dimensions equal `size`.
        let sized = view.frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: sized)
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        renderer.scale = 1

        guard let cgImage = renderer.cgImage else {
            XCTFail("ImageRenderer produced no cgImage for \(name)", file: file, line: line)
            return
        }

        guard let pngData = pngData(from: cgImage) else {
            XCTFail("Could not encode cgImage to PNG for \(name)", file: file, line: line)
            return
        }

        // 2. Always attach to the test result.
        let attachment = XCTAttachment(data: pngData, uniformTypeIdentifier: UTType.png.identifier)
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        testCase.add(attachment)

        // 3. Resolve paths.
        let goldenURL = goldenURL(for: name, file: file)
        let outputDir = outputDirectory(file: file)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let recording = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"

        // 4. Compare or record.
        if recording {
            try? FileManager.default.createDirectory(at: goldenURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            do {
                try pngData.write(to: goldenURL)
                NSLog("[SnapshotRunner] Recorded golden: \(goldenURL.path)")
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
            return  // pass
        }

        let failedURL = outputDir.appendingPathComponent("\(name)-failed.png")
        try? pngData.write(to: failedURL)
        XCTFail(
            "Snapshot \(name) differs from golden. Failed render: \(failedURL.path). " +
            "If this change is intentional, re-record with RECORD_SNAPSHOTS=1.",
            file: file,
            line: line
        )
    }

    // MARK: - PNG encoding

    private static func pngData(from cgImage: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(mutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return mutableData as Data
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
    /// `SFTransitWatch.xcodeproj`. Used as the last-resort base for golden + output paths
    /// when neither `SRCROOT` nor `CI_PRIMARY_REPOSITORY_PATH` is set.
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
        // Fall back to the original file's directory.
        return URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
    }
}
