// ContentView.swift
// The app window: header, the four numbered steps, the current test, and the step cards.

import SwiftUI
import AppKit
import Combine

struct ContentView: View {
    @ObservedObject var monitor: HIDMonitor
    @StateObject private var flow = TestFlow()
    @StateObject private var poll = Ticker(1.5)

    var body: some View {
        ZStack {
            Color.aptBg.ignoresSafeArea()
            RadialGradient(colors: [Color.aptOrange.opacity(0.10), .clear], center: .topLeading, startRadius: 0, endRadius: 700)
                .ignoresSafeArea().allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                header.padding(.horizontal, 32).padding(.top, 22)
                stepper.padding(.horizontal, 32).padding(.top, 22)
                ScrollView {
                    Group {
                        switch flow.step {
                        case .polling: PollingTest(monitor: monitor, flow: flow)
                        case .buttons: ButtonsTest(flow: flow)
                        case .doubleClick: DoubleClickTest(flow: flow)
                        case .clickSpeed: ClickSpeedTest(flow: flow)
                        case .report: ReportView(flow: flow)
                        }
                    }
                    .id("\(flow.step.rawValue)-\(flow.runID)")
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                    .padding(.horizontal, 32).padding(.vertical, 22)
                    .frame(maxWidth: 1180, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    footer.padding(.horizontal, 32).padding(.bottom, 24)
                        .frame(maxWidth: 1180, alignment: .leading)
                        .frame(maxWidth: .infinity)
                }
            }

        }
        .frame(minWidth: 900, idealWidth: 1180, maxWidth: .infinity, minHeight: 640, idealHeight: 860, maxHeight: .infinity)
        .overlay {
            // the step cards sit on top of the whole window, centered
            if let card = flow.card {
                StepCardView(card: card, flow: flow)
                    .id(card.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            let m = monitor
            flow.restartMonitor = { m.restart() }
            // starts counting if Input Monitoring works, otherwise sorts out the permission (see HIDMonitor)
            monitor.launch()
            // the welcome card waits until the permission is sorted, so it never covers the Allow button
            if monitor.running { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { flow.intro() } }
        }
        .onChange(of: monitor.running) { isRunning in
            if isRunning { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { flow.intro() } }
        }
        .onReceive(poll.$now) { _ in
            monitor.poll()   // notices the moment Mouse Rate is turned on in System Settings
        }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text("Mouse Rate").font(.system(size: 21, weight: .heavy)).foregroundColor(.aptText)
                (Text("Compliments of ").foregroundColor(.aptMuted) + Text("Almost Perfect Tech").foregroundColor(.aptPale)
                 + Text("   ·   native \(AppConfig.version), built \(AppConfig.built)").foregroundColor(.aptDim))
                    .font(.ui(13, .medium))
            }
            Spacer()
            // same yellow Tip Jar pill as the website's top menu
            Button(action: {
                if let url = URL(string: AppConfig.coffeeURL) { NSWorkspace.shared.open(url) }
            }) {
                HStack(spacing: 7) {
                    JarShape()
                        .stroke(Color.coffeeInk, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .frame(width: 17, height: 17)
                    Text("Tip Jar").font(.ui(14, .semibold)).foregroundColor(.coffeeInk)
                }
                .padding(.leading, 12).padding(.trailing, 16).padding(.vertical, 9)
                .background(Capsule().fill(LinearGradient(colors: [.coffeeHi, .coffee], startPoint: .top, endPoint: .bottom)))
                .shadow(color: Color.coffee.opacity(0.45), radius: 10, y: 4)
            }
            .buttonStyle(PressStyle())
            .help("Leave a tip. Opens in your browser.")
            .padding(.trailing, 8)
            if monitor.running {
                SecondaryButton(title: "Test another mouse") { flow.resetAll() }
                    .help("Starts over and looks for mice again. Switch the new mouse on first.")
                    .padding(.trailing, 8)
            }
            Toggle(isOn: $flow.cheeky) {
                Text("Cheeky mode").font(.ui(14, .semibold)).foregroundColor(.aptText)
            }
            .toggleStyle(.switch)
            .tint(.aptOrange)
            HStack(spacing: 6) {
                Circle().fill(monitor.running ? Color.aptOk : Color.aptDim).frame(width: 7, height: 7)
                Text(monitor.running ? "Reading your mouse directly" : "Input Monitoring is off")
                    .font(.ui(13)).foregroundColor(.aptMuted)
            }
            .padding(.leading, 10)
        }
    }

    // MARK: numbered steps

    private var stepper: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases) { s in
                let on = flow.step == s, done = flow.finished.contains(s)
                Button(action: { flow.go(s) }) {
                    HStack(spacing: 8) {
                        if s != .report {
                            Text("\(s.rawValue + 1)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(done ? Color(red: 4 / 255, green: 21 / 255, blue: 13 / 255) : (on ? .aptInk : .aptSoft))
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(done ? Color.aptOk : (on ? Color.aptInk.opacity(0.18) : Color.white.opacity(0.07))))
                        }
                        Text(s.title).font(.ui(14, on ? .bold : .medium))
                            .foregroundColor(on ? .aptInk : .aptSoft)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Capsule().fill(on ? AnyShapeStyle(LinearGradient(colors: [.aptHi, .aptOrange], startPoint: .top, endPoint: .bottom))
                                                  : AnyShapeStyle(Color.clear)))
                }
                .buttonStyle(PressStyle())
                .disabled(s == .report && !flow.finished.contains(.report) && flow.clickSpeed == nil)
            }
        }
        .padding(5)
        .background(Capsule().fill(Color.white.opacity(0.03)))
        .overlay(Capsule().stroke(Color.aptLine, lineWidth: 1))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: flow.step)
    }

    // MARK: footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().background(Color.aptLine).padding(.bottom, 8)
            HStack(spacing: 18) {
                Link("Full mouse test website", destination: URL(string: AppConfig.siteURL)!)
                Link("Source code", destination: URL(string: AppConfig.repoURL)!)
                Link("YouTube", destination: URL(string: "https://www.youtube.com/@AlmostPerfectReviews")!)
                Link("Tip Jar", destination: URL(string: AppConfig.coffeeURL)!)
            }
            .font(.ui(13, .semibold))
            .foregroundColor(.aptPale)
            .tint(.aptPale)
            Text("Nothing is saved or sent. This app has no network code. Version \(AppConfig.version).")
                .font(.ui(12)).foregroundColor(.aptMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
