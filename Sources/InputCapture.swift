// InputCapture.swift
// A plain AppKit view that receives every mouse button and scroll event over it, including
// the back and forward side buttons, which SwiftUI doesn't report on its own.

import SwiftUI
import AppKit

final class CaptureView: NSView {
    var onEvent: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onEvent?(event) }
    override func mouseUp(with event: NSEvent) { onEvent?(event) }
    override func rightMouseDown(with event: NSEvent) { onEvent?(event) }
    override func rightMouseUp(with event: NSEvent) { onEvent?(event) }
    override func otherMouseDown(with event: NSEvent) { onEvent?(event) }
    override func otherMouseUp(with event: NSEvent) { onEvent?(event) }
    override func scrollWheel(with event: NSEvent) { onEvent?(event) }
    // no right-click menu inside the test boxes
    override func menu(for event: NSEvent) -> NSMenu? { nil }
}

struct InputCapture: NSViewRepresentable {
    var onEvent: (NSEvent) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let v = CaptureView()
        v.onEvent = onEvent
        return v
    }

    func updateNSView(_ view: CaptureView, context: Context) {
        view.onEvent = onEvent
    }
}

/// The dotted test box the tests live in. Mouse events land on the capture view underneath;
/// everything drawn on top ignores the mouse so nothing gets in the way.
struct TestBox<Overlay: View>: View {
    var height: CGFloat = 420
    var active = false
    var onEvent: (NSEvent) -> Void
    @ViewBuilder var overlay: Overlay

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(red: 11 / 255, green: 11 / 255, blue: 14 / 255))
            DotGrid().opacity(0.5).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            InputCapture(onEvent: onEvent)
            overlay.allowsHitTesting(false)
        }
        .frame(height: height)
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(active ? Color.aptOrange.opacity(0.55) : Color.aptLine, lineWidth: 1))
        .animation(.easeOut(duration: 0.3), value: active)
    }
}

struct DotGrid: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 26
            var y: CGFloat = step / 2
            while y < size.height {
                var x: CGFloat = step / 2
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)), with: .color(.white.opacity(0.12)))
                    x += step
                }
                y += step
            }
        }
        .allowsHitTesting(false)
    }
}
