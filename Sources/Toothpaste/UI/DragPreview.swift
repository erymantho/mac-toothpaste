import AppKit
import SwiftUI

/// The entry itself, carried beside the pointer while it is dragged out of the panel.
///
/// Asked for once drag-to-type existed: the pointer alone said *where*, but not *what*.
/// It is the row as the panel draws it — same font, padding, fill and pin stripe — lifted
/// with a slight tilt so it reads as picked up rather than as a tooltip.
///
/// Three things are deliberate:
/// - **Beside the pointer, never under it.** The click lands on the pointer's tip, and a
///   card over the tip would cover the very field being aimed at. The pointer itself is
///   the ordinary arrow, and the card sits clear of it.
/// - **Invisible to the mouse.** The drop, and the click made there, must go to whatever is
///   underneath. It is also taken off screen before that click is posted.
/// - **A masked entry stays masked.** Carrying it across the screen must not be the thing
///   that finally shows it; the card is given the text the row shows, dots included.
@MainActor
final class DragPreview {
    static let shared = DragPreview()

    /// Tilt and lift at full pickup, applied with a small spring.
    static let tilt = 3.0
    static let lift = 1.03

    private var panel: NSPanel?
    private var card = CGSize.zero
    private var window = CGSize.zero

    private let gap = CGSize(width: 18, height: 14)
    private let maxWidth: CGFloat = 320
    /// Room around the card for its shadow and for the corners it swings out when tilted.
    private let margin: CGFloat = 16

    /// The card's upright size for a given text, capped so a long command does not stretch
    /// across half the screen — it truncates like the row does.
    static func measure(_ text: String) -> CGSize {
        let fit = NSHostingView(rootView: CardFace(text: text)).fittingSize
        return CGSize(width: min(fit.width, 320), height: fit.height)
    }

    func show(_ text: String, pinned: Bool, at location: NSPoint) {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        card = Self.measure(text)
        // The tilted card's bounding box at full lift, plus the margin.
        let angle = Self.tilt * .pi / 180
        let w = card.width * Self.lift, h = card.height * Self.lift
        window = CGSize(width: (w * cos(angle) + h * sin(angle)).rounded(.up) + margin * 2,
                        height: (w * sin(angle) + h * cos(angle)).rounded(.up) + margin * 2)

        let host = NSHostingView(rootView: DragPreviewCard(text: text, pinned: pinned, size: card))
        host.frame = NSRect(origin: .zero, size: window)
        panel.contentView = host
        panel.setContentSize(window)
        move(to: location)
        panel.orderFrontRegardless()
    }

    func move(to location: NSPoint) {
        guard let panel, panel.isVisible else { return }
        // Where the card should sit: below and to the right of the pointer ...
        var cardLeft = location.x + gap.width
        var cardTop = location.y - gap.height
        // ... unless that runs off the display the pointer is on; then the other side.
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(location, $0.frame, false) }) {
            if cardLeft + card.width > screen.frame.maxX { cardLeft = location.x - gap.width - card.width }
            if cardTop - card.height < screen.frame.minY { cardTop = location.y + gap.height + card.height }
        }
        // The window is larger than the card and centred on it.
        panel.setFrameOrigin(NSPoint(x: cardLeft - (window.width - card.width) / 2,
                                     y: cardTop + (window.height - card.height) / 2 - window.height))
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        // The level macOS itself draws drag images at: above other apps' windows, menus
        // and full-screen spaces, which is where something being carried belongs.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.draggingWindow)))
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The shadow is drawn by the card instead: a window shadow is computed once when
        // the window appears, and would stay square under a card that has since tilted.
        panel.hasShadow = false
        panel.alphaValue = 0.96
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        return panel
    }
}

/// The row's text as the panel sets it, on its own — what the card is measured by.
private struct CardFace: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
    }
}

struct DragPreviewCard: View {
    let text: String
    let pinned: Bool
    let size: CGSize
    @State private var lifted = false

    var body: some View {
        CardFace(text: text)
            .frame(width: size.width, height: size.height, alignment: .leading)
            .background(pinned ? Theme.rowPinned : Theme.row)
            .overlay(alignment: .leading) {
                if pinned { Rectangle().fill(Color.accentColor).frame(width: 3) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
            .shadow(color: .black.opacity(lifted ? 0.30 : 0.12),
                    radius: lifted ? 10 : 3, y: lifted ? 5 : 1)
            .rotationEffect(.degrees(lifted ? DragPreview.tilt : 0))
            .scaleEffect(lifted ? DragPreview.lift : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.62)) { lifted = true }
            }
    }
}
