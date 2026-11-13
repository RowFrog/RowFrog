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
    private static let lastPhaseAtKey = "RWDiagnosisLastPhaseAt"
    private let queue = DispatchQueue(label: "com.rowfrog.diagnosis", qos: .utility)
    private var observers: [NSObjectProtocol] = []
    /// When the app last left the screen, for "away" on the way back.
    private var leftAt: Date?

    /// At launch: notes how the last run ended, follows the app's comings and
    /// goings as UIKit sees them, and asks iOS for its reports.
    static func start() {
        let version = BuildInfo.summary
        let last = UserDefaults.standard.string(forKey: lastPhaseKey) ?? "none"
        let solid = UserDefaults.standard.bool(forKey: PowerState.forcedKey) ? "; drawn as in Low Power Mode" : ""
        let ago = (UserDefaults.standard.object(forKey: lastPhaseAtKey) as? Date).map { " (\(duration(since: $0)) ago)" } ?? ""
        note("launch \(version), iOS \(UIDevice.current.systemVersion), \(model)\(solid); \(startedBy); last run's last step: \(last)\(ago)")
        let center = NotificationCenter.default
        let steps: [(Notification.Name, String)] = [
            (UIApplication.willEnterForegroundNotification, "UIKit will enter foreground"),
            (UIApplication.didBecomeActiveNotification, "UIKit did become active"),
            (UIApplication.willResignActiveNotification, "UIKit will resign active"),
            (UIApplication.didEnterBackgroundNotification, "UIKit did enter background"),
            (UIApplication.didReceiveMemoryWarningNotification, "UIKit memory warning"),
        ]
        shared.observers = steps.map { name, text in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { shared.handle(name, text) }
            }
        }
        MXMetricManager.shared.add(shared)
    }

    /// One line with the time and the app's memory.
    static func note(_ text: String) { shared.write(text) }

    /// A step in and out of the app, also kept as the last one, so the next
    /// launch tells whether the run ended in the background (normal) or not.
    static func step(_ text: String) {
        UserDefaults.standard.set("\(text) at \(Date.now.formatted(.iso8601))", forKey: lastPhaseKey)
        UserDefaults.standard.set(Date.now, forKey: lastPhaseAtKey)
        note(text)
    }

    /// UIKit's steps, plus how long the app was away on the way back and what
    /// was on screen on the way out (for the watchdog kills on return).
    @MainActor private func handle(_ name: Notification.Name, _ text: String) {
        switch name {
        case UIApplication.willEnterForegroundNotification:
            Self.step(text + (leftAt.map { " after \(Self.duration(since: $0)) away" } ?? ""))
        case UIApplication.didEnterBackgroundNotification:
            leftAt = .now
            Self.step(text)
            Self.note("on leaving: " + Self.screenContext())
        default:
            Self.step(text)
        }
    }

    // MARK: Context for the watchdog kills

    /// Who started this run. Xcode's Run attaches its debugger and loads its
    /// checkers (Main Thread Checker, view debugger); a Home-screen start has neither.
    private static var startedBy: String {
        let checkers = ProcessInfo.processInfo.environment["DYLD_INSERT_LIBRARIES"] != nil
        if debuggerAttached { return "started from Xcode (debugger attached)" }
        return checkers ? "Xcode checkers loaded, no debugger" : "started on the device"
    }

    private static var debuggerAttached: Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    /// The device model, e.g. iPad14,4.
    private static var model: String {
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else { return "?" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &bytes, &size, nil, 0) == 0 else { return "?" }
        return bytes.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    /// Window size and orientation, light or dark, Low Power Mode, heat,
    /// debugger, and how many live blur and glass layers were on screen
    /// (iOS redraws those outside the app when it comes back).
    @MainActor private static func screenContext() -> String {
        var parts: [String] = []
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            let geometry = scene.effectiveGeometry
            let size = scene.windows.first?.bounds.size ?? .zero
            let style = scene.traitCollection.userInterfaceStyle == .dark ? "dark" : "light"
            parts.append("window \(Int(size.width))x\(Int(size.height)) \(orientationName(geometry.interfaceOrientation)) \(style)")
            var counts = LayerCounts()
            for window in scene.windows where !window.isHidden { counts.walk(window.layer) }
            parts.append("\(counts.all) layers, \(counts.backdrop) blur, \(counts.glass) glass\(counts.capped ? " (count stopped)" : "")")
            parts.append("layer kinds: " + counts.kinds)
        }
        parts.append("Low Power Mode \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "on" : "off")")
        parts.append("drawn solid \(PowerState.shared.lowPower ? "yes" : "no")")
        parts.append("heat \(thermalName(ProcessInfo.processInfo.thermalState))")
        parts.append("debugger \(debuggerAttached ? "attached" : "none")")
        return parts.joined(separator: ", ")
    }

    private static func orientationName(_ orientation: UIInterfaceOrientation) -> String {
        switch orientation {
        case .portrait, .portraitUpsideDown: "portrait"
        case .landscapeLeft, .landscapeRight: "landscape"
        default: "orientation unknown"
        }
    }

    private static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "normal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    private static func duration(since date: Date) -> String {
        let minutes = max(0, Int(Date.now.timeIntervalSince(date) / 60))
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
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

/// Counts the layers under a window: live blurs (backdrop layers) and Liquid
/// Glass pieces, by their class names. Stops after 20 000 layers so leaving the app
/// stays quick.
private struct LayerCounts {
    var all = 0
    var backdrop = 0
    var glass = 0
    var capped = false
    /// How many layers of each class other than plain CALayer, to find the
    /// class names Liquid Glass uses.
    var byClass: [String: Int] = [:]

    /// The 12 most common special layer classes, e.g. "CABackdropLayer 7".
    var kinds: String {
        byClass.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(12).map { "\($0.key) \($0.value)" }.joined(separator: ", ")
    }

    mutating func walk(_ layer: CALayer) {
        guard all < 20_000 else { capped = true; return }
        all += 1
        let name = String(describing: type(of: layer))
        if name != "CALayer" { byClass[name, default: 0] += 1 }
        if name.contains("Backdrop") { backdrop += 1 }
        // Liquid Glass draws each piece through one SDF portal layer (checked
        // 13 Nov: the SDF layers vanish when drawn as in Low Power Mode).
        if name == "SDFPortalLayer" { glass += 1 }
        for sublayer in layer.sublayers ?? [] { walk(sublayer) }
    }
}
