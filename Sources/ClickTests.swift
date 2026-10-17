// ClickTests.swift
// Step 3 (double-click check) and step 4 (click speed).

import SwiftUI
import AppKit

// MARK: - Step 3: double-click

struct DoubleClickTest: View {
    @ObservedObject var flow: TestFlow
    private let goal = 20
    private let phantomMs = 80.0

    @State private var clicks = 0
    @State private var phantom = 0
    @State private var closest: Double?
    @State private var lastDown: [Int: TimeInterval] = [:]
    @State private var segments: [Int] = []      // 0 = waiting, 1 = good, 2 = counted twice
    @State private var label = ""
    @State private var bump = false
    @State private var flag = false
    @State private var quip = ""
    @State private var finishedStep = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Click the box **slowly, about once a second**, 20 times, with the button you want to check. If one press shows up as 2 clicks, the switch inside is wearing out. That's the most common reason mice get replaced.")
                .font(.ui(16)).foregroundColor(.aptSoft).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 760, alignment: .leading)
            TestBox(height: 400, active: flag, onEvent: handle) {
                ZStack {
                    SegmentRing(segments: segments, count: goal).frame(width: 260, height: 260)
                    VStack(spacing: 10) {
                        Text("\(clicks)").font(.number(84)).foregroundColor(.aptText).scaleEffect(bump ? 1.12 : 1)
                        Text(label).font(.ui(18, .semibold)).foregroundColor(.aptHi)
                            .multilineTextAlignment(.center).frame(width: 200).id(label)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.aptBad.opacity(flag ? 0.7 : 0), lineWidth: 2))
            if clicks >= goal {
                Panel(glow: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your switch").font(.ui(14, .medium)).foregroundColor(.aptSoft)
                        Text(phantom == 0 ? "No phantom clicks" : "\(phantom) phantom \(phantom == 1 ? "click" : "clicks")")
                            .font(.display(46)).foregroundColor(phantom == 0 ? .aptOk : .aptBad)
                        Quip(text: quip)
                        Text(phantom == 0 ? "Every press registered once in \(clicks) clicks. Your switch looks healthy."
                             : "Some single presses showed up as 2 clicks, the closest \(Int(closest ?? 0)) milliseconds apart. That's a sign the switch is wearing out. Run it again to confirm.")
                            .font(.ui(15)).foregroundColor(.aptSoft).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            SecondaryButton(title: "Start over", action: reset)
        }
        .onAppear { if segments.isEmpty { reset() } }
    }

    private func reset() {
        clicks = 0; phantom = 0; closest = nil; lastDown = [:]; finishedStep = false; quip = ""
        segments = Array(repeating: 0, count: goal)
        label = Copy.dcLabel(clicks: 0, gapMs: nil, phantom: false, cheeky: flow.cheeky)
    }

    private func handle(_ e: NSEvent) {
        guard [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(e.type) else { return }
        let b = e.type == .leftMouseDown ? 0 : (e.type == .rightMouseDown ? 1 : e.buttonNumber)
        let gap = lastDown[b].map { (e.timestamp - $0) * 1000 }
        lastDown[b] = e.timestamp
        let bad = (gap ?? .infinity) < phantomMs
        clicks += 1
        if let g = gap { closest = min(closest ?? g, g) }
        let i = (clicks - 1) % goal
        if clicks <= goal || bad { segments[i] = bad ? 2 : 1 }
        if bad {
            phantom += 1
            withAnimation(.easeOut(duration: 0.1)) { flag = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { withAnimation { flag = false } }
        }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { bump = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { bump = false } }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
            label = Copy.dcLabel(clicks: clicks, gapMs: gap, phantom: bad, cheeky: flow.cheeky)
        }
        if clicks >= goal && !finishedStep {
            finishedStep = true
            quip = Copy.dcQuip(phantom: phantom, cheeky: flow.cheeky)
            flow.doubleClick = DoubleClickResult(clicks: clicks, phantom: phantom, closestMs: closest.map { Int($0) })
            flow.complete(.doubleClick, summary: phantom == 0 ? "No phantom clicks" : "\(phantom) phantom \(phantom == 1 ? "click" : "clicks")",
                          quip: Copy.dcQuip(phantom: phantom, cheeky: flow.cheeky))
        }
    }
}

struct SegmentRing: View {
    let segments: [Int]
    let count: Int
    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let step = 1.0 / Double(count), gap = 0.012
                Circle()
                    .trim(from: Double(i) * step + gap / 2, to: Double(i + 1) * step - gap / 2)
                    .stroke(color(i < segments.count ? segments[i] : 0), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: i < segments.count ? segments[i] : 0)
            }
        }
    }
    private func color(_ v: Int) -> Color {
        switch v { case 1: return .aptOrange; case 2: return .aptBad; default: return Color.white.opacity(0.1) }
    }
}

// MARK: - Step 4: click speed

struct ClickSpeedTest: View {
    @ObservedObject var flow: TestFlow

    @State private var seconds = 5
    @State private var count = 0
    @State private var start: Date?
    @State private var done = false
    @State private var now = Date()
    @State private var bump = false
    @State private var quip = ""
    @State private var rounds = 0
    @State private var label = ""
    @StateObject private var ticker = Ticker(0.05)

    private var elapsed: Double { start.map { min(Double(seconds), now.timeIntervalSince($0)) } ?? 0 }
    private var score: Double { Double(count) / Double(seconds) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("How fast can you click? The timer starts on your first click. This one measures your finger more than your mouse, so have fun with it.")
                .font(.ui(16)).foregroundColor(.aptSoft).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 760, alignment: .leading)
            HStack(spacing: 8) {
                durationChip(5); durationChip(10)
            }
            TestBox(height: 400, active: start != nil && !done, onEvent: handle) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 6).frame(width: 250, height: 250)
                    Circle().trim(from: 0, to: elapsed / Double(seconds))
                        .stroke(LinearGradient(colors: [.aptPale, .aptOrange], startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90)).frame(width: 250, height: 250)
                        .shadow(color: Color.aptOrange.opacity(0.7), radius: 9)
                    VStack(spacing: 10) {
                        Text("\(count)").font(.number(84)).foregroundColor(.aptText).scaleEffect(bump ? 1.12 : 1)
                        Text(label).font(.ui(18, .semibold)).foregroundColor(.aptHi)
                            .multilineTextAlignment(.center).frame(width: 210)
                    }
                    .offset(y: done ? -20 : 0)
                }
            }
            if done {
                Panel(glow: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your speed").font(.ui(14, .medium)).foregroundColor(.aptSoft)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(String(format: "%.1f", score)).font(.display(54)).foregroundColor(.aptOrange)
                            Text("clicks per second").font(.display(38)).foregroundColor(.aptText)
                        }
                        Quip(text: quip)
                        Text("\(count) clicks in \(seconds) seconds. " + Copy.cpsNote(score)).font(.ui(15)).foregroundColor(.aptSoft)
                        PrimaryButton(title: rounds >= 2 && flow.cheeky ? "Again? Already?" : (flow.cheeky ? "Go again" : "Try again"), action: reset)
                    }
                }
            }
        }
        .onAppear { if label.isEmpty { label = idleLabel } }
        .onReceive(ticker.$now) { t in tick(t) }
    }

    private var idleLabel: String { flow.cheeky ? "Show me what you've got" : "Click to start" }

    private func durationChip(_ s: Int) -> some View {
        Button(action: { if start == nil || done { seconds = s; reset() } }) {
            Text("\(s) seconds").font(.ui(14, .semibold))
                .foregroundColor(seconds == s ? .aptInk : .aptSoft)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Capsule().fill(seconds == s ? Color.aptOrange : Color.white.opacity(0.04)))
        }
        .buttonStyle(PressStyle())
    }

    private func reset() {
        count = 0; start = nil; done = false; quip = ""; label = idleLabel
    }

    private func handle(_ e: NSEvent) {
        guard e.type == .leftMouseDown, !done else { return }
        if start == nil { start = Date(); now = Date() }
        count += 1
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { bump = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { bump = false } }
    }

    private func tick(_ t: Date) {
        guard let s = start, !done else { return }
        now = t
        let el = t.timeIntervalSince(s)
        label = Copy.cpsLabel(left: max(0, Double(seconds) - el), rate: el > 0.4 ? Double(count) / el : 0, elapsed: el, cheeky: flow.cheeky)
        if el >= Double(seconds) { finish() }
    }

    private func finish() {
        done = true; rounds += 1
        label = flow.cheeky ? "Done already?" : "Time's up"
        quip = Copy.cpsQuip(score, cheeky: flow.cheeky)
        flow.clickSpeed = ClickSpeedResult(clicks: count, seconds: seconds)
        flow.complete(.clickSpeed, summary: String(format: "%.1f clicks per second", score), quip: Copy.cpsQuip(score, cheeky: flow.cheeky))
    }
}
