import AppKit
import Testing
@testable import SopranoDesktop

struct LiveProcessRunnerTests {
    @Test func aCommandWritingMoreThanAPipeBufferStillFinishesWithAllItsOutput() async {
        let result = await LiveProcessRunner().run(URL(fileURLWithPath: "/bin/sh"), ["-c", "head -c 300000 /dev/zero | tr '\\0' x"])
        #expect(result.succeeded)
        #expect(result.output.count == 300_000)
    }

    @Test func aMissingExecutableIsAFailedResultNotACrash() async {
        let result = await LiveProcessRunner().run(URL(fileURLWithPath: "/nonexistent/tool"), [])
        #expect(!result.succeeded)
    }
}
