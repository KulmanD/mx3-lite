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

    func testIdentityMustMatchPathPIDAndStartTimeExactly() {
        XCTAssertTrue(WorkerLifecycle.matchesWorkerIdentity(
            identity,
            expectedExecutablePath: identity.executablePath,
            inspectedIdentity: identity
        ))
        XCTAssertFalse(WorkerLifecycle.matchesWorkerIdentity(
            identity,
            expectedExecutablePath: "/different/mx3-lite",
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
}
