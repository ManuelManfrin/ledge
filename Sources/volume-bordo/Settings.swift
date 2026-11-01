import Foundation
import ServiceManagement
import SwiftUI

final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var ready = false
    @Published var note = ""
}

final class BordiSettings: ObservableObject {
    static let shared = BordiSettings()

    private let defaults = UserDefaults.standard

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: Key.enabled) } }
    @Published var requireCommand: Bool { didSet { defaults.set(requireCommand, forKey: Key.command) } }
    @Published var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Key.haptics) } }
    @Published var edgeWidth: Double { didSet { storeEdge() } }
    @Published var twoFingerEdge: Double { didSet { storeReach() } }
    @Published var bottomEdge: Double { didSet { storeBottomEdge() } }
    @Published var bottomReach: Double { didSet { storeBottomReach() } }
    @Published var cornerPriority: CornerBarPriority { didSet { defaults.set(cornerPriority.rawValue, forKey: Key.priority) } }
    @Published var sensitivity: Double { didSet { defaults.set(sensitivity, forKey: Key.sensitivity) } }
    @Published var launchAtLogin: Bool
    @Published var loginError: String?
    @Published var cornerActions: [String: String] { didSet { defaults.set(cornerActions, forKey: Key.corners) } }
    @Published var cornerApps: [String: String] { didSet { defaults.set(cornerApps, forKey: Key.apps) } }

    private init() {
        enabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        requireCommand = defaults.object(forKey: Key.command) as? Bool ?? false
        hapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? false
        edgeWidth = defaults.object(forKey: Key.edge) as? Double ?? 0.08
        twoFingerEdge = defaults.object(forKey: Key.reach) as? Double ?? 0.30
        bottomEdge = defaults.object(forKey: Key.bottomEdge) as? Double ?? 0.08
        bottomReach = defaults.object(forKey: Key.bottomReach) as? Double ?? 0.30
        cornerPriority = CornerBarPriority(rawValue: defaults.string(forKey: Key.priority) ?? "") ?? .bottom
        sensitivity = defaults.object(forKey: Key.sensitivity) as? Double ?? 1.8
        launchAtLogin = SMAppService.mainApp.status == .enabled
        let stored = defaults.dictionary(forKey: Key.corners) as? [String: String]
        cornerActions = stored ?? [TrackCorner.topRight.rawValue: CornerAction.mute.rawValue]
        cornerApps = defaults.dictionary(forKey: Key.apps) as? [String: String] ?? [:]
    }

    func action(for corner: TrackCorner) -> CornerAction {
        CornerAction(rawValue: cornerActions[corner.rawValue] ?? "") ?? .none
    }

    func setAction(_ action: CornerAction, for corner: TrackCorner) {
        cornerActions[corner.rawValue] = action.rawValue
    }

    func appPath(for corner: TrackCorner) -> String? {
        cornerApps[corner.rawValue]
    }

    func setAppPath(_ path: String, for corner: TrackCorner) {
        cornerApps[corner.rawValue] = path
    }

    func binding(for corner: TrackCorner) -> Binding<CornerAction> {
        Binding(
            get: { self.action(for: corner) },
            set: { self.setAction($0, for: corner) }
        )
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "L'avvio al login vale per Bordi.app, non per il binario da terminale."
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func storeEdge() {
        let clamped = min(0.16, max(0.04, edgeWidth))
        if clamped != edgeWidth {
            edgeWidth = clamped
            return
        }
        defaults.set(clamped, forKey: Key.edge)
        if twoFingerEdge < clamped + 0.04 {
            twoFingerEdge = clamped + 0.04
        }
    }

    private func storeReach() {
        let floor = edgeWidth + 0.04
        let clamped = min(0.45, max(floor, twoFingerEdge))
        if clamped != twoFingerEdge {
            twoFingerEdge = clamped
            return
        }
        defaults.set(clamped, forKey: Key.reach)
    }

    private func storeBottomEdge() {
        let clamped = min(0.16, max(0.04, bottomEdge))
        if clamped != bottomEdge {
            bottomEdge = clamped
            return
        }
        defaults.set(clamped, forKey: Key.bottomEdge)
        if bottomReach < clamped + 0.04 {
            bottomReach = clamped + 0.04
        }
    }

    private func storeBottomReach() {
        let floor = bottomEdge + 0.04
        let clamped = min(0.45, max(floor, bottomReach))
        if clamped != bottomReach {
            bottomReach = clamped
            return
        }
        defaults.set(clamped, forKey: Key.bottomReach)
    }

    private enum Key {
        static let enabled = "enabled"
        static let command = "requireCommand"
        static let haptics = "hapticsEnabled"
        static let edge = "edgeWidth"
        static let reach = "twoFingerEdge"
        static let bottomEdge = "bottomEdge"
        static let bottomReach = "bottomReach"
        static let priority = "cornerPriority"
        static let sensitivity = "sensitivity"
        static let corners = "cornerActions"
        static let apps = "cornerApps"
    }
}

enum CornerBarPriority: String, CaseIterable, Identifiable {
    case sides
    case bottom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sides: return "Laterali"
        case .bottom: return "In basso"
        }
    }
}

enum TrackCorner: String, CaseIterable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft: return "Alto sinistra"
        case .topRight: return "Alto destra"
        case .bottomLeft: return "Basso sinistra"
        case .bottomRight: return "Basso destra"
        }
    }
}

enum CornerAction: String, CaseIterable, Identifiable {
    case none
    case mute
    case lock
    case siri
    case missionControl
    case showDesktop
    case sleepDisplay
    case openApp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Nessuna"
        case .mute: return "Mute / unmute"
        case .lock: return "Blocca il Mac"
        case .siri: return "Siri"
        case .missionControl: return "Mission Control"
        case .showDesktop: return "Mostra la scrivania"
        case .sleepDisplay: return "Spegni lo schermo"
        case .openApp: return "Apri un'app"
        }
    }
}
