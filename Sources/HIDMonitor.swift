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
// never stores anything, and never talks to the network. It only counts how many reports arrive.

import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem

/// Carries the open result from the counting thread back to start().
private final class OpenResult { var code: IOReturn = kIOReturnError }

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

    func checkAccess() {
        let state = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        if state == kIOHIDAccessTypeGranted { access = .granted }
        else if state == kIOHIDAccessTypeDenied { access = .denied }
        else { access = .unknown }
    }

    func requestAccess() {
        let ok = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        checkAccess()
        if ok || access == .granted { start() }
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
            if result.code == kIOReturnSuccess {
                self.lock.lock(); self.manager = m; self.hidRunLoop = CFRunLoopGetCurrent(); self.lock.unlock()
            } else {
                IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            }
            opened.signal()
            if result.code == kIOReturnSuccess { CFRunLoopRun() }   // reports are handled here, off the main thread
        }
        thread.name = "Mouse Rate counting"
        thread.qualityOfService = .userInteractive
        thread.start()
        opened.wait()

        if result.code != kIOReturnSuccess {
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
        if access == .granted { start() }
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

/// The standard polling rate a reading is closest to, if it is close enough to call.
func standardRate(for rate: Int) -> Int? {
    let standards = [125, 250, 500, 1000, 2000, 4000, 8000]
    guard rate > 60 else { return nil }
    let best = standards.min(by: { abs($0 - rate) < abs($1 - rate) })!
    return abs(Double(best - rate)) / Double(best) <= 0.12 ? best : nil
}
