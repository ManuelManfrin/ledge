import AppKit
import Darwin
import Foundation

/// Stessa strada del Centro di Controllo: il comando arriva all'app
/// che è in riproduzione adesso, incluso un video nel browser.
private enum NowPlaying {
    enum Command: UInt32 {
        case toggle = 2
        case next = 4
        case previous = 5
    }

    private typealias SendReply = @convention(c) (
        UInt32,
        CFDictionary?,
        DispatchQueue?,
        (@convention(block) (CFArray?) -> Void)?
    ) -> UInt8
    private typealias Send = @convention(c) (Int, AnyObject?) -> Void

    private static var sendReply: SendReply?
    private static var sendPlain: Send?
    private static var loaded = false
    private static var unavailable = false

    static func send(_ command: Command, hidKey: Int32) {
        load()
        if let sendReply {
            let queued = sendReply(command.rawValue, nil, DispatchQueue.global(qos: .userInitiated), { _ in })
            if queued == 0 {
                fputs("MediaRemote non ha accodato il comando.\n", stderr)
            }
            Haptics.tick(notch: 0)
            return
        }
        if let sendPlain {
            sendPlain(Int(command.rawValue), nil)
            Haptics.tick(notch: 0)
            return
        }
        CornerActions.postMediaKey(hidKey)
        Haptics.tick(notch: 0)
    }

    private static func load() {
        guard !loaded else { return }
        loaded = true
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            unavailable = true
            fputs("MediaRemote assente: i media tornano ai tasti di sistema.\n", stderr)
            return
        }
        if let sym = dlsym(handle, "MRMediaRemoteSendCommandWithReply") {
            sendReply = unsafeBitCast(sym, to: SendReply.self)
        }
        if let sym = dlsym(handle, "MRMediaRemoteSendCommand") {
            sendPlain = unsafeBitCast(sym, to: Send.self)
        }
        if sendReply == nil && sendPlain == nil {
            unavailable = true
            fputs("MediaRemote senza comandi: i media tornano ai tasti di sistema.\n", stderr)
        }
    }
}

enum CornerActions {
    static func perform(_ action: CornerAction, appPath: String?) {
        switch action {
        case .none:
            return
        case .mute:
            toggleMute()
        case .lock:
            lockScreen()
        case .siri:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Siri.app"))
        case .missionControl:
            if !dockNotify("com.apple.expose.awake") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
            }
        case .showDesktop:
            if !dockNotify("com.apple.showdesktop.awake") {
                postKey(103, flags: [])
            }
        case .sleepDisplay:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["displaysleepnow"]
            try? process.run()
        case .openApp:
            guard let appPath, FileManager.default.fileExists(atPath: appPath) else {
                print("angolo: nessuna app scelta")
                return
            }
            NSWorkspace.shared.open(URL(fileURLWithPath: appPath))
        }
        Haptics.tick(notch: 0)
    }

    static func playPause() { NowPlaying.send(.toggle, hidKey: 16) }
    static func nextTrack() { NowPlaying.send(.next, hidKey: 17) }
    static func restartTrack() { NowPlaying.send(.previous, hidKey: 18) }

    fileprivate static func postMediaKey(_ key: Int32) {
        func event(_ down: Bool) -> CGEvent? {
            let flags: UInt = down ? 0xA00 : 0xB00
            return NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: flags),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: Int((key << 16) | Int32(flags)),
                data2: -1
            )?.cgEvent
        }
        event(true)?.post(tap: .cghidEventTap)
        event(false)?.post(tap: .cghidEventTap)
    }

    private static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func lockScreen() {
        let path = "/System/Library/PrivateFrameworks/login.framework/login"
        if let handle = dlopen(path, RTLD_LAZY),
           let sym = dlsym(handle, "SACLockScreenImmediate") {
            unsafeBitCast(sym, to: (@convention(c) () -> Void).self)()
            return
        }
        let session = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
        guard FileManager.default.isExecutableFile(atPath: session) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: session)
        process.arguments = ["-suspend"]
        try? process.run()
    }

    @discardableResult
    private static func dockNotify(_ name: String) -> Bool {
        let path = "/System/Library/PrivateFrameworks/Dock.framework/Dock"
        guard let handle = dlopen(path, RTLD_LAZY),
              let sym = dlsym(handle, "CoreDockSendNotification")
        else { return false }
        let fn = unsafeBitCast(sym, to: (@convention(c) (CFString) -> Void).self)
        fn(name as CFString)
        return true
    }
}
