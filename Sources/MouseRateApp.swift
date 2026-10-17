// MouseRateApp.swift
// Mouse Rate: shows the real polling rate of your mouse on a Mac.
// Free and open source, by Almost Perfect Tech.

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct MouseRateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = HIDMonitor()

    var body: some Scene {
        WindowGroup("Mouse Rate") {
            ContentView(monitor: monitor)
        }
        .defaultSize(width: 1280, height: 860)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
