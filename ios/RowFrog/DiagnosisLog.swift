import Foundation
import SwiftUI
import MetricKit
import UIKit

/// A short log of what the app did just before leaving and after coming back,
/// for the rare watchdog kills on return to the app (iPhone reports
/// "scene-update watchdog" with nothing of ours running). Shared from
/// Settings > Developer. iOS's own hang, crash and exit reports (MetricKit)
/// land in it on a later start. Stays on the phone; only the user shares it.
final class DiagnosisLog: NSObject, MXMetricManagerSubscriber {
    static let shared = DiagnosisLog()
    static let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "diagnosis.log")
    /// Older lines go once the file passes this; a few days of normal use.
    private static let maxBytes = 256 * 1024
    private static let lastPhaseKey = "RWDiagnosisLastPhase"
    private let queue = DispatchQueue(label: "com.rowfrog.diagnosis", qos: .utility)
    private var observers: [NSObjectProtocol] = []

    /// At launch: notes how the last run ended, follows the app's comings and
    /// goings as UIKit sees them, and asks iOS for its reports.
    static func start() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let last = UserDefaults.standard.string(forKey: lastPhaseKey) ?? "none"
        note("launch \(version), iOS \(UIDevice.current.systemVersion); last run's last step: \(last)")
        let center = NotificationCenter.default
        let steps: [(Notification.Name, String)] = [
            (UIApplication.willEnterForegroundNotification, "UIKit will enter foreground"),
            (UIApplication.didBecomeActiveNotification, "UIKit did become active"),
            (UIApplication.willResignActiveNotification, "UIKit will resign active"),
            (UIApplication.didEnterBackgroundNotification, "UIKit did enter background"),
            (UIApplication.didReceiveMemoryWarningNotification, "UIKit memory warning"),
        ]
        shared.observers = steps.map { name, text in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in step(text) }
        }
        MXMetricManager.shared.add(shared)
    }

    /// One line with the time and the app's memory.
    static func note(_ text: String) { shared.write(text) }

    /// A step in and out of the app, also kept as the last one, so the next
    /// launch tells whether the run ended in the background (normal) or not.
    static func step(_ text: String) {
        UserDefaults.standard.set("\(text) at \(Date.now.formatted(.iso8601))", forKey: lastPhaseKey)
        note(text)
    }

    static var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    private func write(_ text: String) {
        let line = "\(Date.now.formatted(.iso8601)) \(Self.memoryMB()) MB \(text)\n"
        queue.async {
            let url = Self.url
            let data = Data(line.utf8)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: url)
            }
            Self.trim(url)
        }
    }

    /// Keeps the newer half once the file grows past the limit.
    private static func trim(_ url: URL) {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxBytes,
              let data = try? Data(contentsOf: url) else { return }
        var kept = data.suffix(maxBytes / 2)
        if let newline = kept.firstIndex(of: UInt8(ascii: "\n")) { kept = kept[kept.index(after: newline)...] }
        try? Data(kept).write(to: url)
    }

    private static func memoryMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }

    // MARK: MetricKit, delivered by iOS on a later start, at most daily for metrics.

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            write("iOS diagnostics: " + (String(data: payload.jsonRepresentation(), encoding: .utf8) ?? "?"))
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            guard let exits = payload.applicationExitMetrics else { continue }
            write("iOS exit counts: " + (String(data: exits.jsonRepresentation(), encoding: .utf8) ?? "?"))
        }
    }
}

extension View {
    /// Notes in the diagnosis log when this screen opens and closes.
    func diagnosisNamed(_ name: String) -> some View {
        onAppear { DiagnosisLog.note("\(name) opened") }
            .onDisappear { DiagnosisLog.note("\(name) closed") }
    }
}

/// The root view's steps for the diagnosis log: in and out of the app with the
/// club shown, page switches, the club list and the settings. A modifier of its
/// own, so the root view's long body still type-checks in time.
struct DiagnosisSteps: ViewModifier {
    let page: String
    let list: Bool
    let settings: Bool
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in DiagnosisLog.step("SwiftUI \(phase) on \(page)") }
            .onChange(of: page) { _, page in DiagnosisLog.note("page \(page)") }
            .onChange(of: list) { _, open in DiagnosisLog.note(open ? "club list opened" : "club list closed") }
            .onChange(of: settings) { _, open in DiagnosisLog.note(open ? "settings opened" : "settings closed") }
    }
}
