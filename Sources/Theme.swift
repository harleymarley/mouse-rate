// Theme.swift
// Colors, text styles and small shared views, matching the Almost Perfect mouse test website.

import SwiftUI
import AppKit

extension Color {
    static let aptBg = Color(red: 5 / 255, green: 5 / 255, blue: 6 / 255)
    static let aptCard = Color(red: 15 / 255, green: 15 / 255, blue: 18 / 255)
    static let aptCardHi = Color(red: 22 / 255, green: 22 / 255, blue: 27 / 255)
    static let aptLine = Color.white.opacity(0.08)
    static let aptLine2 = Color.white.opacity(0.14)
    static let aptOrange = Color(red: 253 / 255, green: 120 / 255, blue: 2 / 255)
    static let aptHi = Color(red: 255 / 255, green: 158 / 255, blue: 69 / 255)
    static let aptPale = Color(red: 255 / 255, green: 196 / 255, blue: 138 / 255)
    static let aptText = Color(red: 244 / 255, green: 244 / 255, blue: 242 / 255)
    static let aptSoft = Color(red: 201 / 255, green: 201 / 255, blue: 207 / 255)
    static let aptMuted = Color(red: 140 / 255, green: 140 / 255, blue: 149 / 255)
    static let aptDim = Color(red: 85 / 255, green: 85 / 255, blue: 93 / 255)
    static let aptOk = Color(red: 63 / 255, green: 207 / 255, blue: 142 / 255)
    static let aptBad = Color(red: 255 / 255, green: 90 / 255, blue: 78 / 255)
    static let aptInk = Color(red: 26 / 255, green: 12 / 255, blue: 0)
    // Buy Me a Coffee yellow, so the tip card stands apart from the orange buttons
    static let coffee = Color(red: 255 / 255, green: 221 / 255, blue: 0)
    static let coffeeHi = Color(red: 255 / 255, green: 233 / 255, blue: 77 / 255)
    static let coffeeInk = Color(red: 26 / 255, green: 20 / 255, blue: 0)
}

extension Font {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .black) }
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    static func number(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded).monospacedDigit() }
}

/// A rounded card on a slightly lighter surface, like the panels on the website.
struct Panel<Content: View>: View {
    var padding: CGFloat = 24
    var glow = false
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.aptCard))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(glow ? Color.aptOrange.opacity(0.35) : Color.aptLine, lineWidth: 1))
    }
}

/// The orange pill button.
struct PrimaryButton: View {
    let title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ui(14, .bold))
                .foregroundColor(.aptInk)
                .padding(.horizontal, 20).padding(.vertical, 11)
                .background(Capsule().fill(LinearGradient(colors: [.aptHi, .aptOrange], startPoint: .top, endPoint: .bottom)))
                .shadow(color: Color.aptOrange.opacity(0.35), radius: 12, y: 6)
        }
        .buttonStyle(PressStyle())
    }
}

/// The dark outlined pill button.
struct SecondaryButton: View {
    let title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ui(14, .semibold))
                .foregroundColor(.aptText)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Capsule().fill(Color.white.opacity(0.04)))
                .overlay(Capsule().stroke(Color.aptLine2, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A small label + value block, like the stats on the website.
struct Stat: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.ui(13, .medium)).foregroundColor(.aptSoft)
            Text(value).font(.number(22)).foregroundColor(.aptText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.aptLine, lineWidth: 1))
    }
}

/// A line of cheeky commentary in the brand's pale orange.
struct Quip: View {
    let text: String
    var size: CGFloat = 22
    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(size: size, weight: .heavy))
                .foregroundColor(.aptPale)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(text)
        }
    }
}

/// A timer that keeps running while a view redraws. (A Timer.publish stored in a view restarts
/// every time the view redraws, so on a busy screen it can stop firing altogether.)
final class Ticker: ObservableObject {
    @Published var now = Date()
    private var timer: Timer?
    init(_ interval: TimeInterval) {
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.now = Date() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    deinit { timer?.invalidate() }
}

func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
