// TestFlow.swift
// The guided four-step run: which step is showing, each step's result, and the step cards
// that pop up between steps and move the person along on their own.

import SwiftUI

enum Step: Int, CaseIterable, Identifiable {
    case polling, buttons, doubleClick, clickSpeed, report
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .polling: return "Polling rate"
        case .buttons: return "Buttons and scroll"
        case .doubleClick: return "Double-click"
        case .clickSpeed: return "Click speed"
        case .report: return "Report"
        }
    }
    static let tests: [Step] = [.polling, .buttons, .doubleClick, .clickSpeed]
}

struct PollResult { let avg: Int; let peak: Int; let steady: Double; let device: String; var connection: String = ""
    var snapped: Int? { standardRate(for: avg) }
    var label: String { snapped.map { "\($0)Hz" } ?? "\(avg)Hz" }
}
struct ButtonsResult { let worked: Int; let total: Int; let mainOK: Bool }
struct DoubleClickResult { let clicks: Int; let phantom: Int; let closestMs: Int? }
struct ClickSpeedResult { let clicks: Int; let seconds: Int; var score: Double { Double(clicks) / Double(seconds) } }

struct MouseGrade {
    enum Tone { case great, okay, poor }
    let letter: String
    let title: String
    let detail: String
    let tone: Tone
}

struct StepCard: Identifiable {
    let id = UUID()
    let kicker: String
    let title: String
    let text: String
    let quip: String
    let done: Bool
    let current: Step?
    let hold: Double
    var onShow: (() -> Void)? = nil
}

final class TestFlow: ObservableObject {
    @Published var step: Step = .polling
    @Published var cheeky = true
    @Published var finished: Set<Step> = []
    @Published var poll: PollResult?
    @Published var buttons: ButtonsResult?
    @Published var doubleClick: DoubleClickResult?
    @Published var clickSpeed: ClickSpeedResult?
    @Published var card: StepCard?
    @Published var runID = 0
    @Published var mouseName = ""

    /// Set by the window: forgets every mouse and finds them again, so a new mouse can be tested.
    var restartMonitor: (() -> Void)?

    private var queue: [StepCard] = []
    private var afterCards: (() -> Void)?
    private var work: DispatchWorkItem?
    private var introShown = false

    // MARK: cards

    func intro() {
        guard !introShown else { return }
        introShown = true
        var c = stepCard(.polling)
        c = StepCard(kicker: "4 quick tests · about 2 minutes", title: cheeky ? c.title : "Step 1: Polling rate", text: c.text,
                     quip: c.quip, done: false, current: .polling, hold: 4.6, onShow: c.onShow)
        run([c])
    }

    func stepCard(_ s: Step) -> StepCard {
        let t = Copy.stepIntro(s, cheeky: cheeky)
        let kicker = cheeky ? "Step \(s.rawValue + 1) of 4 · \(s.title)" : "Step \(s.rawValue + 1) of 4"
        return StepCard(kicker: kicker, title: t.title, text: t.text, quip: t.quip, done: false, current: s,
                        hold: cheeky ? 4.2 : 3.6, onShow: { [weak self] in self?.go(s) })
    }

    /// Call when a test is complete. Shows the result card, then the next step (or the report).
    func complete(_ s: Step, summary: String, quip: String) {
        finished.insert(s)
        if step == .report || finished.contains(.report) { return }
        let next = Step.tests.first(where: { $0.rawValue > s.rawValue && !finished.contains($0) })
            ?? Step.tests.first(where: { !finished.contains($0) })
        let doneCard = StepCard(kicker: "Step \(s.rawValue + 1) of 4 done", title: summary, text: "", quip: quip,
                                done: true, current: nil, hold: cheeky ? 3.0 : 2.2)
        DispatchQueue.main.asyncAfter(deadline: .now() + (s == .polling ? 1.2 : 0.7)) { [weak self] in
            guard let self = self else { return }
            if let n = next {
                self.run([doneCard, self.stepCard(n)])
            } else {
                let f = Copy.finalCard(cheeky: self.cheeky)
                let final = StepCard(kicker: "All 4 steps done", title: f.title, text: f.text, quip: f.quip,
                                     done: false, current: nil, hold: 3.2)
                self.run([doneCard, final]) { [weak self] in self?.finishAll() }
            }
        }
    }

    func finishAll() {
        finished.insert(.report)
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { step = .report }
    }

    func run(_ cards: [StepCard], then: (() -> Void)? = nil) {
        work?.cancel()
        queue = cards
        afterCards = then
        advance()
    }

    private func advance() {
        guard !queue.isEmpty else {
            withAnimation(.easeOut(duration: 0.35)) { card = nil }
            let after = afterCards; afterCards = nil; after?()
            return
        }
        let c = queue.removeFirst()
        c.onShow?()
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { card = c }
        let w = DispatchWorkItem { [weak self] in self?.advance() }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + c.hold, execute: w)
    }

    /// Click anywhere on a card: jump straight to where the cards were heading.
    func skip() {
        work?.cancel()
        for c in queue { c.onShow?() }
        queue = []
        advance()
    }

    func go(_ s: Step) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { step = s }
    }

    func resetAll() {
        work?.cancel(); queue = []; card = nil
        restartMonitor?()
        finished = []; poll = nil; buttons = nil; doubleClick = nil; clickSpeed = nil
        mouseName = ""   // the next run may be a different mouse
        runID += 1
        introShown = false
        step = .polling
        intro()
    }

    // MARK: overall grade

    /// One plain answer to "is this a good mouse?". Polling rate sets the grade. A phantom
    /// double-click or a main button that never registered drops it one letter each.
    /// Click speed is left out on purpose: it measures the person, not the mouse.
    func grade() -> MouseGrade? {
        guard let p = poll else { return nil }
        let hz = p.snapped ?? p.avg
        var step: Int
        if hz >= 2000 { step = 0 }
        else if hz >= 900 { step = 1 }
        else if hz >= 450 { step = 2 }
        else if hz >= 200 { step = 3 }
        else if hz >= 110 { step = 4 }
        else { step = 5 }
        var notes: [String] = []
        if let d = doubleClick, d.phantom > 0 {
            step += 1
            notes.append("It also double-clicked on its own, which usually means a worn switch.")
        }
        if let b = buttons, !b.mainOK {
            step += 1
            notes.append("Some of the main buttons never registered.")
        }
        step = min(step, 5)

        let letters = ["A+", "A", "B", "C", "D", "F"]
        let plainLines = ["As fast as mice get.", "Great mouse. No need to upgrade.", "Good mouse. A 1000Hz mouse would still be smoother.",
                     "It's okay. You can do better.", "You can do better.", "Time for a new mouse."]
        let cheekyLines = ["Overkill. We love it.", "Great mouse. Keep this one.", "Pretty good. Not quite great.",
                      "It's fine. You can do better.", "You can do better. Much better.", "Oof. Time for a new mouse."]

        let ms = 1000.0 / Double(max(hz, 1))
        let msText = ms >= 0.95 ? String(format: "%.0f", ms) : String(format: "%.2g", ms)
        var detail = "\(hz)Hz means your Mac gets a new position every \(msText) ms."
        if hz < 450 {
            detail += " A 1000Hz mouse updates \(Int((1000.0 / Double(max(hz, 1))).rounded())) times as often."
        }
        if !notes.isEmpty { detail += " " + notes.joined(separator: " ") }
        let tone: MouseGrade.Tone = step <= 1 ? .great : step <= 3 ? .okay : .poor
        return MouseGrade(letter: letters[step], title: self.cheeky ? cheekyLines[step] : plainLines[step], detail: detail, tone: tone)
    }

    // MARK: sharing

    /// The leaderboard on the website, with this run's results after the # as base64url JSON. The browser keeps the
    /// part after the # to itself. Nothing is shared until the person presses Share on the page, and the mouse's
    /// name only goes along if they tick the box there.
    func leaderboardURL() -> URL? {
        guard let p = poll else { return URL(string: AppConfig.siteURL + "/#board") }
        var d: [String: Any] = ["v": 1, "src": "app", "app": AppConfig.version, "hz": p.snapped ?? p.avg,
                                "mouse": mouseName.trimmingCharacters(in: .whitespaces)]
        if let b = buttons { d["btn"] = ["got": b.worked, "of": b.total, "core": b.mainOK] as [String: Any] }
        if let dc = doubleClick { d["dc"] = ["phantom": dc.phantom, "clicks": dc.clicks] }
        if let c = clickSpeed { d["cps"] = (c.score * 10).rounded() / 10 }
        guard let data = try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys]) else { return nil }
        let b64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(string: AppConfig.siteURL + "/#post=" + b64)
    }

    func commentLine() -> String {
        var parts: [String] = []
        if let g = grade() { parts.append("grade \(g.letter)") }
        if let p = poll { parts.append("\(p.label) polling") }
        if let b = buttons { parts.append(b.worked == b.total ? "every button works" : b.mainOK ? "main buttons work" : "\(b.worked) of \(b.total) buttons work") }
        if let d = doubleClick { parts.append(d.phantom == 0 ? "0 phantom clicks" : "\(d.phantom) phantom clicks") }
        if let c = clickSpeed { parts.append(String(format: "%.1f clicks per second", c.score)) }
        let name = mouseName.trimmingCharacters(in: .whitespaces)
        return (name.isEmpty ? "My mouse" : name) + ": " + (parts.isEmpty ? "not tested yet" : parts.joined(separator: ", ")) + "."
    }
}
