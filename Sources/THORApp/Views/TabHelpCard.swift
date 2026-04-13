import SwiftUI

struct TabHelpCard: View {
    let tab: DetailTab
    let onHide: () -> Void
    let onHideByDefault: () -> Void

    private var help: DetailTabHelp {
        tab.help
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(help.title, systemImage: "questionmark.circle")
                            .font(.system(size: 15, weight: .semibold))
                        Text(help.summary)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button("Hide") {
                            onHide()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Hide by Default") {
                            onHideByDefault()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if !help.startHere.isEmpty {
                    helpSection(
                        title: "Start Here",
                        icon: "play.circle",
                        items: help.startHere
                    )
                }

                if !help.lookFor.isEmpty {
                    helpSection(
                        title: "Look For",
                        icon: "scope",
                        items: help.lookFor
                    )
                }
            }
            .padding(4)
        }
    }

    private func helpSection(title: String, icon: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            ForEach(Array(items.enumerated()), id: \.offset) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 2)
                    Text(entry.element)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
