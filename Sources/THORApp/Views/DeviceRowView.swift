import SwiftUI
import THORShared

struct DeviceRowView: View {
    let device: Device
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 12) {
            statusIndicator
            VStack(alignment: .leading, spacing: 4) {
                Text(device.displayName)
                    .font(.system(size: 14, weight: .medium))
                Text(device.hostname)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            environmentBadge
        }
        .padding(.vertical, 4)
    }

    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
    }

    private var statusColor: Color {
        switch status {
        case .connected: .green
        case .degraded: .orange
        case .disconnected, .unreachable: .red
        case .authFailed, .hostKeyMismatch: .red
        case .unknown: .gray
        }
    }

    private var environmentBadge: some View {
        Text(device.environment.rawValue.uppercased())
            .font(.system(size: 10, weight: .medium))
            .tracking(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color(.secondarySystemFill))
            .clipShape(.rect(cornerRadius: 4))
    }
}
