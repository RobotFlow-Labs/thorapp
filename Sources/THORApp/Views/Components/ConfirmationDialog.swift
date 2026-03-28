import SwiftUI

/// Reusable confirmation alert for destructive actions.
struct DestructiveActionModifier: ViewModifier {
    let title: String
    let message: String
    let actionLabel: String
    @Binding var isPresented: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: $isPresented) {
                Button(actionLabel, role: .destructive, action: action)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(message)
            }
    }
}

extension View {
    func destructiveConfirmation(
        _ title: String,
        message: String,
        actionLabel: String = "Confirm",
        isPresented: Binding<Bool>,
        action: @escaping () -> Void
    ) -> some View {
        modifier(DestructiveActionModifier(
            title: title,
            message: message,
            actionLabel: actionLabel,
            isPresented: isPresented,
            action: action
        ))
    }
}
