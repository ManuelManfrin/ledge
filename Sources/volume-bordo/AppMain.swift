import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        CGAssociateMouseAndMouseCursorPosition(1)
        Brightness.prepare()

        let model = AppModel.shared
        if startTrackpad() {
            model.ready = true
            if !installEventTap() {
                model.note = "Manca il permesso Accessibilità: durante lo scroll il puntatore può ancora spostarsi."
            }
        } else {
            model.note = "Nessun trackpad in ascolto. Abilita Bordi in Monitoraggio input e riaprila."
        }

        let host = NSHostingController(rootView: PopoverRoot())
        host.sizingOptions = .preferredContentSize
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = host

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = menuBarIcon()
            button.image?.isTemplate = true
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp])
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private func menuBarIcon() -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size, flipped: false) { rect in
        let body = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 3.2), xRadius: 2.2, yRadius: 2.2)
        NSColor.black.setStroke()
        body.lineWidth = 1.25
        body.stroke()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: 2.4, y: 5.2, width: 1.7, height: 7.6), xRadius: 0.6, yRadius: 0.6).fill()
        NSBezierPath(roundedRect: NSRect(x: 13.9, y: 5.2, width: 1.7, height: 7.6), xRadius: 0.6, yRadius: 0.6).fill()
        return true
    }
    image.isTemplate = true
    return image
}
