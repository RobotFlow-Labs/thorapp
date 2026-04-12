import SwiftUI
import THORShared

struct CapabilityGateView: View {
    let gate: CapabilityGate

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Text(gate.reason)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let action = gate.actionLabel {
                Text(action)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private var title: String {
        switch gate.state {
        case .supported: "Ready"
        case .degraded: "Available with Limits"
        case .unsupported: "Unsupported"
        case .needsSetup: "Needs Setup"
        }
    }

    private var icon: String {
        switch gate.state {
        case .supported: "checkmark.circle"
        case .degraded: "exclamationmark.triangle"
        case .unsupported: "xmark.circle"
        case .needsSetup: "wrench.and.screwdriver"
        }
    }

    private var color: Color {
        switch gate.state {
        case .supported: .green
        case .degraded: .orange
        case .unsupported: .red
        case .needsSetup: .blue
        }
    }
}
