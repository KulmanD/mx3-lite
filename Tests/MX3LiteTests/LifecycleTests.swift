import Foundation
import Testing
@testable import MX3Lite

@Suite struct LifecycleTests {
    private let identity = WorkerProcessIdentity(
        pid: 4321,
        executablePath: "/tmp/mx3-lite",
        startTimeSeconds: 100,
        startTimeMicroseconds: 200
    )

    @Test func parsesCurrentMetadata() throws {
        let data = try JSONEncoder().encode(identity)
        #expect(WorkerMetadataRecord.parse(data) == .current(identity))
    }

    @Test func parsesLegacyPID() {
        #expect(WorkerMetadataRecord.parse(Data("4321\n".utf8)) == .legacyPID(4321))
    }

    @Test func rejectsMalformedAndNonPositivePIDMetadata() {
        #expect(WorkerMetadataRecord.parse(Data("not-a-pid".utf8)) == .invalid)
        #expect(WorkerMetadataRecord.parse(Data("0".utf8)) == .invalid)
        #expect(WorkerMetadataRecord.parse(Data("-1".utf8)) == .invalid)
    }

    @Test func identityMustMatchPathPIDAndStartTimeExactly() {
        #expect(WorkerLifecycle.matchesWorkerIdentity(
            identity,
            expectedExecutablePath: identity.executablePath,
            inspectedIdentity: identity
        ))
        #expect(!WorkerLifecycle.matchesWorkerIdentity(
            identity,
            expectedExecutablePath: "/different/mx3-lite",
            inspectedIdentity: identity
        ))
        #expect(!WorkerLifecycle.matchesWorkerIdentity(
            identity,
            expectedExecutablePath: identity.executablePath,
            inspectedIdentity: WorkerProcessIdentity(
                pid: identity.pid,
                executablePath: identity.executablePath,
                startTimeSeconds: identity.startTimeSeconds + 1,
                startTimeMicroseconds: identity.startTimeMicroseconds
            )
        ))
        #expect(!WorkerLifecycle.matchesWorkerIdentity(
            identity,
            expectedExecutablePath: identity.executablePath,
            inspectedIdentity: nil
        ))
    }
}
