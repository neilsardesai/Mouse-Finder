//
//  AppDelegate.swift
//  Finder
//
//  Created by Neil Sardesai on 2/17/21.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: Properties
    
    private let contentView = NSImageView(image: NSImage(named: .base)!)
        
    private let eyes: NSImageView = {
        let eyes = NSImageView(image: NSImage(named: .eyes)!)
        eyes.imageScaling = .scaleAxesIndependently
        return eyes
    }()
    
    private weak var hoverAnimationTimer: Timer?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if !AXIsProcessTrusted() {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Needed"
            alert.informativeText = "This app uses accessibility features to find the mouse pointer on your screen."
            alert.addButton(withTitle: "Continue")
            if alert.runModal() == .alertFirstButtonReturn {
                let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
                _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            }
        }
        
        activateTheRealFinder()
        
        contentView.addSubview(eyes)
        eyes.frame = NSRect(origin: .baseEyesOrigin, size: eyes.image!.size)
        
        NSApp.dockTile.contentView = contentView
        NSApp.dockTile.display()
                
        NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] in
            guard let self = self else { return $0 }
            self.updateEyes()
            NSApp.dockTile.display()
            return $0
        }
        
        NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] _ in
            guard let self = self else { return }
            self.updateEyes()
            NSApp.dockTile.display()
        }
         
        let blinkTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            if Bool.random() { self?.performBlinkAnimation() }
        }
        blinkTimer.tolerance = 1
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        activateTheRealFinder()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openTheRealFinder()
        return false
    }
    
    private func activateTheRealFinder() {
        guard AXIsProcessTrusted() else { return }

        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == .realFinderBundleId }?
            .activate(options: [])
    }
    
    private func openTheRealFinder() {
        guard AXIsProcessTrusted() else { return }

        let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: .realFinderBundleId)!
        NSWorkspace.shared.openApplication(
            at: appUrl,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil
        )
    }
    
    // MARK: - Animations
    
    private func performBlinkAnimation() {
        var blinkSpeed: CGFloat = -0.5
        
        Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            
            self.eyes.frame.size.height += blinkSpeed
            
            if self.eyes.frame.height <= 0 {
                blinkSpeed = -blinkSpeed
            }
            if self.eyes.frame.height >= self.eyes.image!.size.height {
                self.eyes.frame.size.height = self.eyes.image!.size.height
                timer.invalidate()
            }
            
            NSApp.dockTile.display()
        }
    }
    
    private func performHoverAnimation() {
        guard hoverAnimationTimer == nil else { return }
        
        hoverAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            self.eyes.frame.origin.x.round()
            self.eyes.frame.origin.y.round()
            
            if self.eyes.frame.origin.x < NSPoint.baseEyesOrigin.x {
                self.eyes.frame.origin.x += 1
            }
            if self.eyes.frame.origin.x > NSPoint.baseEyesOrigin.x {
                self.eyes.frame.origin.x -= 1
            }
            if self.eyes.frame.origin.y < NSPoint.baseEyesOrigin.y {
                self.eyes.frame.origin.y += 1
            }
            if self.eyes.frame.origin.y > NSPoint.baseEyesOrigin.y {
                self.eyes.frame.origin.y -= 1
            }
            
            if self.eyes.frame.origin == NSPoint.baseEyesOrigin {
                self.hoverAnimationTimer?.invalidate()
                self.hoverAnimationTimer = nil
                
                self.eyes.isHidden = true
                self.contentView.image = NSImage(named: .hover)
            }
                        
            NSApp.dockTile.display()
        }
    }

    private func updateEyes() {
        guard AXIsProcessTrusted() else { return }
        
        /// The center of the icon in screen space
        var finderOrigin = NSPoint.zero
        let mouseLocation = NSEvent.mouseLocation
                        
        if let dockIcon = dockIcon() {                                    
            var values: CFArray?
            if AXUIElementCopyMultipleAttributeValues(
                dockIcon,
                [(kAXPositionAttribute as CFString), (kAXSizeAttribute as CFString)] as CFArray,
                .stopOnError,
                &values
            ) == .success {
                var position = CGPoint.zero
                var size = CGSize.zero
                
                (values as! [AXValue]).forEach { axValue in
                    AXValueGetValue(axValue, .cgPoint, &position)
                    AXValueGetValue(axValue, .cgSize, &size)
                }
                
                finderOrigin = NSPoint(
                    x: position.x + size.width / 2.0,
                    y: NSScreen.main!.frame.height - (position.y + size.height / 2.0)
                )
                
                // If the pointer is overlapping the icon
                if mouseLocation.x >= position.x
                    && mouseLocation.x <= position.x + size.width
                    && mouseLocation.y <= NSScreen.main!.frame.height - position.y
                    && mouseLocation.y >= NSScreen.main!.frame.height - position.y - size.height
                {
                    performHoverAnimation()
                    return
                } else {
                    hoverAnimationTimer?.invalidate()
                    hoverAnimationTimer = nil
                    eyes.isHidden = false
                    contentView.image = NSImage(named: .base)
                }
            }
        }
        
        let mouseXRelativeToFinder = mouseLocation.x - finderOrigin.x
        let mouseYRelativeToFinder = mouseLocation.y - finderOrigin.y
        
        var angle = atan(mouseYRelativeToFinder / mouseXRelativeToFinder)
        
        if mouseXRelativeToFinder < 0 {
            angle += .pi
        }
                
        let unitEyeX = cos(angle)
        let unitEyeY = sin(angle)
        
        let horizontalScaleFactor: CGFloat = 5
        let verticalScaleFactor: CGFloat = 10
        
        eyes.frame.origin.x = unitEyeX * horizontalScaleFactor + NSPoint.baseEyesOrigin.x
        eyes.frame.origin.y = unitEyeY * verticalScaleFactor + NSPoint.baseEyesOrigin.y
    }
    
    // MARK: - Accessibility Helpers
    
    /// The accessibility element for the app’s dock tile
    private func dockIcon() -> AXUIElement? {
        let appsWithDockBundleId = NSRunningApplication.runningApplications(withBundleIdentifier: .dockBundleId)
        guard let processId = appsWithDockBundleId.last?.processIdentifier else { return nil }
        let appElement = AXUIElementCreateApplication(processId)
        guard let firstChild = subelements(from: appElement, forAttribute: .axChildren)?.first else { return nil }
        // Reverse to avoid picking up the real Finder in case it’s in the Dock.
        guard let children = subelements(from: firstChild, forAttribute: .axChildren)?.reversed() else { return nil }
        for axElement in children {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(axElement, kAXTitleAttribute as CFString, &value) == .success {
                let appName = Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as! String
                if value as? String == appName { return axElement }
            }
        }
        return nil
    }
    
    private func subelements(from element: AXUIElement, forAttribute attribute: String) -> [AXUIElement]? {
        var subElements: CFArray?
        var count: CFIndex = 0
        if AXUIElementGetAttributeValueCount(element, attribute as CFString, &count) != .success {
            return nil
        }
        if AXUIElementCopyAttributeValues(element, attribute as CFString, 0, count, &subElements) != .success {
            return nil
        }
        return subElements as? [AXUIElement]
    }
    
}

// MARK: - Constants

private extension NSPoint {
    static let baseEyesOrigin = NSPoint(x: 38, y: 75)
}

private extension String {
    static let axChildren = "AXChildren"
    static let dockBundleId = "com.apple.dock"
    static let realFinderBundleId = "com.apple.finder"
}
