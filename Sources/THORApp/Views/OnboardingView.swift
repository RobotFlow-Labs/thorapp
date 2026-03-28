import SwiftUI

struct OnboardingView: View {
    @Binding var isComplete: Bool
    @State private var currentStep = 0

    private let steps: [OnboardingStep] = [
        OnboardingStep(
            icon: "cpu.fill",
            title: "Welcome to THOR",
            subtitle: "The Mac control plane for Jetson robotics",
            description: "Connect, deploy, debug, and manage your NVIDIA Jetson devices — without Terminal."
        ),
        OnboardingStep(
            icon: "link.badge.plus",
            title: "Connect Your Jetson",
            subtitle: "SSH-based secure connectivity",
            description: "THOR connects to Jetson devices over SSH. Your credentials are stored securely in macOS Keychain. The agent API runs on localhost only, tunneled through SSH."
        ),
        OnboardingStep(
            icon: "rectangle.3.group.fill",
            title: "Manage Your Fleet",
            subtitle: "One app for all your devices",
            description: "Monitor health, sync files, control Docker containers, stream logs, and run deploy profiles across multiple Jetson devices."
        ),
    ]

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            Image(systemName: steps[currentStep].icon)
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            // Text
            VStack(spacing: 8) {
                Text(steps[currentStep].title)
                    .font(.title)
                    .fontWeight(.semibold)
                Text(steps[currentStep].subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Text(steps[currentStep].description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Spacer()

            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            // Buttons
            HStack(spacing: 16) {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if currentStep < steps.count - 1 {
                    Button("Next") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        isComplete = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 32)
        }
        .padding(40)
        .frame(width: 600, height: 450)
    }
}

private struct OnboardingStep {
    let icon: String
    let title: String
    let subtitle: String
    let description: String
}
