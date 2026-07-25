import Foundation
import XCTest
@testable import MX3Lite

final class DoctorTests: XCTestCase {
    func testReportExitCodeAndConciseRendering() {
        let report = DoctorReport(checks: [
            DoctorCheck(name: "binary", severity: .ok, summary: "ready", details: ["hidden detail"]),
            DoctorCheck(name: "device", severity: .warning, summary: "not connected", details: ["connect mouse"]),
            DoctorCheck(name: "permission", severity: .blocker, summary: "not granted", details: ["grant access"])
        ])

        XCTAssertEqual(report.warningCount, 1)
        XCTAssertEqual(report.blockerCount, 1)
        XCTAssertEqual(report.exitCode, 1)

        let concise = report.rendered(verbose: false)
        XCTAssertFalse(concise.contains("hidden detail"))
        XCTAssertTrue(concise.contains("connect mouse"))
        XCTAssertTrue(concise.contains("grant access"))
        XCTAssertTrue(concise.contains("result: blocked"))
        XCTAssertTrue(report.rendered(verbose: true).contains("hidden detail"))
    }

    func testWarningsDoNotMakeDoctorFail() {
        let report = DoctorReport(checks: [
            DoctorCheck(name: "device", severity: .warning, summary: "not connected")
        ])

        XCTAssertEqual(report.exitCode, 0)
        XCTAssertTrue(report.rendered(verbose: false).contains("ready with warnings"))
    }

    func testWrapperTargetParsingAndValidation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("mx3-lite")
        try Data().write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let wrapper = directory.appendingPathComponent("mxmaster")
        let contents = """
        #!/usr/bin/env bash
        MX3_LITE="\(executable.path)"
        exec "$MX3_LITE" "$@"
        """
        try Data(contents.utf8).write(to: wrapper)

        XCTAssertEqual(WrapperInspector.targetPath(in: contents), executable.path)
        XCTAssertEqual(
            WrapperInspector.inspect(wrapperURL: wrapper, expectedExecutableURL: executable),
            .valid(target: executable.path)
        )
    }

    func testWrapperMismatchIsReportedWithoutExecutingIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let actual = directory.appendingPathComponent("actual")
        let expected = directory.appendingPathComponent("expected")
        for file in [actual, expected] {
            try Data().write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        let wrapper = directory.appendingPathComponent("mxmaster")
        try Data("MX3_LITE=\"\(actual.path)\"\n".utf8).write(to: wrapper)

        XCTAssertEqual(
            WrapperInspector.inspect(wrapperURL: wrapper, expectedExecutableURL: expected),
            .targetMismatch(actual: actual.path, expected: expected.path)
        )
    }
}
