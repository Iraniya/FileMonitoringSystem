//
//  AppDelegate.swift
//  FileMonitoringSystem
//
//  Created by Iraniya Naynesh on 27/12/20.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    let menuIcon = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
        buildMenuBarMenu()
        if let button = menuIcon.button {
            button.image = NSImage(named: NSImage.Name("menuicon"))
        }
    }
    
    func buildMenuBarMenu() {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "Show App Window", action: #selector(showWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "Run in Background", action: #selector(hideDockIcon), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Run in Dock", action: #selector(showDockIcon), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "Quit File Monitoring",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))

        menuIcon.menu = menu
    }
    
    @objc func showWindow(_: Any?) {
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func showDockIcon(_: Any?) {
        NSApp.setActivationPolicy(.regular)
    }
    
    @objc func hideDockIcon(_: Any?) {
        NSApp.setActivationPolicy(.accessory)
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }


}


class AppWindowController: NSWindowController, NSWindowDelegate {
    func windowShouldClose(_: NSWindow) -> Bool {
        NSApp.hide(nil)
        return false
    }
}
