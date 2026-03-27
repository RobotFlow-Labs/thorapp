import SwiftUI

struct EmptyDeviceView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Select a Device")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Choose a device from the sidebar or add a new one.")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
