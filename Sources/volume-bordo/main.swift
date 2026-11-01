// Bordi. Uso personale. Il comportamento attuale è in HANDOFF.md.
//
//   cd /Users/manuel/Progetti/trackpad-bordi
//   ./build-app.sh && open Bordi.app

import AppKit
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import IOKit

// Valori letti dalle impostazioni, così la barra dei menu li cambia subito.
var edgeWidth: Float { Float(BordiSettings.shared.edgeWidth) }
var twoFingerEdge: Float { Float(BordiSettings.shared.twoFingerEdge) }
var bottomEdge: Float { Float(BordiSettings.shared.bottomEdge) }
var bottomReach: Float { Float(BordiSettings.shared.bottomReach) }
var requireCommand: Bool { BordiSettings.shared.requireCommand }
var hapticsEnabled: Bool { BordiSettings.shared.hapticsEnabled }
var sensitivity: Float { Float(BordiSettings.shared.sensitivity) }
let armDistance: Float = 0.025
let mediaSwipeDistance: Float = 0.08
let tapTravel: Float = 0.02
let cornerSize: Float = 0.16
let fineScale: Float = 0.1
let tapMaxDuration = 0.25
let doubleTapGap = 0.40
let notches = 16

// MARK: - Tasti

func modifierFlags() -> CGEventFlags {
    CGEventSource.flagsState(.hidSystemState)
}

func commandDown() -> Bool { modifierFlags().contains(.maskCommand) }
func optionDown() -> Bool { modifierFlags().contains(.maskAlternate) }

// MARK: - Contatto

struct MTPoint {
    var x: Float
    var y: Float
}

struct MTVector {
    var position: MTPoint
    var velocity: MTPoint
}

struct MTData {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32
    var unknown1: Int32
    var unknown2: Int32
    var normalized: MTVector
    var size: Float
    var unknown3: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absolute: MTVector
    var unknown5: Int32
    var unknown6: Int32
    var unknown7: Float
}

enum TouchPhase {
    case began, moved, ended, other
}

func phase(of state: Int32) -> TouchPhase {
    switch state {
    case 1, 3: return .began
    case 4, 6: return .moved
    case 5, 7: return .ended
    default: return .other
    }
}

struct Finger {
    var id: Int32
    var x: Float
    var y: Float
    var size: Float
    var major: Float
    var minor: Float
    var phase: TouchPhase
}

func isPalm(_ finger: Finger) -> Bool {
    let short = max(0.001, min(finger.major, finger.minor))
    let long = max(finger.major, finger.minor)
    return finger.size > 1.2 || long / short > 2.4
}

// MARK: - Volume

func defaultOutputDevice() -> AudioObjectID? {
    var id = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &addr, 0, nil, &size, &id
    )
    return status == noErr && id != 0 ? id : nil
}

func volumeAddress(_ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: element
    )
}

func muteAddress(_ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: element
    )
}

func readVolume() -> Float {
    guard let device = defaultOutputDevice() else { return 0 }
    var best: Float = 0
    for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1, 2] {
        var addr = volumeAddress(element)
        guard AudioObjectHasProperty(device, &addr) else { continue }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr {
            best = max(best, value)
        }
    }
    return min(1, max(0, best))
}

func writeVolume(_ value: Float) {
    if outputMuted() { setMuted(false) }
    guard let device = defaultOutputDevice() else { return }
    var vol = Float32(min(1, max(0, value)))
    let size = UInt32(MemoryLayout<Float32>.size)
    var master = volumeAddress(kAudioObjectPropertyElementMain)
    if AudioObjectHasProperty(device, &master),
       AudioObjectSetPropertyData(device, &master, 0, nil, size, &vol) == noErr {
        return
    }
    for channel: AudioObjectPropertyElement in [1, 2] {
        var addr = volumeAddress(channel)
        if AudioObjectHasProperty(device, &addr) {
            AudioObjectSetPropertyData(device, &addr, 0, nil, size, &vol)
        }
    }
}

func outputMuted() -> Bool {
    guard let device = defaultOutputDevice() else { return false }
    for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1, 2] {
        var addr = muteAddress(element)
        guard AudioObjectHasProperty(device, &addr) else { continue }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &muted) == noErr {
            return muted != 0
        }
    }
    return false
}

func setMuted(_ muted: Bool) {
    guard let device = defaultOutputDevice() else { return }
    var value: UInt32 = muted ? 1 : 0
    let size = UInt32(MemoryLayout<UInt32>.size)
    for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1, 2] {
        var addr = muteAddress(element)
        if AudioObjectHasProperty(device, &addr) {
            AudioObjectSetPropertyData(device, &addr, 0, nil, size, &value)
        }
    }
}

func toggleMute() {
    let mute = !outputMuted()
    setMuted(mute)
    if mute {
        SystemHUD.muted()
        print("audio disattivato")
    } else {
        let volume = readVolume()
        SystemHUD.volume(volume)
        print(String(format: "audio attivo  %3.0f%%", volume * 100))
    }
}

// MARK: - Luminosità (DisplayServices, privato)

enum Brightness {
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private static var setFn: SetFn?
    private static var getFn: GetFn?
    private static var loaded = false

    static func prepare() {
        guard !loaded else { return }
        loaded = true
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            fputs("DisplayServices assente: niente luminosità.\n", stderr)
            return
        }
        if let sym = dlsym(handle, "DisplayServicesSetBrightness") {
            setFn = unsafeBitCast(sym, to: SetFn.self)
        }
        if let sym = dlsym(handle, "DisplayServicesGetBrightness") {
            getFn = unsafeBitCast(sym, to: GetFn.self)
        }
        if let value = read() {
            print(String(format: "luminosità attuale %3.0f%%", value * 100))
        } else {
            fputs("luminosità illeggibile su questo display.\n", stderr)
        }
    }

    static func read() -> Float? {
        guard let getFn, let display = builtinDisplay() else { return nil }
        var value: Float = 0
        guard getFn(display, &value) == 0 else { return nil }
        return min(1, max(0, value))
    }

    static func write(_ value: Float) {
        guard let setFn, let display = builtinDisplay() else { return }
        _ = setFn(display, min(1, max(0, value)))
    }

    private static func builtinDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        guard count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return ids.first { CGDisplayIsBuiltin($0) != 0 } ?? ids.first
    }
}

// MARK: - Barra di sistema

enum SystemHUD {
    private static var show: (@convention(c) (AnyObject, Selector, Int64, UInt32, UInt32, UInt32, UInt32, UInt32, Bool) -> Void)?
    private static var manager: AnyObject?
    private static var selector: Selector?
    private static var ready = false
    private static var tried = false

    static func volume(_ value: Float) { post(graphic: 3, value: value) }
    static func brightness(_ value: Float) { post(graphic: 1, value: value) }
    static func muted() { post(graphic: 4, value: 0) }

    private static func post(graphic: Int64, value: Float) {
        guard load(), let show, let manager, let selector else { return }
        let filled = UInt32((Double(min(1, max(0, value))) * Double(notches)).rounded())
        show(manager, selector, graphic, UInt32(CGMainDisplayID()), 0x1F4, 1000, filled, UInt32(notches), false)
    }

    private static func load() -> Bool {
        if tried { return ready }
        tried = true
        guard let bundle = Bundle(path: "/System/Library/PrivateFrameworks/OSD.framework"),
              bundle.load(),
              let cls = NSClassFromString("OSDManager"),
              let sharedMethod = class_getClassMethod(cls, NSSelectorFromString("sharedManager"))
        else {
            fputs("OSD.framework assente: i livelli cambiano, senza la barra.\n", stderr)
            return false
        }
        typealias Shared = @convention(c) (AnyClass, Selector) -> AnyObject
        let shared = unsafeBitCast(method_getImplementation(sharedMethod), to: Shared.self)
        let sel = NSSelectorFromString(
            "showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:"
        )
        guard let method = class_getInstanceMethod(cls, sel) else { return false }
        show = unsafeBitCast(
            method_getImplementation(method),
            to: (@convention(c) (AnyObject, Selector, Int64, UInt32, UInt32, UInt32, UInt32, UInt32, Bool) -> Void).self
        )
        manager = shared(cls, NSSelectorFromString("sharedManager"))
        selector = sel
        ready = true
        return true
    }
}

// MARK: - Aptica
//
// L'attuatore del Force Touch accetta pochi waveform fissi, dal tocco
// leggero al colpo pieno. Le 17 tacche (0…16) ci si appoggiano in ordine:
// in basso il tick è il più lieve, in alto il più forte.
// L'handle vale un colpo solo: si ricrea a ogni tacca.

enum Haptics {
    private typealias Create = @convention(c) (UInt64) -> Unmanaged<AnyObject>?
    private typealias Open = @convention(c) (UnsafeMutableRawPointer, UInt32) -> Int32
    private typealias Close = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias Actuate = @convention(c) (UnsafeMutableRawPointer, Int32, UInt32, UInt32, UInt32) -> Int32

    private static var create: Create?
    private static var openAct: Open?
    private static var closeAct: Close?
    private static var actuate: Actuate?
    private static var deviceID: UInt64 = 0
    static var isReady = false

    // Dal più lieve al più forte: light tap, weak click, soft thud,
    // medium tap, strong tap, strong click, strong thud.
    private static let ladder: [Int32] = [4, 1, 15, 5, 6, 2, 16]

    static func load(_ handle: UnsafeMutableRawPointer) {
        if let sym = dlsym(handle, "MTActuatorCreateFromDeviceID") {
            create = unsafeBitCast(sym, to: Create.self)
        }
        if let sym = dlsym(handle, "MTActuatorOpen") {
            openAct = unsafeBitCast(sym, to: Open.self)
        }
        if let sym = dlsym(handle, "MTActuatorClose") {
            closeAct = unsafeBitCast(sym, to: Close.self)
        }
        if let sym = dlsym(handle, "MTActuatorActuate") {
            actuate = unsafeBitCast(sym, to: Actuate.self)
        }
    }

    static func adopt(_ device: MTDevice) {
        guard !isReady else { return }
        var candidates: [UInt64] = []
        let offsetID = device.load(fromByteOffset: 64, as: UInt64.self)
        if offsetID != 0 { candidates.append(offsetID) }
        for id in registryDeviceIDs() where !candidates.contains(id) {
            candidates.append(id)
        }
        for id in candidates where opens(id) {
            deviceID = id
            isReady = true
            print(String(format: "aptica pronta (device 0x%llx)", id))
            return
        }
        print("aptica non disponibile: volume e luminosità restano, senza tick")
    }

    /// Sempre il waveform più lieve (light tap). La scala più forte resta
    /// nel `ladder`, ma non viene usata.
    static func tick(notch: Int) {
        guard hapticsEnabled else { return }
        _ = notch
        fire(ladder[0])
    }

    static func fire(_ waveform: Int32) {
        guard hapticsEnabled, isReady, let create, let openAct, let closeAct, let actuate else { return }
        guard let created = create(deviceID) else { return }
        let actuator = created.takeRetainedValue()
        let pointer = Unmanaged.passUnretained(actuator).toOpaque()
        if openAct(pointer, 0) == 0 {
            _ = actuate(pointer, waveform, 0, 0, 0)
        }
        _ = closeAct(pointer)
    }

    private static func opens(_ id: UInt64) -> Bool {
        guard let create, let openAct, let closeAct, let created = create(id) else { return false }
        let actuator = created.takeRetainedValue()
        let pointer = Unmanaged.passUnretained(actuator).toOpaque()
        let rc = openAct(pointer, 0)
        _ = closeAct(pointer)
        return rc == 0
    }

    private static func registryDeviceIDs() -> [UInt64] {
        guard let match = IOServiceMatching("AppleMultitouchDevice") else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var ids: [UInt64] = []
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            guard let raw = IORegistryEntryCreateCFProperty(service, "mt-device-id" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() else { continue }
            var number: Int64 = 0
            guard CFGetTypeID(raw) == CFNumberGetTypeID() else { continue }
            let cf = raw as! CFNumber
            guard CFNumberGetValue(cf, .sInt64Type, &number) else { continue }
            ids.append(UInt64(bitPattern: number))
        }
        return ids
    }
}

// MARK: - Gesto

enum Side {
    case volume, brightness

    var label: String { self == .volume ? "volume" : "luminosità" }

    func read() -> Float {
        switch self {
        case .volume: return readVolume()
        case .brightness: return Brightness.read() ?? 0.5
        }
    }

    func write(_ value: Float) {
        switch self {
        case .volume:
            writeVolume(value)
            SystemHUD.volume(value)
        case .brightness:
            Brightness.write(value)
            SystemHUD.brightness(value)
        }
    }
}

struct Slide {
    var ids: Set<Int32>
    var side: Side
    var anchorY: Float
    var lastY: Float
    var level: Float
    var armed: Bool
    var notch: Int
}

struct MediaSwipe {
    var ids: Set<Int32>
    var originX: Float
    var fired: Bool
}

enum TapTarget: Equatable {
    case corner(TrackCorner)
    case bottom
}

/// Letto anche dal tap degli eventi, fuori dal main thread.
nonisolated(unsafe) var captureGesture = false

struct Contact {
    var id: Int32
    var x: Float
    var y: Float
    var time: Double
    var travel: Float
    var corner: TrackCorner?
    var inBottom: Bool
}

final class Engine: @unchecked Sendable {
    var slide: Slide?
    var media: MediaSwipe?
    var contact: Contact?
    var lastTarget: TapTarget?
    var lastCornerTap = -Double.infinity
    var cursorFrozen = false
    var savedCursor = CGPoint.zero

    func handle(_ fingers: [Finger], time: Double) {
        if !BordiSettings.shared.enabled || (requireCommand && !commandDown()) {
            dropGesture()
            return
        }

        let live = fingers.filter { $0.phase != .other && $0.phase != .ended && !isPalm($0) }
        switch live.count {
        case 0:
            finishContact(time: time)
            endSlide(reason: nil)
        case 1:
            if slide != nil || media != nil { endSlide(reason: nil) }
            let finger = live[0]
            if contact?.id != finger.id {
                finishContact(time: time)
                beginTap(finger, time: time)
            } else {
                track(finger)
            }
        case 2:
            contact = nil
            scroll(live)
        default:
            dropGesture(reason: "più di due dita, gesto annullato")
        }
    }

    private func beginTap(_ finger: Finger, time: Double) {
        contact = Contact(
            id: finger.id,
            x: finger.x,
            y: finger.y,
            time: time,
            travel: 0,
            corner: corner(of: finger),
            inBottom: finger.y <= bottomReach
        )
    }

    private func corner(of finger: Finger) -> TrackCorner? {
        let left = finger.x <= cornerSize
        let right = finger.x >= 1 - cornerSize
        let top = finger.y >= 1 - cornerSize
        let bottom = finger.y <= cornerSize
        if top && left { return .topLeft }
        if top && right { return .topRight }
        if bottom && left { return .bottomLeft }
        if bottom && right { return .bottomRight }
        return nil
    }

    private func scroll(_ fingers: [Finger]) {
        let ys = fingers.map(\.y)
        let minY = ys.min() ?? 1
        let maxY = ys.max() ?? 1
        let xs = fingers.map(\.x)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let onBottom = minY <= bottomEdge && maxY <= bottomReach
        let onRight = maxX >= 1 - edgeWidth && minX >= 1 - twoFingerEdge
        let onLeft = minX <= edgeWidth && maxX <= twoFingerEdge
        let sidesOwnCorners = BordiSettings.shared.cornerPriority == .sides
        let bottomOwns = onBottom && !(sidesOwnCorners && (onLeft || onRight))
        if bottomOwns {
            slide = nil
            mediaSwipe(fingers)
            return
        }
        media = nil
        let side: Side? = onRight ? .volume : (onLeft ? .brightness : nil)
        guard let side else {
            if slide != nil {
                endSlide(reason: "dita uscite dalla striscia")
            } else if cursorFrozen {
                endSlide(reason: nil)
            }
            return
        }

        let ids = Set(fingers.map(\.id))
        let avgY = fingers.map(\.y).reduce(0, +) / Float(fingers.count)
        var current: Slide
        if let existing = slide, existing.ids == ids, existing.side == side {
            current = existing
        } else {
            let level = side.read()
            current = Slide(
                ids: ids,
                side: side,
                anchorY: avgY,
                lastY: avgY,
                level: level,
                armed: false,
                notch: Int((level * Float(notches)).rounded())
            )
        }

        // Dal primo frame sul bordo il puntatore resta dov'è.
        holdCursor()

        if !current.armed {
            guard abs(avgY - current.anchorY) >= armDistance else {
                slide = current
                return
            }
            current.armed = true
            current.lastY = avgY
            current.level = current.side.read()
            current.notch = Int((current.level * Float(notches)).rounded())
        }
        let scale: Float = optionDown() ? fineScale : 1
        let delta = (avgY - current.lastY) * sensitivity * scale
        current.lastY = avgY
        current.level = min(1, max(0, current.level + delta))
        current.side.write(current.level)
        let notch = Int((current.level * Float(notches)).rounded())
        if notch != current.notch {
            Haptics.tick(notch: notch)
            current.notch = notch
            print(String(format: "%@ %3.0f%%%@", current.side.label, current.level * 100, optionDown() ? "  (fine)" : ""))
        }
        slide = current
    }

    private func mediaSwipe(_ fingers: [Finger]) {
        let ids = Set(fingers.map(\.id))
        let avgX = fingers.map(\.x).reduce(0, +) / Float(fingers.count)
        var current: MediaSwipe
        if let existing = media, existing.ids == ids {
            current = existing
        } else {
            current = MediaSwipe(ids: ids, originX: avgX, fired: false)
        }
        holdCursor()
        if !current.fired {
            let dx = avgX - current.originX
            if abs(dx) >= mediaSwipeDistance {
                current.fired = true
                if dx > 0 {
                    CornerActions.nextTrack()
                    print("brano successivo")
                } else {
                    CornerActions.restartTrack()
                    print("brano ricominciato")
                }
            }
        }
        media = current
    }

    private func track(_ finger: Finger) {
        guard var current = contact else { return }
        let dx = finger.x - current.x
        let dy = finger.y - current.y
        current.travel = max(current.travel, hypotf(dx, dy))
        contact = current
    }

    private func finishContact(time: Double) {
        guard let current = contact else { return }
        contact = nil
        let duration = time - current.time
        let cornerAction = current.corner.flatMap { corner -> CornerAction? in
            let action = BordiSettings.shared.action(for: corner)
            return action == .none ? nil : action
        }
        let target: TapTarget? = {
            if let corner = current.corner, cornerAction != nil { return .corner(corner) }
            if current.inBottom { return .bottom }
            return nil
        }()
        let cleanTap = target != nil
            && current.travel < tapTravel
            && duration < tapMaxDuration
            && slide?.armed != true
        guard cleanTap, let target else {
            lastTarget = nil
            return
        }
        if lastTarget == target, time - lastCornerTap <= doubleTapGap {
            lastTarget = nil
            lastCornerTap = -.infinity
            switch target {
            case .corner(let corner):
                CornerActions.perform(
                    BordiSettings.shared.action(for: corner),
                    appPath: BordiSettings.shared.appPath(for: corner)
                )
            case .bottom:
                CornerActions.playPause()
            }
        } else {
            lastTarget = target
            lastCornerTap = time
        }
    }

    private func dropGesture(reason: String? = nil) {
        contact = nil
        lastTarget = nil
        lastCornerTap = -.infinity
        endSlide(reason: reason)
    }

    private func endSlide(reason: String?) {
        if let reason { print(reason) }
        slide = nil
        media = nil
        thawCursor()
        captureGesture = false
    }

    private func holdCursor() {
        captureGesture = true
        if !cursorFrozen {
            savedCursor = quartzCursor()
            CGAssociateMouseAndMouseCursorPosition(0)
            cursorFrozen = true
        }
        CGWarpMouseCursorPosition(savedCursor)
    }

    private func thawCursor() {
        guard cursorFrozen else { return }
        CGWarpMouseCursorPosition(savedCursor)
        CGAssociateMouseAndMouseCursorPosition(1)
        cursorFrozen = false
    }
}

var eventTap: CFMachPort?

func eventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    if captureGesture {
        switch type {
        case .scrollWheel, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return nil
        default:
            break
        }
    }
    return Unmanaged.passUnretained(event)
}

@discardableResult
func installEventTap() -> Bool {
    let watched: [CGEventType] = [
        .scrollWheel, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged
    ]
    let mask = watched.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: eventTapCallback,
        userInfo: nil
    ) else {
        fputs("Senza Accessibilità il puntatore può ancora spostarsi durante lo scroll sul bordo.\n", stderr)
        return false
    }
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    eventTap = tap
    return true
}

func quartzCursor() -> CGPoint {
    let cocoa = NSEvent.mouseLocation
    let height = NSScreen.screens.map(\.frame.maxY).max() ?? cocoa.y
    return CGPoint(x: cocoa.x, y: height - cocoa.y)
}

let engine = Engine()

// MARK: - MultitouchSupport

typealias MTDevice = UnsafeMutableRawPointer
typealias ContactCallback = @convention(c) (
    Int32, UnsafeMutableRawPointer?, Int32, Double, Int32
) -> Int32

func contactCallback(
    _ device: Int32,
    _ data: UnsafeMutableRawPointer?,
    _ nFingers: Int32,
    _ timestamp: Double,
    _ frame: Int32
) -> Int32 {
    let count = Int(nFingers)
    var copy: [MTData] = []
    if let data, count > 0 {
        let typed = data.assumingMemoryBound(to: MTData.self)
        copy = Array(UnsafeBufferPointer(start: typed, count: count))
    }
    let fingers = copy.map { raw in
        Finger(
            id: raw.identifier,
            x: raw.normalized.position.x,
            y: raw.normalized.position.y,
            size: raw.size,
            major: raw.majorAxis,
            minor: raw.minorAxis,
            phase: phase(of: raw.state)
        )
    }
    let time = timestamp
    DispatchQueue.main.async {
        engine.handle(fingers, time: time)
    }
    return 0
}

func startTrackpad() -> Bool {
    let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
    guard let handle = dlopen(path, RTLD_LAZY) else {
        let err = dlerror().map { String(cString: $0) } ?? "sconosciuto"
        fputs("dlopen fallito: \(err)\n", stderr)
        return false
    }
    Haptics.load(handle)

    typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    typealias Register = @convention(c) (MTDevice, ContactCallback) -> Void
    typealias Start = @convention(c) (MTDevice, Int32) -> Void
    typealias Dims = @convention(c) (MTDevice, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32

    guard let createListSym = dlsym(handle, "MTDeviceCreateList"),
          let registerSym = dlsym(handle, "MTRegisterContactFrameCallback"),
          let startSym = dlsym(handle, "MTDeviceStart")
    else {
        fputs("simboli del trackpad mancanti\n", stderr)
        return false
    }
    let createList = unsafeBitCast(createListSym, to: CreateList.self)
    let register = unsafeBitCast(registerSym, to: Register.self)
    let start = unsafeBitCast(startSym, to: Start.self)
    let dims = dlsym(handle, "MTDeviceGetSensorDimensions").map {
        unsafeBitCast($0, to: Dims.self)
    }
    guard let list = createList()?.takeRetainedValue() else {
        fputs("nessun device multitouch\n", stderr)
        return false
    }

    var started = 0
    for index in 0..<CFArrayGetCount(list) {
        guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
        let device = UnsafeMutableRawPointer(mutating: raw)
        var rows: Int32 = 0
        var cols: Int32 = 0
        if let dims { _ = dims(device, &rows, &cols) }
        print("device \(index): griglia \(rows)x\(cols)")
        if rows > 0 && rows < 10 {
            print("  salto: sensore ausiliario")
            continue
        }
        register(device, contactCallback)
        start(device, 0)
        started += 1
        print("  in ascolto")
        Haptics.adopt(device)
    }
    if started == 0 {
        fputs("nessun trackpad adatto\n", stderr)
        return false
    }
    return true
}

signal(SIGINT, SIG_IGN)
let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
interrupt.setEventHandler {
    engine.handle([], time: 0)
    exit(0)
}
interrupt.resume()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
