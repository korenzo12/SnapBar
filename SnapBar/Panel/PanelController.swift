import AppKit
import SwiftUI

extension PanelCorner {
    var isLeft: Bool { self == .bottomLeft || self == .topLeft }
    var isBottom: Bool { self == .bottomLeft || self == .bottomRight }
}

enum PanelAction: String {
    case copy, edit, saveAs, reveal, copyText, delete
}

/// The corner panels. They stay until closed or used, stack up to five, and never take focus.
@MainActor
final class PanelController {
    static let shared = PanelController()
    static let maxStack = 5

    private(set) var panels: [QuickPanel] = []
    private let settings = AppSettings.shared

    func present(shot: Shot, since start: Date) {
        guard settings.panelEnabled else {
            NotificationsService.shared.post(shot: shot)
            Log.info("panel disabled, notification used id=\(shot.id.uuidString)")
            return
        }
        let frontBefore = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-"
        let panel = QuickPanel(shot: shot)
        panels.append(panel)
        while panels.count > PanelController.maxStack {
            let oldest = panels.removeFirst()
            oldest.close()
            Log.info("panel dismissed reason=overflow id=\(oldest.shot.id.uuidString)")
        }
        layout(animated: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
        Log.info("panel shown id=\(shot.id.uuidString) ms=\(Log.ms(since: start)) stack=\(panels.count)")
        let frontAfter = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-"
        Log.info("panel focus frontmostBefore=\(frontBefore) frontmostAfter=\(frontAfter)")
        let seconds = settings.panelAutoHideSeconds
        if seconds > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) { [weak self, weak panel] in
                MainActor.assumeIsolated {
                    guard let panel else { return }
                    self?.dismiss(panel, reason: "timeout")
                }
            }
        }
    }

    func dismiss(_ panel: QuickPanel, reason: String) {
        guard let index = panels.firstIndex(where: { $0 === panel }) else { return }
        panels.remove(at: index)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { panel.close() }
        })
        Log.info("panel dismissed reason=\(reason) id=\(panel.shot.id.uuidString)")
        layout(animated: true)
    }

    func dismissAll(reason: String) {
        for panel in panels { dismiss(panel, reason: reason) }
    }

    /// Brings an older, compact panel back to full size at the bottom of the stack.
    func promote(_ panel: QuickPanel) {
        guard let index = panels.firstIndex(where: { $0 === panel }), index != panels.count - 1 else { return }
        panels.remove(at: index)
        panels.append(panel)
        layout(animated: true)
    }

    func perform(_ action: PanelAction, on panel: QuickPanel) {
        let shot = ShotStore.shared.shot(id: panel.shot.id) ?? panel.shot
        Log.info("panel action=\(action.rawValue) id=\(shot.id.uuidString)")
        switch action {
        case .copy: ShotActions.copy([shot])
        case .edit: ShotActions.edit(shot)
        case .saveAs: ShotActions.saveAs(shot)
        case .reveal: ShotActions.reveal([shot])
        case .copyText: ShotActions.copyText(shot)
        case .delete: ShotStore.shared.remove(ids: [shot.id], trashFiles: true)
        }
        dismiss(panel, reason: "used")
    }

    /// Index of the screen that holds `point`, or the nearest one. Nil only with no screens.
    nonisolated static func screenIndex(for point: CGPoint, frames: [CGRect]) -> Int? {
        if let hit = frames.firstIndex(where: { $0.contains(point) }) { return hit }
        return frames.indices.min { distance(point, frames[$0]) < distance(point, frames[$1]) }
    }

    nonisolated private static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    private func layout(animated: Bool) {
        let screens = NSScreen.screens
        guard let index = PanelController.screenIndex(for: NSEvent.mouseLocation, frames: screens.map(\.frame)) else { return }
        let area = screens[index].visibleFrame
        let margin: CGFloat = 16
        let gap: CGFloat = 10
        let corner = settings.panelCorner
        var offset: CGFloat = 0
        for (slot, panel) in panels.reversed().enumerated() {
            let compact = slot > 0
            panel.state.compact = compact
            let size = compact ? QuickPanel.compactSize : QuickPanel.fullSize
            let x = corner.isLeft ? area.minX + margin : area.maxX - margin - size.width
            let y = corner.isBottom ? area.minY + margin + offset : area.maxY - margin - offset - size.height
            let frame = NSRect(x: x, y: y, width: size.width, height: size.height)
            if animated && panel.isVisible {
                // animator() runs asynchronously; setFrame(animate:) would block the app for each panel.
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    panel.animator().setFrame(frame, display: true)
                }
            } else {
                panel.setFrame(frame, display: true)
            }
            offset += size.height + gap
        }
    }
}
