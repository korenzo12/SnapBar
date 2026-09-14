import AppKit
import SwiftUI

@MainActor
final class QuickPanelState: ObservableObject {
    @Published var compact = false
}

extension NSImage {
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// A floating, non-activating panel: it shows over everything without stealing focus from the app you are in.
@MainActor
final class QuickPanel: NSPanel {
    static let fullSize = NSSize(width: 280, height: 244)
    static let compactSize = NSSize(width: 280, height: 62)

    let shot: Shot
    let state = QuickPanelState()

    init(shot: Shot) {
        self.shot = shot
        super.init(contentRect: NSRect(origin: .zero, size: QuickPanel.fullSize),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = .roundedMask(radius: 14)
        let host = NSHostingView(rootView: QuickPanelView(panel: self, shot: shot, state: state))
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        contentView = effect
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        PanelController.shared.dismiss(self, reason: "escape")
    }
}

struct QuickPanelView: View {
    let panel: QuickPanel
    let shot: Shot
    @ObservedObject var state: QuickPanelState
    @State private var image: NSImage?

    private var controller: PanelController { PanelController.shared }

    var body: some View {
        Group {
            if state.compact { compactBody } else { fullBody }
        }
        .onAppear(perform: loadImage)
    }

    private var title: String { shot.appName ?? shot.fileName }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: shot.source == .native ? "command" : "camera.viewfinder")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11, weight: .semibold))
                Text(verbatim: title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(shot.createdAt, format: .dateTime.hour().minute())
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer(minLength: 4)
                closeButton
            }
            DragThumbnail(urls: [shot.url], image: image, onClick: nil) { moved in
                if moved {
                    Log.info("panel action=drag id=\(shot.id.uuidString)")
                    controller.dismiss(panel, reason: "used")
                }
            }
            .frame(height: 142)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.quaternary))
            .help(Text("Drag into any app"))
            HStack(spacing: 6) {
                Button {
                    controller.perform(.copy, on: panel)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 22)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
                .help(Text("Copy"))
                .accessibilityLabel(Text("Copy"))
                iconButton("pencil.tip.crop.circle", "Edit", .edit)
                iconButton("square.and.arrow.down", "Save As…", .saveAs)
                iconButton("folder", "Show in Finder", .reveal)
                iconButton("text.viewfinder", "Copy Text", .copyText)
                iconButton("trash", "Move to Trash", .delete)
            }
        }
        .padding(12)
        .frame(width: QuickPanel.fullSize.width, height: QuickPanel.fullSize.height)
    }

    private var compactBody: some View {
        HStack(spacing: 10) {
            DragThumbnail(urls: [shot.url], image: image, onClick: { controller.promote(panel) }) { moved in
                if moved { controller.dismiss(panel, reason: "used") }
            }
            .frame(width: 58, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(shot.createdAt, style: .relative).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 4)
            Button { controller.perform(.copy, on: panel) } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .help(Text("Copy"))
            closeButton
        }
        .padding(.horizontal, 10)
        .frame(width: QuickPanel.compactSize.width, height: QuickPanel.compactSize.height)
    }

    private var closeButton: some View {
        Button {
            controller.dismiss(panel, reason: "close")
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .frame(width: 18, height: 18)
                .background(Circle().fill(.quaternary))
        }
        .buttonStyle(.plain)
        .help(Text("Close"))
        .accessibilityLabel(Text("Close"))
    }

    private func iconButton(_ symbol: String, _ label: LocalizedStringKey, _ action: PanelAction) -> some View {
        Button {
            controller.perform(action, on: panel)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }

    private func loadImage() {
        ThumbnailCache.shared.thumbnail(for: shot, size: 512) { loaded in
            image = loaded
        }
    }
}
