import SwiftUI
import UIKit

/// TEMPORARY freeze probe (never merged): `-RWStress YES` swipes through the
/// clubs and turns the phone on its side and back, while a watchdog thread
/// writes to Documents/stress.log whenever the main thread stops answering.
final class StressBeat: @unchecked Sendable {
    static let shared = StressBeat()
    var date = Date()
}

enum StressProbe {
    /// `-RWProbe N` switches one suspect off (0 = none).
    static let variant = UserDefaults.standard.integer(forKey: "RWProbe")
    static var logURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("stress.log") }

    static func log(_ line: String) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("stress.log")
        let text = "\(Date().timeIntervalSince1970) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(Data(text.utf8)); try? handle.close()
        } else {
            try? Data(text.utf8).write(to: url)
        }
        NSLog("RWSTRESS %@", line)
    }

    @MainActor static func startWatchdog() {
        try? FileManager.default.removeItem(at: logURL)
        log("start")
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in StressBeat.shared.date = Date() }
        Thread.detachNewThread {
            var stalled = false
            while true {
                Thread.sleep(forTimeInterval: 0.5)
                let gap = Date().timeIntervalSince(StressBeat.shared.date)
                if gap > 2 && !stalled { stalled = true; log("STALL main thread silent \(gap)s") }
                if gap > 10 { log("STALL still \(gap)s") ; Thread.sleep(forTimeInterval: 5) }
                if gap < 1 && stalled { stalled = false; log("recovered") }
            }
        }
    }

    @MainActor static func run(ids: [String], select: @escaping (String) -> Void) async {
        guard ids.count > 1 else { log("too few clubs \(ids.count)"); return }
        startWatchdog()
        try? await Task.sleep(for: .seconds(4))
        for step in 0..<30 {
            let id = ids[(step + 1) % ids.count]
            log("step \(step) select \(id)")
            withAnimation { select(id) }
            try? await Task.sleep(for: .milliseconds(1200))
            if step % 5 == 4 {
                let side = (step / 5) % 2 == 0
                log("turn \(side ? "landscape" : "portrait")")
                for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: side ? .landscapeRight : .portrait))
                }
                try? await Task.sleep(for: .milliseconds(2500))
            }
        }
        log("done")
    }
}
