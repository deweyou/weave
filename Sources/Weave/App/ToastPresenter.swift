import Foundation
import Observation

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
