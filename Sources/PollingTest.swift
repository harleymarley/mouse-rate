// PollingTest.swift
// Step 1. The real polling rate, counted straight from the mouse by HIDMonitor.

import SwiftUI

struct PollingTest: View {
    @ObservedObject var monitor: HIDMonitor
    @ObservedObject var flow: TestFlow

    private enum Phase { case waiting, running, done }
    @State private var phase: Phase = .waiting
    @State private var samples: [Int] = []
    @State private var paused = false
    @State private var label = ""
    @State private var labelBucket = -1
    @State private var labelAt = Date.distantPast
    @State private var shown: Double = 0
    @State private var quip = ""

    private let goal = 24   // 24 readings x 250 ms = 6 seconds of movement, the first second is warm-up

    private var live: Int { monitor.devices.first?.rate ?? 0 }
    private var progress: Double { min(1, Double(samples.count) / Double(goal)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your mouse's **polling rate** is how many times per second it tells your Mac where it is. Move your mouse in steady circles for about 5 seconds. This app counts it straight from the mouse, so this is the real number, not the 120 every website shows.")
                .font(.ui(16)).foregroundColor(.aptSoft).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 760, alignment: .leading)

            if !monitor.running {
                permission
            } else {
                TestBox(height: 400, active: phase == .running, onEvent: { _ in }) {
                    VStack(spacing: 6) {
                        ZStack {
                            SpeedGauge(value: shown, progress: phase == .waiting ? 0 : progress)
                                .frame(width: 330, height: 330)
                            VStack(spacing: 0) {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text("\(Int(shown.rounded()))").font(.number(92)).foregroundColor(phase == .waiting ? .aptDim : .aptText)
                                    Text("Hz").font(.number(26)).foregroundColor(.aptMuted)
                                }
                                Text(label).font(.ui(17, .semibold)).foregroundColor(.aptHi)
                                    .multilineTextAlignment(.center).frame(maxWidth: 230)
                                    .animation(.easeOut(duration: 0.25), value: label)
                            }
                            .offset(y: 8)
                        }
                    }
                }
                if phase == .done, let r = flow.poll { result(r) }
                devicesList
            }
        }
        .onAppear { label = Copy.pollIdle(cheeky: flow.cheeky) }
        .onReceive(monitor.$devices) { _ in tick() }
    }

    // MARK: test logic

    private func tick() {
        // ease the big number toward the live reading
        let target = Double(phase == .done ? (flow.poll?.avg ?? live) : live)
        shown += (target - shown) * 0.6
        guard monitor.running, flow.card == nil, flow.step == .polling else { return }
        switch phase {
        case .waiting:
            if live > 0 { phase = .running; samples = []; updateLabel(force: true) }
        case .running:
            if live > 0 { samples.append(live); paused = false } else { paused = true }
            updateLabel(force: false)
            if samples.count >= goal { finish() }
        case .done:
            break
        }
    }

    private func updateLabel(force: Bool) {
        let bucket = paused ? 9 : Int(progress * 4)
        if force || bucket != labelBucket || Date().timeIntervalSince(labelAt) > 1.6 {
            labelBucket = bucket; labelAt = Date()
            label = Copy.pollLive(progress: progress, paused: paused, cheeky: flow.cheeky)
        }
    }

    private func finish() {
        let use = Array(samples.dropFirst(4)).filter { $0 > 0 }
        guard !use.isEmpty else { return }
        let sorted = use.sorted()
        let avg = sorted[sorted.count / 2]
        let held = Double(use.filter { abs(Double($0 - avg)) / Double(max(avg, 1)) <= 0.1 }.count) / Double(use.count)
        let top = monitor.devices.first
        let t = (top?.transport ?? "").lowercased()
        let connection = t.contains("bluetooth") ? "Bluetooth" : t == "usb" ? "USB or receiver" : (top?.transport ?? "")
        let r = PollResult(avg: avg, peak: sorted.last ?? avg, steady: held, device: top?.name ?? "Mouse", connection: connection)
        if flow.mouseName.trimmingCharacters(in: .whitespaces).isEmpty || flow.mouseName == flow.poll?.device {
            flow.mouseName = r.device == "Mouse" ? "" : r.device
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
            flow.poll = r
            phase = .done
        }
        label = Copy.pollDone(cheeky: flow.cheeky)
        quip = Copy.pollQuip(r.snapped ?? avg, cheeky: flow.cheeky)
        let summary = flow.cheeky ? "Your mouse reports \(r.label)" : "Your mouse reports \(r.label)"
        flow.complete(.polling, summary: summary, quip: Copy.pollQuip(r.snapped ?? avg, cheeky: flow.cheeky))
    }

    private func again() {
        withAnimation { phase = .waiting; samples = []; flow.poll = nil; quip = "" }
        label = Copy.pollIdle(cheeky: flow.cheeky)
    }

    // MARK: pieces

    private func result(_ r: PollResult) -> some View {
        Panel(glow: true) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Your mouse").font(.ui(14, .medium)).foregroundColor(.aptSoft)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(r.snapped != nil ? "About" : "").font(.display(54)).foregroundColor(.aptText)
                    Text(r.label).font(.display(54)).foregroundColor(.aptOrange)
                }
                Quip(text: quip)
                Text(Copy.pollNote(r.snapped ?? r.avg)).font(.ui(15)).foregroundColor(.aptSoft)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 640, alignment: .leading)
                HStack(spacing: 10) {
                    Stat(label: "Steady average", value: "\(r.avg)Hz")
                    Stat(label: "Peak", value: "\(r.peak)Hz")
                    Stat(label: "Held steady", value: "\(Int((r.steady * 100).rounded()))%")
                    Stat(label: "Measured on", value: r.device)
                }
                HStack(spacing: 12) {
                    TextField("Which mouse? (optional, for the comment)", text: $flow.mouseName)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                    PrimaryButton(title: "Copy for the comments") {
                        let who = flow.mouseName.trimmingCharacters(in: .whitespaces)
                        copyToClipboard("\(who.isEmpty ? "My mouse" : "My " + who) got \(r.label) on the Almost Perfect mouse test (Mac app).")
                    }
                    SecondaryButton(title: flow.cheeky ? "Go again" : "Test again", action: again)
                }
            }
        }
    }

    private var devicesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(monitor.devices.count > 1 ? "Every mouse connected" : "Connected mouse")
                .font(.ui(13, .medium)).foregroundColor(.aptMuted)
            if monitor.devices.isEmpty {
                Text("No mouse found yet. Plug one in, or turn on its receiver or Bluetooth.").font(.ui(14)).foregroundColor(.aptMuted)
            }
            ForEach(monitor.devices) { d in
                HStack {
                    Circle().fill(d.rate > 0 ? Color.aptOrange : Color.aptDim).frame(width: 8, height: 8)
                    Text(d.name).font(.ui(14, .semibold)).foregroundColor(.aptText)
                    Text(d.transport.lowercased() == "usb" ? "USB or receiver" : d.transport).font(.ui(12)).foregroundColor(.aptMuted)
                    Spacer()
                    Text("\(d.rate)/s").font(.number(15)).foregroundColor(d.rate > 0 ? .aptHi : .aptMuted)
                    Text(d.peak > 0 ? "best \(d.peak)" : "").font(.ui(12)).foregroundColor(.aptMuted).frame(width: 74, alignment: .trailing)
                }
                .padding(.vertical, 8).padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
            }
        }
    }

    private var permission: some View {
        Panel(glow: true) {
            VStack(alignment: .leading, spacing: 14) {
                Text("One permission first").font(.display(30)).foregroundColor(.aptText)
                Text("To count your mouse's reports, macOS needs you to allow Input Monitoring for Mouse Rate. The app only counts how many reports arrive. It never reads your keys, your clicks or where the cursor is, and it has no network code at all. The other three tests work without this.")
                    .font(.ui(15)).foregroundColor(.aptSoft).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 680, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    Text("1.  When macOS asks, click Open System Settings. No prompt? Click Allow.").font(.ui(15)).foregroundColor(.aptText)
                    Text("2.  Turn on Mouse Rate under Input Monitoring.").font(.ui(15)).foregroundColor(.aptText)
                    Text("3.  Click Quit & Reopen. If you skip that, Mouse Rate reopens by itself.").font(.ui(15)).foregroundColor(.aptText)
                }
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(monitor.restarting ? Color.aptOk : Color.aptOrange).frame(width: 8, height: 8).padding(.top, 5)
                    Text(permissionStatus).font(.ui(14, .semibold)).foregroundColor(monitor.restarting ? .aptOk : .aptHi)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 680, alignment: .leading)
                }
                .animation(.easeOut(duration: 0.25), value: permissionStatus)
                HStack(spacing: 12) {
                    PrimaryButton(title: "Allow") { monitor.allow() }
                    SecondaryButton(title: "Reopen Mouse Rate", action: relaunchApp)
                }
                Text("Still stuck? In System Settings, open Privacy & Security, then Input Monitoring. Select Mouse Rate, click the minus button to remove it, then click Allow here.")
                    .font(.ui(13)).foregroundColor(monitor.needsManualFix ? .aptSoft : .aptMuted)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 680, alignment: .leading)
                if monitor.openFailed {
                    Text("For support: access \(String(describing: monitor.access)), open code \(String(format: "%08x", UInt32(bitPattern: monitor.lastOpenCode)))")
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(.aptDim)
                }
            }
        }
    }

    /// One line on the permission card that says what Mouse Rate is waiting for.
    private var permissionStatus: String {
        if monitor.restarting { return "Input Monitoring is on. Reopening Mouse Rate so it can start counting." }
        if monitor.asking { return "Waiting for macOS." }
        if monitor.needsManualFix { return "macOS kept an old entry from an earlier copy of Mouse Rate. Remove it once with the steps below." }
        switch monitor.access {
        case .granted:
            return "macOS lists Mouse Rate as allowed, but this copy can't read your mouse yet. Click Allow to fix it."
        case .denied:
            return monitor.clearedOldEntry
                ? "Cleared an old entry from an earlier copy. Now turn on Mouse Rate in Input Monitoring."
                : "Waiting for Mouse Rate to be turned on in Input Monitoring."
        case .unknown:
            return "Click Allow and macOS will ask."
        }
    }
}

/// The speedometer: a 270 degree arc on a log scale from 60 to 8000, plus a thin outer ring for test progress.
struct SpeedGauge: View {
    let value: Double
    let progress: Double

    static func frac(_ v: Double) -> Double {
        guard v > 0 else { return 0 }
        return max(0, min(1, (log(v) - log(60)) / (log(8000) - log(60))))
    }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                GaugeArc(to: 1).stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                GaugeArc(to: SpeedGauge.frac(value))
                    .stroke(LinearGradient(colors: [.aptOrange, .aptPale], startPoint: .bottomLeading, endPoint: .topTrailing),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .shadow(color: Color.aptOrange.opacity(0.6), radius: 10)
                GaugeArc(to: progress, inset: -16)
                    .stroke(Color.aptPale.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                ForEach([125, 250, 500, 1000, 2000, 4000, 8000], id: \.self) { mark in
                    Text(mark >= 1000 ? "\(mark / 1000)K" : "\(mark)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(.aptMuted)
                        .position(SpeedGauge.point(for: mark, size: s))
                }
            }
            .frame(width: s, height: s)
            .animation(.easeOut(duration: 0.25), value: value)
            .animation(.easeOut(duration: 0.25), value: progress)
        }
    }

    static func point(for mark: Int, size s: CGFloat) -> CGPoint {
        let a = (135 + 270 * frac(Double(mark))) * Double.pi / 180
        let r = Double(s) / 2 - 40
        return CGPoint(x: Double(s) / 2 + cos(a) * r, y: Double(s) / 2 + sin(a) * r)
    }
}

struct GaugeArc: Shape {
    var to: Double
    var inset: CGFloat = 0
    var animatableData: Double { get { to } set { to = newValue } }

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2 - inset
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: max(r, 1),
                 startAngle: .degrees(135), endAngle: .degrees(135 + 270 * max(0.0001, min(1, to))), clockwise: false)
        return p
    }
}

func relaunchApp() {
    let config = NSWorkspace.OpenConfiguration()
    config.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
}
