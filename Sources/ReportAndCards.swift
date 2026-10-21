// ReportAndCards.swift
// The final report, and the step cards that pop up between steps.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Report

struct ReportView: View {
    @ObservedObject var flow: TestFlow
    @State private var copied = false
    @State private var savedNote = ""
    @State private var shownTiles = false
    @State private var quip = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(subtitle).font(.ui(15, .semibold)).foregroundColor(.aptHi)
                    Text(mouseTitle).font(.display(52)).foregroundColor(.aptText)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(flow.cheeky ? "All four tests, in one place. No judgment. Well, a little." : "All four tests, in one place.")
                        .font(.ui(16)).foregroundColor(.aptSoft)
                }
                Spacer()
                Quip(text: quip, size: 24)
            }
            gradeCard
            HStack(spacing: 12) {
                tile(0, "Polling rate", pollValue, pollNote, pollTone)
                tile(1, "Buttons and scroll", btnValue, btnNote, btnTone)
                tile(2, "Double-click", dcValue, dcNote, dcTone)
                tile(3, "Click speed", cpsValue, cpsNote, cpsTone)
            }
            TextField("Mouse name (shows on the report)", text: $flow.mouseName)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 380)
            HStack(spacing: 12) {
                PrimaryButton(title: copied ? "Copied. Opening YouTube..." : "Copy and paste in the YouTube comments") {
                    copyToClipboard(flow.commentLine())
                    copied = true
                    // a short pause so the "Copied" is seen, then the video opens in the browser
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        if let url = URL(string: AppConfig.videoURL) { NSWorkspace.shared.open(url) }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6) { copied = false }
                }
                SecondaryButton(title: "Save as image") { saveImage() }
                    .help("Saves the report as a picture you can post. It has the site link on it.")
                SecondaryButton(title: "Test another mouse") { flow.resetAll() }
            }
            if copied {
                Text(flow.cheeky ? "Copied. Press Command-V in the YouTube comments and show off." : "Copied. Press Command-V in the YouTube comments to paste it.")
                    .font(.ui(14)).foregroundColor(.aptOk)
            }
            if !savedNote.isEmpty {
                Text(savedNote).font(.ui(14)).foregroundColor(.aptOk)
            }
            Group {
                leaderboardCard.padding(.top, 8)
                coffeeCard
            }
            videoCard
        }
        .onAppear {
            quip = flow.cheeky ? Copy.pick(["That's the full workout. Need a towel?", "Four tests. Zero shame.", "You and your mouse should get a room.", "Same time next week?"]) : ""
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.1)) { shownTiles = true }
        }
    }

    private var cleanName: String { flow.mouseName.trimmingCharacters(in: .whitespaces) }
    private var mouseTitle: String { cleanName.isEmpty ? "Your mouse report" : cleanName }
    private var subtitle: String {
        guard !cleanName.isEmpty else { return "Mouse report" }
        if let c = flow.poll?.connection, !c.isEmpty { return "Mouse report · \(c)" }
        return "Mouse report"
    }

    // MARK: overall grade

    @ViewBuilder private var gradeCard: some View {
        let g = flow.grade()
        let color: Color = g == nil ? .aptDim : g!.tone == .great ? .aptOk : g!.tone == .okay ? .aptHi : .aptBad
        HStack(alignment: .center, spacing: 30) {
            Text(g?.letter ?? "?")
                .font(.system(size: 120, weight: .black, design: .rounded))
                .foregroundColor(color)
                .frame(minWidth: 170)
                .shadow(color: color.opacity(0.35), radius: 24)
            VStack(alignment: .leading, spacing: 8) {
                Text("Overall grade").font(.ui(14, .semibold)).foregroundColor(.aptSoft)
                Text(g?.title ?? "Run the polling test to get a grade.")
                    .font(.display(36)).foregroundColor(.aptText)
                    .fixedSize(horizontal: false, vertical: true)
                if let g = g {
                    Text(g.detail).font(.ui(16)).foregroundColor(.aptSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Graded on polling rate, buttons and double-clicks. Click speed is about you, not the mouse.")
                    .font(.ui(12)).foregroundColor(.aptMuted)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28).padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.white.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(color.opacity(0.45), lineWidth: 1))
        .opacity(shownTiles ? 1 : 0)
        .scaleEffect(shownTiles ? 1 : 0.97)
        .animation(.spring(response: 0.7, dampingFraction: 0.8), value: shownTiles)
    }

    // MARK: save as image

    /// Renders the report as a 1080 x 1350 picture (same layout as the website's "Save as image") and asks where to save it.
    @MainActor private func saveImage() {
        let g = flow.grade()
        let gradeColor: Color = g == nil ? .aptDim : g!.tone == .great ? .aptOk : g!.tone == .okay ? .aptHi : .aptBad
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM d, yyyy"
        let card = ReportShareCard(
            name: cleanName.isEmpty ? "My mouse" : cleanName,
            kicker: subtitle,
            date: fmt.string(from: Date()),
            letter: g?.letter ?? "?",
            gradeTitle: g?.title ?? "Run the polling test to get a grade.",
            gradeDetail: g?.detail ?? "",
            gradeColor: gradeColor,
            tiles: [
                ShareTile(label: "Polling rate", value: pollValue, note: pollNote, color: toneColor(pollTone)),
                ShareTile(label: "Buttons and scroll", value: btnValue, note: btnNote, color: toneColor(btnTone)),
                ShareTile(label: "Double-click", value: dcValue, note: dcNote, color: toneColor(dcTone)),
                ShareTile(label: "Click speed", value: cpsValue, note: cpsNote, color: toneColor(cpsTone))
            ])
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 1350)
        guard let cg = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            savedNote = "Couldn't make the picture. A screenshot works too."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.png]
        panel.canCreateDirectories = true
        let safeName = cleanName.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|")).joined()
        panel.nameFieldStringValue = safeName.isEmpty ? "Mouse report.png" : "Mouse report - \(safeName).png"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url)
            let folder = url.deletingLastPathComponent().lastPathComponent
            savedNote = flow.cheeky ? "Saved to \(folder). Go on, post it." : "Saved to \(folder)."
        } catch {
            savedNote = "Couldn't save the picture there. Try another folder."
        }
    }

    private func toneColor(_ t: Tone) -> Color {
        switch t {
        case .good: return .aptHi
        case .bad: return .aptBad
        case .skip: return .aptDim
        case .plain: return .aptText
        }
    }

    // MARK: tip jar

    private var coffeeCard: some View {
        HStack(spacing: 22) {
            JarShape()
                .stroke(Color.coffeeInk, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .frame(width: 34, height: 34)
                .frame(width: 66, height: 66)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.coffee))
                .shadow(color: Color.coffee.opacity(0.5), radius: 14, y: 6)
            VStack(alignment: .leading, spacing: 6) {
                Text("Was this useful?").font(.display(26)).foregroundColor(.aptText)
                Text(flow.cheeky
                     ? "Your mouse just got graded. If you enjoyed the show, drop something in the tip jar. $1, $3, $5, $10 or whatever feels right."
                     : "If it helped, you can leave a little something in the tip jar. $1, $3, $5, $10 or any amount you like. It keeps this free, with no ads.")
                    .font(.ui(16)).foregroundColor(.aptSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button(action: {
                if let url = URL(string: AppConfig.coffeeURL) { NSWorkspace.shared.open(url) }
            }) {
                Text("Tip Jar")
                    .font(.ui(16, .bold))
                    .foregroundColor(.coffeeInk)
                    .padding(.horizontal, 24).padding(.vertical, 14)
                    .background(Capsule().fill(LinearGradient(colors: [.coffeeHi, .coffee], startPoint: .top, endPoint: .bottom)))
                    .shadow(color: Color.coffee.opacity(0.45), radius: 14, y: 6)
            }
            .buttonStyle(PressStyle())
        }
        .padding(.horizontal, 28).padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(LinearGradient(colors: [Color.coffee.opacity(0.16), Color.coffee.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.coffee.opacity(0.5), lineWidth: 1))
        .shadow(color: Color.coffee.opacity(0.18), radius: 30, y: 14)
    }

    // MARK: the video

    private var videoCard: some View {
        HStack(spacing: 22) {
            Image(systemName: "play.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.aptInk)
                .offset(x: 2)
                .frame(width: 66, height: 66)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.aptOrange))
                .shadow(color: Color.aptOrange.opacity(0.5), radius: 14, y: 6)
            VStack(alignment: .leading, spacing: 6) {
                Text("Watch the ultimate mouse guide for Mac").font(.display(26)).foregroundColor(.aptText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(flow.cheeky
                     ? "Now find out which mouse your Mac actually deserves, and which one to skip."
                     : "The video this test was made for: which mouse to get for your Mac, and which one to skip.")
                    .font(.ui(16)).foregroundColor(.aptSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button(action: {
                if let url = URL(string: AppConfig.videoURL) { NSWorkspace.shared.open(url) }
            }) {
                Text("Watch the video")
                    .font(.ui(16, .bold))
                    .foregroundColor(.aptInk)
                    .padding(.horizontal, 24).padding(.vertical, 14)
                    .background(Capsule().fill(LinearGradient(colors: [.aptHi, .aptOrange], startPoint: .top, endPoint: .bottom)))
                    .shadow(color: Color.aptOrange.opacity(0.45), radius: 14, y: 6)
            }
            .buttonStyle(PressStyle())
            .help("Opens the Almost Perfect mouse video on YouTube.")
        }
        .padding(.horizontal, 28).padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(LinearGradient(colors: [Color.aptOrange.opacity(0.16), Color.aptOrange.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.aptOrange.opacity(0.5), lineWidth: 1))
        .shadow(color: Color.aptOrange.opacity(0.18), radius: 30, y: 14)
    }

    // MARK: leaderboard

    /// Sharing is optional, and Mouse Rate has no network code, so it happens on the website. This opens the
    /// leaderboard in the browser with the results after the # in the address (that part never goes to a server
    /// by itself). The person picks a nickname or gets a made-up one, chooses whether to show the mouse's name,
    /// and presses Share there.
    private var leaderboardCard: some View {
        HStack(spacing: 22) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.aptHi)
                .frame(width: 66, height: 66)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.aptCardHi))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.aptOrange.opacity(0.45), lineWidth: 1))
                .shadow(color: Color.aptOrange.opacity(0.3), radius: 14, y: 6)
            VStack(alignment: .leading, spacing: 6) {
                Text(flow.cheeky ? "Want to brag on the leaderboard?" : "Share your results on the leaderboard?")
                    .font(.display(26)).foregroundColor(.aptText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(leaderboardText)
                    .font(.ui(16)).foregroundColor(.aptSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            SecondaryButton(title: "Share on the leaderboard") {
                if let url = flow.leaderboardURL() { NSWorkspace.shared.open(url) }
            }
            .disabled(flow.poll == nil)
            .opacity(flow.poll == nil ? 0.5 : 1)
            .help("Opens the leaderboard in your browser with your results filled in. Nothing is shared until you press Share there.")
        }
        .padding(.horizontal, 28).padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.015)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.aptLine2, lineWidth: 1))
    }

    private var leaderboardText: String {
        if flow.poll == nil { return "Run step 1 first. The leaderboard needs your polling rate." }
        return flow.cheeky
            ? "It's up to you. This opens the leaderboard in your browser. Pick a nickname, or we'll make one up. Nothing is shared until you press Share there."
            : "It's up to you. This opens the leaderboard in your browser, where you can add a nickname or get a made-up one. Nothing is shared until you press Share there, and your mouse's name only if you tick the box."
    }

    private enum Tone { case good, bad, plain, skip }

    private func tile(_ i: Int, _ label: String, _ value: String, _ note: String, _ tone: Tone) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.ui(14, .medium)).foregroundColor(.aptSoft)
            Text(value).font(.display(30)).lineLimit(2).minimumScaleFactor(0.7)
                .foregroundColor(tone == .good ? .aptHi : tone == .bad ? .aptBad : tone == .skip ? .aptDim : .aptText)
            Text(note).font(.ui(13)).foregroundColor(.aptMuted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.aptLine, lineWidth: 1))
        .opacity(shownTiles ? 1 : 0)
        .offset(y: shownTiles ? 0 : 18)
        .animation(.spring(response: 0.7, dampingFraction: 0.8).delay(Double(i) * 0.08), value: shownTiles)
    }

    private var pollValue: String { flow.poll?.label ?? "Not tested" }
    private var pollNote: String {
        guard let p = flow.poll else { return "Run step 1 to fill this in." }
        let hz = p.snapped ?? p.avg
        return hz >= 700 ? "Gaming-grade. One update every millisecond or so." : hz >= 200 ? "Middle of the pack." : "Office mouse territory."
    }
    private var pollTone: Tone { guard let p = flow.poll else { return .skip }; return (p.snapped ?? p.avg) >= 700 ? .good : .plain }

    private var btnValue: String {
        guard let b = flow.buttons else { return "Not tested" }
        return b.worked == b.total ? "All work" : b.mainOK ? "Main ones work" : "\(b.worked) of \(b.total)"
    }
    private var btnNote: String {
        guard let b = flow.buttons else { return "Press every button once to fill this in." }
        return b.worked == b.total ? "Every button and the wheel checked out." : b.mainOK ? "Left, right and the wheel are fine. Middle or side buttons weren't pressed." : "Some buttons never registered."
    }
    private var btnTone: Tone { guard let b = flow.buttons else { return .skip }; return b.mainOK ? .good : .bad }

    private var dcValue: String {
        guard let d = flow.doubleClick else { return "Not tested" }
        return d.phantom == 0 ? "No phantoms" : "\(d.phantom) phantom"
    }
    private var dcNote: String {
        guard let d = flow.doubleClick else { return "Click slowly 20 times to fill this in." }
        return d.phantom == 0 ? "\(d.clicks) clicks, each counted once." : "Your switch may be wearing out."
    }
    private var dcTone: Tone { guard let d = flow.doubleClick else { return .skip }; return d.phantom == 0 ? .good : .bad }

    private var cpsValue: String { flow.clickSpeed.map { String(format: "%.1f / sec", $0.score) } ?? "Not tested" }
    private var cpsNote: String { flow.clickSpeed.map { Copy.cpsNote($0.score) } ?? "Click as fast as you can for 5 seconds." }
    private var cpsTone: Tone { flow.clickSpeed == nil ? .skip : .good }
}

// MARK: - Share picture

/// One result box on the saved picture.
struct ShareTile {
    let label: String
    let value: String
    let note: String
    let color: Color
}

/// The report as a picture, 1080 points wide and at least 1350 tall (the 4:5 size Reddit, X and phones show well).
struct ReportShareCard: View {
    let name: String
    let kicker: String
    let date: String
    let letter: String
    let gradeTitle: String
    let gradeDetail: String
    let gradeColor: Color
    let tiles: [ShareTile]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                Text("Almost Perfect Tech").font(.ui(27, .semibold)).foregroundColor(.aptPale)
                Spacer()
                Text(kicker).font(.ui(24, .medium)).foregroundColor(.aptMuted)
            }
            Text(name)
                .font(.display(88)).foregroundColor(.aptText)
                .lineLimit(2).minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 64)
            Text("Tested \(date)").font(.ui(25)).foregroundColor(.aptMuted).padding(.top, 14)
            gradeBox.padding(.top, 44)
            VStack(spacing: 24) {
                HStack(spacing: 24) { tileView(tiles[0]); tileView(tiles[1]) }
                HStack(spacing: 24) { tileView(tiles[2]); tileView(tiles[3]) }
            }
            .padding(.top, 26)
            Spacer(minLength: 56)
            HStack(spacing: 22) {
                Text("Test yours free").font(.ui(24, .bold)).foregroundColor(.aptInk)
                    .padding(.horizontal, 22).padding(.vertical, 14)
                    .background(Capsule().fill(LinearGradient(colors: [.aptHi, .aptOrange], startPoint: .top, endPoint: .bottom)))
                Text("mouse.almostperfecttech.com").font(.system(size: 27, weight: .medium, design: .monospaced)).foregroundColor(.aptText)
                Spacer()
                Text("No ads. No sign-up.").font(.ui(22)).foregroundColor(.aptMuted)
            }
        }
        .padding(.horizontal, 72).padding(.top, 66).padding(.bottom, 46)
        .frame(width: 1080)
        .frame(minHeight: 1350, alignment: .top)
        .background(backdrop)
    }

    private var gradeBox: some View {
        HStack(alignment: .center, spacing: 30) {
            Text(letter)
                .font(.system(size: letter.count > 1 ? 180 : 220, weight: .black, design: .rounded))
                .foregroundColor(gradeColor)
                .shadow(color: gradeColor.opacity(0.55), radius: 40)
                .frame(width: 250)
            VStack(alignment: .leading, spacing: 12) {
                Text("Overall grade").font(.ui(24, .semibold)).foregroundColor(.aptSoft)
                Text(gradeTitle).font(.display(42)).foregroundColor(.aptText)
                    .fixedSize(horizontal: false, vertical: true)
                if !gradeDetail.isEmpty {
                    Text(gradeDetail).font(.ui(25)).foregroundColor(.aptSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 30).padding(.vertical, 40)
        .frame(maxWidth: .infinity, minHeight: 340, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 40, style: .continuous).fill(Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 40, style: .continuous).stroke(gradeColor.opacity(0.6), lineWidth: 2))
    }

    private func tileView(_ t: ShareTile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t.label).font(.ui(23, .medium)).foregroundColor(.aptSoft)
            Text(t.value).font(.display(44)).foregroundColor(t.color)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(t.note).font(.ui(21)).foregroundColor(.aptMuted)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 196, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1.5))
    }

    private var backdrop: some View {
        ZStack {
            Color(red: 11 / 255, green: 11 / 255, blue: 12 / 255)
            RadialGradient(colors: [Color.aptOrange.opacity(0.30), .clear], center: .topLeading, startRadius: 0, endRadius: 760)
            RadialGradient(colors: [Color.aptOrange.opacity(0.22), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 700)
            ShareDots(spacing: 26, radius: 1.1).fill(Color.white.opacity(0.05))
        }
    }
}

/// The faint dot grid behind the saved picture.
struct ShareDots: Shape {
    var spacing: CGFloat
    var radius: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        var y = r.minY + 24
        while y < r.maxY {
            var x = r.minX + 24
            while x < r.maxX {
                p.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                x += spacing
            }
            y += spacing
        }
        return p
    }
}

// MARK: - Step cards

struct StepCardView: View {
    let card: StepCard
    @ObservedObject var flow: TestFlow
    @State private var fill: CGFloat = 0
    @State private var drawn: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    ForEach(Step.tests) { s in
                        Capsule()
                            .fill(flow.finished.contains(s) ? Color.aptOk : (card.current == s ? Color.aptOrange : Color.white.opacity(0.1)))
                            .frame(width: card.current == s ? 54 : 34, height: 6)
                    }
                }
                .padding(.bottom, 6)
                Text(card.kicker).font(.ui(15, .semibold)).foregroundColor(.aptHi)
                if card.done {
                    ZStack {
                        Circle().trim(from: 0, to: drawn).stroke(Color.aptOk, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        CheckShape().trim(from: 0, to: drawn).stroke(Color.aptOk, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                            .frame(width: 26, height: 20)
                    }
                    .frame(width: 60, height: 60)
                    .padding(.vertical, 4)
                }
                Text(card.title).font(.display(42)).foregroundColor(.aptText).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !card.text.isEmpty {
                    Text(card.text).font(.ui(17)).foregroundColor(.aptSoft).multilineTextAlignment(.center)
                        .frame(maxWidth: 440).fixedSize(horizontal: false, vertical: true)
                }
                if !card.quip.isEmpty {
                    Text(card.quip).font(.ui(17, .bold)).foregroundColor(.aptHi).multilineTextAlignment(.center)
                }
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(Color.aptOrange).frame(width: 260 * fill)
                }
                .frame(width: 260, height: 4)
                .padding(.top, 10)
                Text(flow.cheeky ? "Can't wait? Click anywhere." : "Click anywhere to skip").font(.ui(13)).foregroundColor(.aptMuted)
            }
            .padding(.horizontal, 40).padding(.top, 36).padding(.bottom, 26)
            .frame(width: 560)
            .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(Color(red: 18 / 255, green: 18 / 255, blue: 22 / 255)))
            .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(Color.aptOrange.opacity(0.4), lineWidth: 1))
            .shadow(color: .black.opacity(0.8), radius: 50, y: 30)
        }
        .contentShape(Rectangle())
        .onTapGesture { flow.skip() }
        .onAppear {
            fill = 0; drawn = 0
            withAnimation(.linear(duration: card.hold)) { fill = 1 }
            withAnimation(.easeOut(duration: 0.8).delay(0.15)) { drawn = 1 }
        }
    }
}

struct CheckShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.36, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

/// A simple tip jar: lid, coin slot, jar body and a coin inside. Drawn on a 32 x 32 grid.
struct JarShape: Shape {
    func path(in r: CGRect) -> Path {
        let s = min(r.width, r.height) / 32
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * s, y: r.minY + y * s) }
        var p = Path()
        // lid and coin slot
        p.addRoundedRect(in: CGRect(origin: pt(11, 4.5), size: CGSize(width: 10 * s, height: 4 * s)), cornerSize: CGSize(width: 1 * s, height: 1 * s))
        p.move(to: pt(14.5, 6.5)); p.addLine(to: pt(17.5, 6.5))
        // body
        p.move(to: pt(10, 8.5))
        p.addLine(to: pt(22, 8.5))
        p.addLine(to: pt(22, 11))
        p.addQuadCurve(to: pt(24.5, 15.3), control: pt(24.5, 12.4))
        p.addLine(to: pt(24.5, 25))
        p.addQuadCurve(to: pt(21.5, 28), control: pt(24.5, 28))
        p.addLine(to: pt(10.5, 28))
        p.addQuadCurve(to: pt(7.5, 25), control: pt(7.5, 28))
        p.addLine(to: pt(7.5, 15.3))
        p.addQuadCurve(to: pt(10, 11), control: pt(7.5, 12.4))
        p.closeSubpath()
        // coin
        p.addEllipse(in: CGRect(origin: pt(12.6, 16.6), size: CGSize(width: 6.8 * s, height: 6.8 * s)))
        return p
    }
}
