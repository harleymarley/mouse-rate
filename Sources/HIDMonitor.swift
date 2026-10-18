// HIDMonitor.swift
// Counts the raw HID input reports each connected mouse sends to this Mac, per second.
// This is the mouse's real polling rate in practice, measured below the browser and below
// macOS event coalescing (which is why every website on a Mac shows 60 or 120).
//
// The counting runs on its own thread. The window's main thread is busy drawing the test page
// at the screen's refresh rate, and if the reports were handled there, they would be picked up
// only about once per frame (about 120 a second), which is the very problem this app gets around.
//
// What this file does NOT do: it never reads which buttons you press or where the cursor is,
// never stores anything about you or your mouse, and never talks to the network. It only counts
// how many reports arrive. (The one thing it remembers is which build of the app last asked
// macOS for Input Monitoring, so it asks once per version instead of every launch.)

import Foundation
import AppKit
import Security
import IOKit
import IOKit.hid
import IOKit.hidsystem

/// Carries the open result from the counting thread back to start().
private final class OpenResult { var code: IOReturn = kIOReturnError; var keep = false }

// What IOKit returns when Input Monitoring isn't allowed for this copy of the app.
private let ioNotPermitted = IOReturn(bitPattern: 0xE00002E2)   // kIOReturnNotPermitted
private let ioNotPrivileged = IOReturn(bitPattern: 0xE00002C1)  // kIOReturnNotPrivileged

struct MouseDevice: Identifiable {
    let id: String          // one entry per physical mouse (product, transport, location, usage)
    var group: String = ""
    let name: String
    let transport: String
    var rate: Int = 0        // reports in the last second
    var peak: Int = 0        // highest full one-second reading
    var lastActive: Date = .distantPast
}

final class HIDMonitor: ObservableObject {
    enum Access { case unknown, granted, denied }

    @Published var access: Access = .unknown
    @Published var running = false
    @Published var openFailed = false
    @Published var devices: [MouseDevice] = []

    // What the permission card shows
    @Published var asking = false            // waiting on macOS to show or answer its prompt
    @Published var clearedOldEntry = false   // removed an Input Monitoring entry an earlier copy left behind
    @Published var needsManualFix = false    // macOS kept that old entry, so the card shows the manual steps
    @Published var restarting = false        // access just came through and the app is reopening to use it
    @Published private(set) var lastOpenCode: IOReturn = 0

    private var launched = false
    private var checkedOnce = false
    private var grantedThisSession = false   // turned on while this copy was running
    private let bundleID = Bundle.main.bundleIdentifier ?? "com.almostperfecttech.mouserate"
    private let build = buildFingerprint()
    private let askedKey = "inputMonitoringAskedForBuild"

    // Everything below is shared between the counting thread and the main thread, behind `lock`.
    private let lock = NSLock()
    private var manager: IOHIDManager?
    private var keyFor: [UnsafeMutableRawPointer: String] = [:]
    private var buffers: [UnsafeMutableRawPointer: UnsafeMutablePointer<UInt8>] = [:]
    private var info: [String: MouseDevice] = [:]
    private var counts: [String: Int] = [:]
    private var bins: [String: [Int]] = [:]

    private var hidThread: Thread?
    private var hidRunLoop: CFRunLoop?
    private var timer: Timer?

    // MARK: permission (System Settings > Privacy & Security > Input Monitoring)
    //
    // macOS ties an Input Monitoring entry to the exact copy of the app it was given to. Mouse Rate is
    // signed without a paid Apple certificate, so every new version (and every rebuild) looks like a
    // different app to macOS. The old entry still shows as on in System Settings, but it no longer
    // counts, macOS doesn't ask again on its own, and deleting the app doesn't remove the entry.
    // So when a new copy has no working access, Mouse Rate clears its own old entry (only its own,
    // by bundle ID) and asks once. All it takes from the person is turning the switch on.

    func checkAccess() {
        let state = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        let now: Access = state == kIOHIDAccessTypeGranted ? .granted : (state == kIOHIDAccessTypeDenied ? .denied : .unknown)
        if checkedOnce && now == .granted && access != .granted { grantedThisSession = true }
        checkedOnce = true
        if access != now { access = now }
    }

    /// Runs once when the window opens.
    func launch() {
        guard !launched else { return }
        launched = true
        checkAccess()
        if access == .granted {
            start()
            if running { return }
        }
        // No working access. Once per build, clear whatever an earlier copy left and ask macOS.
        // On a first install there's nothing to clear, so this just brings up the macOS prompt.
        if UserDefaults.standard.string(forKey: askedKey) != build {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.ask(clearFirst: true) }
        }
    }

    /// The Allow button. Works out what's in the way and deals with it.
    func allow() {
        checkAccess()
        switch access {
        case .unknown:
            ask(clearFirst: false)
        case .denied:
            // Either the switch isn't on yet, or the entry belongs to an earlier copy of the app.
            // If this copy already made the entry, the switch just needs turning on.
            if UserDefaults.standard.string(forKey: askedKey) == build && !needsManualFix { openSettings() }
            else { ask(clearFirst: true) }
        case .granted:
            openFailed = false
            start()
            if running { return }
            if grantedThisSession { reopenSoon() } else { ask(clearFirst: true) }
        }
    }

    /// Every 1.5 seconds while not counting. Notices the moment Mouse Rate is turned on.
    func poll() {
        guard !running else { return }
        let before = access
        checkAccess()
        guard access == .granted else { return }
        if before != .granted { openFailed = false }
        guard !openFailed else { return }
        start()
        if !running && grantedThisSession { reopenSoon() }
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Optionally clears this app's old entry, then asks macOS. Runs off the main thread so the
    /// window never freezes while the macOS prompt is up.
    private func ask(clearFirst: Bool) {
        guard !asking, !running else { return }
        asking = true
        UserDefaults.standard.set(build, forKey: askedKey)
        let id = bundleID
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var cleared = false, blocked = false
            if clearFirst && IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeUnknown {
                if clearInputMonitoringEntry(id) {
                    for _ in 0..<10 {
                        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeUnknown { cleared = true; break }
                        usleep(100_000)
                    }
                }
                blocked = !cleared
            }
            let before = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
            let ok = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.asking = false
                if cleared { self.clearedOldEntry = true }
                self.needsManualFix = blocked
                self.checkAccess()
                if ok || self.access == .granted {
                    self.openFailed = false
                    self.start()
                    if !self.running && self.grantedThisSession { self.reopenSoon() }
                    return
                }
                // macOS shows its own prompt only when there's no entry yet. Otherwise go straight to the switch.
                if before != kIOHIDAccessTypeUnknown { self.openSettings() }
            }
        }
    }

    /// macOS hands a new Input Monitoring setting to an app only after it restarts. System Settings
    /// offers Quit & Reopen for that. If it was skipped, Mouse Rate reopens itself.
    private func reopenSoon() {
        guard !restarting else { return }
        restarting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { relaunchApp() }
    }

    // MARK: start listening (on a dedicated thread)

    func start() {
        guard hidThread == nil else { return }
        let opened = DispatchSemaphore(value: 0)
        let result = OpenResult()
        let ctx = Unmanaged.passUnretained(self).toOpaque()

        let thread = Thread {
            let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            let matching: [[String: Any]] = [
                [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
                [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer],
            ]
            IOHIDManagerSetDeviceMatchingMultiple(m, matching as CFArray)
            IOHIDManagerRegisterDeviceMatchingCallback(m, { context, _, _, device in
                guard let context = context else { return }
                Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue().matched(device)
            }, ctx)
            IOHIDManagerRegisterDeviceRemovalCallback(m, { context, _, _, device in
                guard let context = context else { return }
                Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue().removed(device)
            }, ctx)
            IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            result.code = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
            // IOHIDManagerOpen returns the error of the first mouse that failed to open, even when the
            // others opened fine (another mouse app can hold one connection for itself). Only a
            // permission error means nothing can be counted.
            result.keep = result.code != ioNotPermitted && result.code != ioNotPrivileged
            if result.keep {
                self.lock.lock(); self.manager = m; self.hidRunLoop = CFRunLoopGetCurrent(); self.lock.unlock()
            } else {
                IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
                IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            }
            opened.signal()
            if result.keep { CFRunLoopRun() }   // reports are handled here, off the main thread
        }
        thread.name = "Mouse Rate counting"
        thread.qualityOfService = .userInteractive
        thread.start()
        opened.wait()

        lastOpenCode = result.code
        if !result.keep {
            openFailed = true
            checkAccess()
            return
        }
        hidThread = thread
        openFailed = false
        running = true
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: stop and start over (for testing a different mouse without quitting the app)

    func stop() {
        timer?.invalidate(); timer = nil
        lock.lock(); let rl = hidRunLoop; let m = manager; lock.unlock()
        var closed = true
        if let rl = rl, let m = m {
            let done = DispatchSemaphore(value: 0)
            // close the manager on its own thread, so no report can arrive halfway through
            CFRunLoopPerformBlock(rl, CFRunLoopMode.defaultMode.rawValue) {
                IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
                IOHIDManagerUnscheduleFromRunLoop(m, rl, CFRunLoopMode.defaultMode.rawValue)
                CFRunLoopStop(rl)
                done.signal()
            }
            CFRunLoopWakeUp(rl)
            closed = done.wait(timeout: .now() + 2) == .success
        }
        lock.lock()
        if closed { for b in buffers.values { b.deallocate() } }   // if it never closed, leaving a few bytes is safer than freeing them
        buffers = [:]; keyFor = [:]; info = [:]; counts = [:]; bins = [:]
        manager = nil; hidRunLoop = nil
        lock.unlock()
        hidThread = nil
        running = false
        devices = []
    }

    /// Forget every mouse and look for them again. Picks up a mouse that was just switched on or plugged in.
    func restart() {
        stop()
        checkAccess()
        if access == .granted { openFailed = false; start() }
    }

    // MARK: device callbacks (counting thread)

    fileprivate func matched(_ device: IOHIDDevice) {
        let ptr = Unmanaged.passUnretained(device).toOpaque()
        let product = ((IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "Mouse")
            .trimmingCharacters(in: .whitespaces)
        let transport = (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String) ?? "Unknown"
        let page = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int) ?? 0
        let usage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int) ?? 0
        let location = (IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int) ?? 0
        // Some receivers show up as more than one interface. Every interface is counted on its own,
        // and the busiest one stands for the mouse. (Picking just the first one can land on a
        // slower interface, which is how a 1000Hz mouse ended up reading 125.)
        let group = "\(product)|\(transport)|\(location)|\(page)|\(usage)"
        let key = group + "#\(UInt(bitPattern: ptr))"

        lock.lock()
        if keyFor[ptr] != nil { lock.unlock(); return }
        keyFor[ptr] = key
        info[key] = MouseDevice(id: key, group: group, name: product.isEmpty ? "Mouse" : product, transport: transport)
        let reported = (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int) ?? 64
        let size = max(reported, 8)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        buffers[ptr] = buffer
        lock.unlock()

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, size, { context, _, sender, _, _, _, length in
            guard let context = context, let sender = sender, length > 0 else { return }
            Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue().report(from: sender)
        }, ctx)
        // the same as the Terminal tool, which reads the full rate: schedule the device on this thread's run loop
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        DispatchQueue.main.async { [weak self] in self?.publish() }
    }

    fileprivate func removed(_ device: IOHIDDevice) {
        let ptr = Unmanaged.passUnretained(device).toOpaque()
        lock.lock()
        if let key = keyFor.removeValue(forKey: ptr), !keyFor.values.contains(key) {
            info.removeValue(forKey: key); counts.removeValue(forKey: key); bins.removeValue(forKey: key)
        }
        // The buffer is freed only after the device is gone, so no callback can still write to it.
        if let b = buffers.removeValue(forKey: ptr) { b.deallocate() }
        lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.publish() }
    }

    fileprivate func report(from sender: UnsafeMutableRawPointer) {
        lock.lock()
        if let key = keyFor[sender] { counts[key, default: 0] += 1 }
        lock.unlock()
    }

    // MARK: every 250 ms on the main thread, roll a one-second window

    private func tick() {
        let now = Date()
        lock.lock()
        for key in Array(info.keys) {
            var b = bins[key] ?? []
            b.append(counts[key] ?? 0)
            if b.count > 4 { b.removeFirst(b.count - 4) }
            bins[key] = b
            let rate = b.reduce(0, +)
            guard var dev = info[key] else { continue }
            dev.rate = rate
            if b.count == 4 && b.allSatisfy({ $0 > 0 }) { dev.peak = max(dev.peak, rate) }
            if rate > 0 { dev.lastActive = now }
            info[key] = dev
        }
        counts.removeAll(keepingCapacity: true)
        lock.unlock()
        publish()
    }

    private func publish() {
        lock.lock()
        let snapshot = Array(info.values)
        lock.unlock()
        // one line per physical mouse: the busiest interface wins
        var best: [String: MouseDevice] = [:]
        for d in snapshot {
            if let cur = best[d.group] {
                if d.rate > cur.rate || (d.rate == cur.rate && d.peak > cur.peak) {
                    var m = d; m.peak = max(d.peak, cur.peak); m.lastActive = max(d.lastActive, cur.lastActive); best[d.group] = m
                } else {
                    var m = cur; m.peak = max(d.peak, cur.peak); m.lastActive = max(d.lastActive, cur.lastActive); best[d.group] = m
                }
            } else { best[d.group] = d }
        }
        devices = best.values.map { d -> MouseDevice in
            var m = MouseDevice(id: d.group, group: d.group, name: d.name, transport: d.transport)
            m.rate = d.rate; m.peak = d.peak; m.lastActive = d.lastActive
            return m
        }.sorted {
            if $0.rate != $1.rate { return $0.rate > $1.rate }
            if $0.lastActive != $1.lastActive { return $0.lastActive > $1.lastActive }
            return $0.name < $1.name
        }
    }

    func resetPeaks() {
        lock.lock()
        for key in Array(info.keys) { info[key]?.peak = 0 }
        lock.unlock()
        publish()
    }
}

/// A fingerprint of this exact build: the hash in its code signature, the same thing macOS ties the
/// Input Monitoring entry to. Falls back to the version and build time.
private func buildFingerprint() -> String {
    var code: SecCode?
    var staticCode: SecStaticCode?
    var info: CFDictionary?
    if SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code = code,
       SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode = staticCode,
       SecCodeCopySigningInformation(staticCode, SecCSFlags(), &info) == errSecSuccess,
       let dict = info as? [String: Any], let hash = dict[kSecCodeInfoUnique as String] as? Data, !hash.isEmpty {
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    return "\(AppConfig.version) \(AppConfig.built)"
}

/// Removes Mouse Rate's own Input Monitoring entry with Apple's tccutil, so the next request creates a
/// fresh one for this copy. The bundle ID is always passed, so no other app's setting is touched.
private func clearInputMonitoringEntry(_ bundleID: String) -> Bool {
    guard !bundleID.isEmpty else { return false }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
    p.arguments = ["reset", "ListenEvent", bundleID]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0
}

/// The standard polling rate a reading is closest to, if it is close enough to call.
func standardRate(for rate: Int) -> Int? {
    let standards = [125, 250, 500, 1000, 2000, 4000, 8000]
    guard rate > 60 else { return nil }
    let best = standards.min(by: { abs($0 - rate) < abs($1 - rate) })!
    return abs(Double(best - rate)) / Double(best) <= 0.12 ? best : nil
}
