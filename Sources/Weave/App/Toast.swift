import Accessibility
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Transient, recoverable feedback. Persistent data-loss/save errors still use their own UI.
struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    var details: String?
}

@Observable @MainActor
final class ToastPresenter {
    private(set) var message: ToastMessage?

    func show(_ message: ToastMessage) { self.message = message }

    func dismiss(id: UUID) {
        guard message?.id == id else { return }
        message = nil
    }

    func clear() { message = nil }
}

struct ToastOverlay: View {
    @Bindable var presenter: ToastPresenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let message = presenter.message {
                ToastCard(message: message) { presenter.dismiss(id: message.id) }
                    .id(message.id)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: presenter.message?.id)
    }
}

private struct ToastCard: View {
    let message: ToastMessage
    let dismiss: () -> Void
    @State private var isHovered = false
    @State private var showsDetails = false
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private struct TimerKey: Equatable {
        let hovered: Bool
        let details: Bool
        let voiceOver: Bool
    }

    private var buttonSize: CGFloat {
        #if os(macOS)
            32
        #else
            44
        #endif
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(message.title).font(.callout.weight(.semibold))
                Text(message.message).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            HStack(spacing: 0) {
                if let details = message.details {
                    Button {
                        showsDetails = true
                    } label: {
                        Image(systemName: "info.circle")
                            .frame(width: buttonSize, height: buttonSize)
                            .contentShape(Rectangle())
                    }
                    .modifier(ToastButtonPointer())
                    .help("查看详细原因")
                    .accessibilityLabel("查看详细原因")
                    .accessibilityIdentifier("toast-details")
                    .popover(isPresented: $showsDetails) {
                        ScrollView {
                            Text(details)
                                .font(.callout)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(20)
                        }
                        .frame(idealWidth: 360, maxWidth: 420, idealHeight: 200, maxHeight: 320)
                    }
                }
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.callout.weight(.medium))
                        .frame(width: buttonSize, height: buttonSize)
                        .contentShape(Rectangle())
                }
                .modifier(ToastButtonPointer())
                .help("关闭提示")
                .accessibilityLabel("关闭提示")
                .accessibilityIdentifier("toast-dismiss")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 12)
        .frame(maxWidth: 440)
        .background {
            if reduceTransparency || contrast == .increased {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.background)
                    .strokeBorder(.primary.opacity(0.2), lineWidth: 1)
            }
        }
        .glassEffect(reduceTransparency || contrast == .increased ? .identity : .regular, in: .rect(cornerRadius: 20))
        .accessibilityIdentifier("feedback-toast")
        .onHover { isHovered = $0 }
        .task {
            AccessibilityNotification.Announcement(message.title + "。" + message.message).post()
        }
        .task(id: TimerKey(hovered: isHovered, details: showsDetails, voiceOver: voiceOver)) {
            guard !isHovered, !showsDetails, !voiceOver else { return }
            do {
                try await Task.sleep(for: .seconds(4))
                try Task.checkCancellation()
                dismiss()
            } catch {
                // ContinuousClock sleep/checkCancellation only throw cancellation.
                // Hover, details, replacement and leaving the editor cancel this timer.
                return
            }
        }
    }
}

/// Scope the cursor to each control, not the containing glass surface.
private struct ToastButtonPointer: ViewModifier {
    #if os(macOS)
        @State private var isHovered = false
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
            content
                .pointerStyle(.link)
                .background(PointingHandRegion())
                .onContinuousHover { phase in
                    switch phase {
                    case .active:
                        isHovered = true
                        NSCursor.pointingHand.set()
                    case .ended:
                        isHovered = false
                        NSCursor.arrow.set()
                    }
                }
                .onDisappear {
                    // Clicking Close removes the button before a hover-exit event.
                    if isHovered { NSCursor.arrow.set() }
                }
        #else
            content
        #endif
    }
}
