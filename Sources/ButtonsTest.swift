// ButtonsTest.swift
// Step 2. Every button, including back and forward, plus the scroll wheel and wheel skips.

import SwiftUI
import AppKit

enum MousePart: CaseIterable, Hashable {
    case left, right, middle, back, forward, up, down, tiltLeft, tiltRight
    var label: String {
        switch self {
        case .left: return "Left button"
        case .right: return "Right button"
        case .middle: return "Middle (wheel click)"
        case .back: return "Back (side)"
        case .forward: return "Forward (side)"
        case .up: return "Scroll up"
        case .down: return "Scroll down"
        case .tiltLeft: return "Tilt left"
        case .tiltRight: return "Tilt right"
        }
    }
    /// Must work before the step can finish. Middle and side buttons are checked if the mouse has them.
    static let main: [MousePart] = [.left, .right, .up, .down]
    static let buttons: [MousePart] = [.left, .right, .middle, .back, .forward, .up, .down]
}

struct ButtonsTest: View {
    @ObservedObject var flow: TestFlow

    @State private var worked: Set<MousePart> = []
    @State private var pressed: Set<MousePart> = []
    @State private var ups = 0
    @State private var downs = 0
    @State private var skips = 0
    @State private var lastDir: MousePart?
    @State private var lastScrollAt: TimeInterval = 0
    @State private var quip = ""
    @State private var finishedStep = false
    @State private var graceArmed = false
    @State private var touched = false
    // the playful bits: a slap that makes the mouse jiggle, a splash out of the pressed spot,
    // and the line for each button popping up right where it was hit
    @State private var slaps: CGFloat = 0
    @State private var slapDir: CGFloat = 1
    @State private var smack = ""
    @State private var smackID = 0
    @State private var smackTilt: Double = -6
    @State private var smackAt: CGPoint = .zero
    @StateObject private var splash = Splash()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Point at the box and press **every button** on your mouse once, side buttons too. Then roll the wheel **up and down** for a few seconds. Each part turns green when it works. Back and forward won't leave this window.")
                .font(.ui(16)).foregroundColor(.aptSoft).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 760, alignment: .leading)
            Quip(text: quip, size: 26).frame(minHeight: 32, alignment: .leading)
            TestBox(height: 430, active: !pressed.isEmpty, onEvent: handle) {
                HStack(spacing: 40) {
                    MouseDrawing(worked: worked, pressed: pressed)
                        .frame(width: 210, height: 330)
                        .modifier(SlapEffect(amount: slaps, dir: slapDir))
                        .overlay(alignment: .topLeading) {
                            // the line for each button pops up right where the mouse was hit
                            if !smack.isEmpty {
                                Text(smack)
                                    .font(.display(20)).foregroundColor(.aptPale)
                                    .multilineTextAlignment(.center)
                                    .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
                                    .shadow(color: Color.aptOrange.opacity(0.6), radius: 10, y: 3)
                                    .frame(width: 240)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .rotationEffect(.degrees(smackTilt))
                                    .position(x: smackAt.x, y: smackAt.y - 34)
                                    .id(smackID)
                                    .transition(.asymmetric(insertion: .scale(scale: 0.6).combined(with: .opacity),
                                                            removal: .opacity.combined(with: .offset(y: -22))))
                            }
                        }
                        .overlay(SplashLayer(splash: splash).frame(width: 610, height: 730))
                    VStack(spacing: 8) {
                        ForEach(MousePart.allCases, id: \.self) { part in partRow(part) }
                    }
                    .frame(width: 330)
                }
                .padding(28)
            }
            HStack(spacing: 10) {
                Stat(label: "Up steps", value: "\(ups)")
                Stat(label: "Down steps", value: "\(downs)")
                Stat(label: "Wrong-way steps", value: "\(skips)")
            }
            Text(skips > 2 ? "Some steps went the wrong way while you scrolled one way. That's usually wear or dust in the wheel." : "If you scroll one way and a step goes the other way, the wheel is skipping. That's usually wear or dust in the wheel.")
                .font(.ui(14)).foregroundColor(skips > 2 ? .aptBad : .aptMuted)
            SecondaryButton(title: "Start over") {
                worked = []; pressed = []; ups = 0; downs = 0; skips = 0; finishedStep = false; graceArmed = false
                quip = Copy.buttonsIntro(cheeky: flow.cheeky)
            }
        }
        .onAppear {
            quip = Copy.buttonsIntro(cheeky: flow.cheeky)
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) {
                if !touched && flow.cheeky && flow.step == .buttons { quip = Copy.pick(["Don't be shy. Press something.", "Any button. We're not picky.", "It won't bite. Promise."]) }
            }
        }
    }

    private func partRow(_ part: MousePart) -> some View {
        let ok = worked.contains(part), down = pressed.contains(part)
        let optional = part == .tiltLeft || part == .tiltRight
        return HStack(spacing: 10) {
            Circle().fill(ok ? Color.aptOk : (down ? Color.aptOrange : Color.aptDim)).frame(width: 9, height: 9)
            Text(part.label).font(.ui(14, .semibold)).foregroundColor(.aptText)
            Spacer()
            Text(ok ? "Works" : (optional ? "Optional" : "Not yet")).font(.ui(12, .medium))
                .foregroundColor(ok ? .aptOk : .aptMuted)
        }
        .padding(.vertical, 7).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(ok ? Color.aptOk.opacity(0.08) : Color.white.opacity(0.03)))
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: ok)
    }

    // MARK: events

    private func handle(_ e: NSEvent) {
        touched = true
        switch e.type {
        case .leftMouseDown: press(.left)
        case .rightMouseDown: press(.right)
        case .otherMouseDown:
            if let p = part(for: e.buttonNumber) { press(p) }
        case .leftMouseUp: release(.left)
        case .rightMouseUp: release(.right)
        case .otherMouseUp:
            if let p = part(for: e.buttonNumber) { release(p) }
        case .scrollWheel: scroll(e)
        default: break
        }
    }

    private func part(for button: Int) -> MousePart? {
        switch button { case 2: return .middle; case 3: return .back; case 4: return .forward; default: return nil }
    }

    private func press(_ p: MousePart) {
        let again = worked.contains(p)
        withAnimation(.easeOut(duration: 0.12)) { _ = pressed.insert(p) }
        mark(p)
        slap(p)
        if again { splashAt(p, count: 8) }
    }

    /// The jiggle: the mouse swings from the top so its back end wobbles, the way it would after a slap.
    private func slap(_ p: MousePart) {
        slapDir = p == .left ? -1 : (p == .right ? 1 : (Bool.random() ? 1 : -1))
        withAnimation(.linear(duration: 0.62)) { slaps += 1 }
    }

    /// Shows a button's line on the drawing, right above the spot that was hit.
    private func pop(_ p: MousePart, _ line: String) {
        guard !line.isEmpty else { return }
        smackAt = spot(p)
        smackTilt = Double.random(in: -4...4)
        smackID += 1
        let id = smackID
        withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { smack = line }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if smackID == id { withAnimation(.easeOut(duration: 0.3)) { smack = "" } }
        }
    }

    /// Where each part sits on the drawing (210 x 330), so the splash comes out of the right spot.
    private func spot(_ p: MousePart) -> CGPoint {
        let w: CGFloat = 210, h: CGFloat = 330
        switch p {
        case .left: return CGPoint(x: w * 0.27, y: h * 0.2)
        case .right: return CGPoint(x: w * 0.73, y: h * 0.2)
        case .middle, .up, .down: return CGPoint(x: w / 2, y: h * 0.2)
        case .forward: return CGPoint(x: 4, y: h * 0.43)
        case .back: return CGPoint(x: 4, y: h * 0.56)
        case .tiltLeft: return CGPoint(x: w / 2 - w * 0.16, y: h * 0.2)
        case .tiltRight: return CGPoint(x: w / 2 + w * 0.16, y: h * 0.2)
        }
    }

    private func splashAt(_ p: MousePart, count: Int) {
        let pt = spot(p)
        // the splash layer is 200 points bigger than the drawing on every side
        splash.burst(at: CGPoint(x: pt.x + 200, y: pt.y + 200), count: count)
    }

    private func release(_ p: MousePart) {
        withAnimation(.easeOut(duration: 0.2)) { _ = pressed.remove(p) }
    }

    private func scroll(_ e: NSEvent) {
        if e.momentumPhase != [] { return }   // ignore coasting after a trackpad or Magic Mouse swipe
        let sign: CGFloat = e.isDirectionInvertedFromDevice ? -1 : 1
        let dy = e.scrollingDeltaY * sign, dx = e.scrollingDeltaX * sign
        if abs(dy) >= abs(dx), dy != 0 {
            let dir: MousePart = dy > 0 ? .up : .down
            if dir == .up { ups += 1 } else { downs += 1 }
            // a lone step the other way, right after a step this way, is the wheel skipping
            if let last = lastDir, last != dir, e.timestamp - lastScrollAt < 0.08 { skips += 1 }
            lastDir = dir; lastScrollAt = e.timestamp
            flash(dir)
            if (dir == .up ? ups : downs) <= 1 || Int.random(in: 0..<4) == 0 { mark(dir) } else { _ = worked.insert(dir); checkDone() }
            if flow.cheeky && ups + downs == 60 { quip = "Okay, you really like scrolling." }
            if flow.cheeky && ups + downs == 160 { quip = "This is getting intimate. Maybe take a break." }
        } else if dx != 0 {
            let dir: MousePart = dx > 0 ? .tiltLeft : .tiltRight
            flash(dir); mark(dir)
        }
    }

    private func flash(_ p: MousePart) {
        withAnimation(.easeOut(duration: 0.1)) { _ = pressed.insert(p) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) { withAnimation(.easeOut(duration: 0.2)) { _ = pressed.remove(p) } }
    }

    private func mark(_ p: MousePart) {
        let first = !worked.contains(p)
        _ = worked.insert(p)
        if first { splashAt(p, count: 26) }
        let line = Copy.buttonLine(p, cheeky: flow.cheeky)
        if flow.cheeky || first { pop(p, line) }
        checkDone()
    }

    private func checkDone() {
        guard !finishedStep else { return }
        let all = MousePart.buttons.allSatisfy { worked.contains($0) }
        let main = MousePart.main.allSatisfy { worked.contains($0) }
        if all {
            splash.burst(at: CGPoint(x: 305, y: 330), count: 90, power: 1.3)
            finish()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { withAnimation { quip = Copy.buttonsAll(cheeky: flow.cheeky) } }
        } else if main && !graceArmed {
            graceArmed = true
            splash.burst(at: CGPoint(x: 305, y: 330), count: 50, power: 1.1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { quip = Copy.buttonsSide(cheeky: flow.cheeky) } }
            // no middle or side buttons? move on after a few seconds anyway
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { if !finishedStep { finish() } }
        }
    }

    private func finish() {
        guard !finishedStep else { return }
        finishedStep = true
        let got = MousePart.buttons.filter { worked.contains($0) }.count
        let main = MousePart.main.allSatisfy { worked.contains($0) }
        let r = ButtonsResult(worked: got, total: MousePart.buttons.count, mainOK: main)
        flow.buttons = r
        let summary = got == r.total ? "Every button works" : (main ? "Your main buttons work" : "\(got) of \(r.total) work")
        let q: String
        if !flow.cheeky { q = "" }
        else if got == r.total { q = Copy.pick(["Every single spot. You really know your way around.", "All of them. We need a cold shower."]) }
        else { q = Copy.pick(["We'll pretend you didn't skip the side ones.", "The side ones are shy. That's okay."]) }
        flow.complete(.buttons, summary: summary, quip: q)
    }
}

/// A simple top-down mouse. Each part lights orange while pressed and green once it works.
struct MouseDrawing: View {
    let worked: Set<MousePart>
    let pressed: Set<MousePart>

    private func fill(_ p: MousePart) -> Color {
        if pressed.contains(p) { return Color.aptOrange.opacity(0.85) }
        if worked.contains(p) { return Color.aptOk.opacity(0.35) }
        return Color.white.opacity(0.05)
    }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                // body
                RoundedRectangle(cornerRadius: w * 0.45, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: w * 0.45, style: .continuous).stroke(Color.aptLine2, lineWidth: 1))
                // left and right buttons
                HStack(spacing: 3) {
                    UnevenTop(left: true).fill(fill(.left))
                    UnevenTop(left: false).fill(fill(.right))
                }
                .frame(width: w - 10, height: h * 0.4)
                .position(x: w / 2, y: h * 0.2 + 5)
                // wheel
                Capsule().fill(pressed.contains(.middle) || pressed.contains(.up) || pressed.contains(.down) ? Color.aptOrange :
                                (worked.contains(.middle) ? Color.aptOk.opacity(0.6) : Color(white: 0.3)))
                    .frame(width: w * 0.11, height: h * 0.16)
                    .position(x: w / 2, y: h * 0.2)
                // side buttons on the left edge
                Capsule().fill(fill(.forward)).frame(width: 10, height: h * 0.1).position(x: 4, y: h * 0.43)
                Capsule().fill(fill(.back)).frame(width: 10, height: h * 0.1).position(x: 4, y: h * 0.56)
                // tilt arrows
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
                    .foregroundColor(pressed.contains(.tiltLeft) ? .aptOrange : (worked.contains(.tiltLeft) ? .aptOk : .aptDim))
                    .position(x: w / 2 - w * 0.16, y: h * 0.2)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                    .foregroundColor(pressed.contains(.tiltRight) ? .aptOrange : (worked.contains(.tiltRight) ? .aptOk : .aptDim))
                    .position(x: w / 2 + w * 0.16, y: h * 0.2)
            }
            .scaleEffect(pressed.isEmpty ? 1 : 0.985)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pressed)
        }
    }
}

/// One top button of the mouse: rounded on the outer top corner.
struct UnevenTop: Shape {
    let left: Bool
    func path(in r: CGRect) -> Path {
        let big = min(r.width, r.height) * 0.9, small: CGFloat = 4
        var p = Path()
        let tl = left ? big : small, tr = left ? small : big
        p.move(to: CGPoint(x: r.minX + tl, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + tr), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + tl))
        p.addQuadCurve(to: CGPoint(x: r.minX + tl, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - slap and splash

/// Swings the view from near its top edge with a quick squash and stretch that dies out.
/// `amount` goes up by 1 for every slap, and each whole step plays one jiggle.
struct SlapEffect: GeometryEffect {
    var amount: CGFloat
    var dir: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        let t = amount - floor(amount)
        guard t > 0 else { return ProjectionTransform(CGAffineTransform.identity) }
        let decay = 1 - t
        let wobble = sin(t * .pi * 5) * decay
        let angle = wobble * 0.12 * dir          // about 7 degrees at the start
        let sx = 1 + wobble * 0.05, sy = 1 - wobble * 0.06
        let pivot = CGPoint(x: size.width / 2, y: size.height * 0.1)
        var tr = CGAffineTransform(translationX: pivot.x, y: pivot.y)
        tr = tr.rotated(by: angle).scaledBy(x: sx, y: sy)
        tr = tr.translatedBy(x: -pivot.x, y: -pivot.y)
        return ProjectionTransform(tr)
    }
}

/// Little orange particles that burst out and fall, like the website's splash.
final class Splash: ObservableObject {
    struct Particle {
        let origin: CGPoint
        let velocity: CGVector
        let born: Date
        let radius: CGFloat
        let tone: Int
    }
    @Published var particles: [Particle] = []

    func burst(at origin: CGPoint, count: Int, power: CGFloat = 1) {
        let now = Date()
        for _ in 0..<count {
            let a = Double.random(in: 0..<(2 * .pi))
            let speed = CGFloat.random(in: 110...400) * power
            particles.append(Particle(origin: origin,
                                      velocity: CGVector(dx: CGFloat(cos(a)) * speed, dy: CGFloat(sin(a)) * speed - 170 * power),
                                      born: now, radius: .random(in: 1.5...4), tone: Int.random(in: 0..<5)))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            let cutoff = Date().addingTimeInterval(-1.0)
            self?.particles.removeAll { $0.born < cutoff }
        }
    }
}

struct SplashLayer: View {
    @ObservedObject var splash: Splash
    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: splash.particles.isEmpty)) { timeline in
            Canvas { ctx, _ in
                let now = timeline.date
                for p in splash.particles {
                    let t = CGFloat(now.timeIntervalSince(p.born))
                    if t < 0 || t > 1 { continue }
                    let x = p.origin.x + p.velocity.dx * t
                    let y = p.origin.y + p.velocity.dy * t + 0.5 * 950 * t * t
                    let color: Color = p.tone == 0 ? Color(red: 1, green: 0.95, blue: 0.89) : (p.tone < 3 ? .aptOrange : .aptHi)
                    ctx.opacity = Double(1 - t)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - p.radius, y: y - p.radius, width: p.radius * 2, height: p.radius * 2)),
                             with: .color(color))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
