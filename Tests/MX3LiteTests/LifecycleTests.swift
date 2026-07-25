import Foundation
import XCTest
@testable import MX3Lite

final class LifecycleTests: XCTestCase {
    private let identity = WorkerProcessIdentity(
        pid: 4321,
        executablePath: "/tmp/mx3-lite",
        startTimeSeconds: 100,
        startTimeMicroseconds: 200
    )

    func testParsesCurrentMetadata() throws {
        let data = try JSONEncoder().encode(identity)
        XCTAssertEqual(WorkerMetadataRecord.parse(data), .current(identity))
    }

    func testParsesLegacyPID() {
        XCTAssertEqual(WorkerMetadataRecord.parse(Data("4321\n".utf8)), .legacyPID(4321))
    }

    func testRejectsMalformedAndNonPositivePIDMetadata() {
        XCTAssertEqual(WorkerMetadataRecord.parse(Data("not-a-pid".utf8)), .invalid)
        XCTAssertEqual(WorkerMetadataRecord.parse(Data("0".utf8)), .invalid)
        XCTAssertEqual(WorkerMetadataRecord.parse(Data("-1".utf8)), .invalid)
    }

    func testIdentityAcceptsCopiedHelperButStillRequiresExactLiveProcessIdentity() {
        XCTAssertTrue(WorkerLifecycle.matchesWorkerIdentity(
            identity,
            expectedExecutablePath: identity.executablePath,
            inspectedIdentity: identity
        ))
        XCTAssertTrue(WorkerLifecycle.matchesWorkerIdentity(
            identity,
            expectedExecutablePath: "/different/mx3-lite",
            inspectedIdentity: identity
        ))
        XCTAssertFalse(WorkerLifecycle.matchesWorkerIdentity(
            identity,
            expectedExecutablePath: "/different/not-mx3-lite",
            inspectedIdentity: identity
        ))
        XCTAssertFalse(WorkerLifecycle.matchesWorkerIdentity(
            identity,
            expectedExecutablePath: identity.executablePath,
            inspectedIdentity: WorkerProcessIdentity(
                pid: identity.pid,
                executablePath: identity.executablePath,
                startTimeSeconds: identity.startTimeSeconds + 1,
                startTimeMicroseconds: identity.startTimeMicroseconds
            )
        ))
        XCTAssertFalse(WorkerLifecycle.matchesWorkerIdentity(
            identity,
            expectedExecutablePath: identity.executablePath,
            inspectedIdentity: nil
        ))
    }

    func testRecognizedWorkerPathRequiresTheExactHelperName() {
        XCTAssertTrue(WorkerLifecycle.isRecognizedWorkerPath(
            "/Applications/mx3-lite.app/Contents/Helpers/mx3-lite",
            expectedExecutablePath: "/Users/test/project/.build/release/mx3-lite"
        ))
        XCTAssertFalse(WorkerLifecycle.isRecognizedWorkerPath(
            "/Applications/other.app/Contents/Helpers/mx3-lite-copy",
            expectedExecutablePath: "/Users/test/project/.build/release/mx3-lite"
        ))
        XCTAssertFalse(WorkerLifecycle.isRecognizedWorkerPath(
            "",
            expectedExecutablePath: "/Users/test/project/.build/release/mx3-lite"
        ))
    }

    func testReadOnlyDiagnosisDistinguishesRunningStaleAndMalformedMetadata() {
        XCTAssertEqual(
            WorkerLifecycle.diagnose(
                .current(identity),
                expectedExecutablePath: identity.executablePath,
                inspectedIdentity: identity
            ),
            .running(identity, legacyMetadata: false)
        )

        XCTAssertEqual(
            WorkerLifecycle.diagnose(
                .legacyPID(identity.pid),
                expectedExecutablePath: identity.executablePath,
                inspectedIdentity: identity
            ),
            .running(identity, legacyMetadata: true)
        )

        guard case .stale = WorkerLifecycle.diagnose(
            .current(identity),
            expectedExecutablePath: identity.executablePath,
            inspectedIdentity: nil
        ) else {
            return XCTFail("missing live process should be diagnosed as stale")
        }

        XCTAssertEqual(
            WorkerLifecycle.diagnose(
                .invalid,
                expectedExecutablePath: identity.executablePath,
                inspectedIdentity: nil
            ),
            .malformedMetadata
        )
    }
}
