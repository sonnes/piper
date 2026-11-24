import AppKit
import SwiftUI

/// The toast: one floating panel at the bottom right corner of the screen.
///
/// It shows a message of `Messages`, or the card of a web page capture. A new
/// toast replaces the one on the screen. The panel never activates Piper, so
/// the reader keeps working in the other application. Only a card that asks
/// for the keyboard takes it.
@MainActor
final class Toast: NSObject {

    enum Metrics {
        static let width: CGFloat = 360
        /// The space between the toast and the corner of the screen.
        static let margin: CGFloat = 30
        static let cornerRadius: CGFloat = 12
        static let padding = EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 12)
        static let buttonHeight: CGFloat = 24
        static let buttonPadding: CGFloat = 10
        static let buttonRadius: CGFloat = 6
        /// How long a toast with no button stays.
        static let duration: TimeInterval = 3
        /// How long a toast with a button stays.
        static let actionDuration: TimeInterval = 6
    }

    // MARK: - Properties

    private var panel: ToastPanel?
    private var dismiss: DispatchWorkItem?
    /// Runs when the content on the screen goes, by its timer, by `close`, or by a new toast.
    private var closed: (() -> Void)?
    private var resignedKey: (() -> Void)?

    var isVisible: Bool { panel?.isVisible == true }

    // MARK: - Showing

    func show(_ message: Message) {
        let action = message.action.map { action in
            Message.Action(title: action.title) { [weak self] in
                self?.close()
                action.perform()
            }
        }
        show(MessageCard(message: message, action: action),
             duration: message.action == nil ? Metrics.duration : Metrics.actionDuration)
    }

    /// Shows a view in the toast.
    ///
    /// - Parameters:
    ///   - takesKeyboard: True for a view with a text field. The toast then has no timer.
    ///   - duration: The time before the toast goes, for a toast that does not take the keyboard.
    ///   - closed: Runs when this view leaves the screen.
    ///   - resignedKey: Runs when the panel loses the keyboard.
    func show<Content: View>(_ view: Content, takesKeyboard: Bool = false, duration: TimeInterval = Metrics.actionDuration,
                             closed: (() -> Void)? = nil, resignedKey: (() -> Void)? = nil) {
        dismiss?.cancel()
        let previous = self.closed
        self.closed = closed
        self.resignedKey = resignedKey
        previous?()
        let panel = self.panel ?? makePanel()
        let hosting = FirstMouseHostingView(rootView: view)
        panel.contentView = hosting
        let size = hosting.fittingSize
        if let screen = NSScreen.main {
            panel.setFrame(NSRect(x: screen.visibleFrame.maxX - size.width - Metrics.margin, y: screen.visibleFrame.minY + Metrics.margin,
                                  width: size.width, height: size.height), display: true)
        }
        self.panel = panel
        panel.acceptsKey = takesKeyboard
        if takesKeyboard {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
            let work = DispatchWorkItem { [weak self] in self?.close() }
            dismiss = work
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        }
    }

    func close() {
        dismiss?.cancel()
        dismiss = nil
        resignedKey = nil
        let closed = self.closed
        self.closed = nil
        panel?.acceptsKey = false
        panel?.orderOut(nil)
        closed?()
    }
}

// MARK: - NSWindowDelegate

extension Toast: NSWindowDelegate {

    func windowDidResignKey(_ notification: Notification) {
        resignedKey?()
    }
}

// MARK: - Private

private extension Toast {

    func makePanel() -> ToastPanel {
        let panel = ToastPanel(contentRect: NSRect(x: 0, y: 0, width: Metrics.width, height: 100),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        return panel
    }
}

/// A panel that takes the keyboard only while a card with a text field shows.
private final class ToastPanel: NSPanel {
    var acceptsKey = false
    override var canBecomeKey: Bool { acceptsKey }
}

/// The toast takes a click without first becoming the key window.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Views

/// The frame of every toast.
struct ToastCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) { content }
            .padding(Toast.Metrics.padding)
            .frame(width: Toast.Metrics.width, alignment: .leading)
            .foregroundStyle(PiperTheme.paperInk)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Toast.Metrics.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Toast.Metrics.cornerRadius).strokeBorder(PiperTheme.paperRule, lineWidth: 0.5))
    }
}

/// The accent button of the toast. A stock prominent button turns gray in a
/// panel that is not the key window, and the toast is rarely the key window.
struct ToastButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PiperTheme.paperUI(.body, weight: .medium))
            .foregroundStyle(PiperTheme.onAccent)
            .padding(.horizontal, Toast.Metrics.buttonPadding)
            .frame(height: Toast.Metrics.buttonHeight)
            .background(PiperTheme.brand.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: Toast.Metrics.buttonRadius))
            .contentShape(Rectangle())
    }
}

private struct MessageCard: View {
    let message: Message
    let action: Message.Action?

    var body: some View {
        ToastCard {
            HStack(spacing: 10) {
                Image(systemName: message.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(message.isError ? PiperTheme.warning : PiperTheme.brand)
                    .accessibilityHidden(true)
                Text(message.text).font(PiperTheme.paperUI(.body)).lineLimit(3).help(message.text)
                Spacer(minLength: 0)
                if let action {
                    Button(action.title, action: action.perform).buttonStyle(ToastButtonStyle())
                } else if !message.isError {
                    Text(Command.today.key?.glyph ?? "").font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint)
                }
            }
        }
    }
}
