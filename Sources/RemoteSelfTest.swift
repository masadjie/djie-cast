import Foundation
import AppKit

/// `DJIE_REMOTE_SELFTEST=1` runs host + viewer in this process over 127.0.0.1 with a
/// synthetic screen (no permissions, no input injection), prints results and quits.
@MainActor
enum RemoteSelfTest {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["DJIE_REMOTE_SELFTEST"] != nil else { return }
        Task { await run(); exit(0) }
    }

    private static func sleep(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

    static func run() async {
        let host = RemoteHostModel.shared, viewer = RemoteViewerModel.shared
        host.useSyntheticSource = true
        host.code = "482913"
        host.start(port: 47899)
        await sleep(1)
        print("HOST status:", host.status)

        // 1) Correct code
        let screen = RemoteScreenView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        viewer.headless = true
        viewer.testScreen = screen
        var config = (0, 0), frames = 0, keys = 0
        viewer.onVideoConfig = { config = ($0, $1) }
        viewer.onFrameDecoded = { frames += 1; if $0 { keys += 1 } }
        viewer.connect(address: "127.0.0.1:47899", code: "482 913")
        await sleep(4)
        print("RIGHT CODE → viewer:", viewer.status, "| host:", host.status)
        print("  video config:", config, "frames:", frames, "keyframes:", keys,
              "renderer:", screen.renderer.status == .failed ? "FAILED \(String(describing: screen.renderer.error))" : "ok",
              "| stats:", viewer.stats)
        viewer.disconnect()
        await sleep(1.5)
        print("AFTER DISCONNECT → host:", host.status)

        // 2) Wrong code must be rejected
        frames = 0
        viewer.connect(address: "127.0.0.1:47899", code: "000000")
        await sleep(4)
        print("WRONG CODE → viewer:", viewer.status, "| frames:", frames, "| host:", host.status)
        viewer.disconnect()

        // 3) Nobody listening
        viewer.connect(address: "127.0.0.1:47898", code: "482913")
        await sleep(3)
        print("NO HOST → viewer:", viewer.status)
        host.stop()
    }
}
