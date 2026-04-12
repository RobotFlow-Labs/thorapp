import SwiftUI
import THORShared

struct DeployView: View {
    let device: Device
    @Environment(AppState.self) private var appState
    @State private var recipes: [DeployRecipe] = []
    @State private var selectedRecipeID: Int64?
    @State private var variableValues: [String: String] = [:]
    @State private var recentRuns: [RecipeRun] = []
    @State private var currentRun: RecipeRun?
    @State private var rollbackSuggestions: [DeployRecipeStep] = []
    @State private var errorMessage: String?
    @State private var isLoading = false

    private var deviceID: Int64 { device.id ?? 0 }

    private var selectedRecipe: DeployRecipe? {
        if let selectedRecipeID {
            return recipes.first(where: { $0.id == selectedRecipeID })
        }
        return recipes.first
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            recipeList
                .frame(width: 280)

            VStack(alignment: .leading, spacing: 16) {
                header
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
                if let recipe = selectedRecipe {
                    recipeDetail(recipe)
                    if let currentRun {
                        executionLogView(run: currentRun)
                    }
                    if !rollbackSuggestions.isEmpty {
                        rollbackCard
                    }
                } else {
                    ContentUnavailableView(
                        "No Deploy Recipes",
                        systemImage: "play.rectangle",
                        description: Text("Deploy recipes will appear here after the foundation database is initialized.")
                    )
                }
                recentRunsCard
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task {
            await loadRecipes()
        }
    }

    private var recipeList: some View {
        GroupBox("Deploy Recipes") {
            if recipes.isEmpty {
                Text("No deploy recipes available yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(recipes, id: \.id) { recipe in
                            let isSelected = selectedRecipeID == recipe.id || (selectedRecipeID == nil && recipes.first?.id == recipe.id)
                            Button {
                                selectedRecipeID = recipe.id
                                hydrateVariables(for: recipe)
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: recipe.icon)
                                        .foregroundStyle(isSelected ? .white : .secondary)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(recipe.name)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(isSelected ? .white : .primary)
                                        Text(recipe.summary)
                                            .font(.system(size: 10))
                                            .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(isSelected ? Color.accentColor : Color(.secondarySystemFill).opacity(0.45))
                                .clipShape(.rect(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Deploy Recipes", systemImage: "play.rectangle")
                    .font(.system(size: 15, weight: .semibold))
                Text("Typed deploy flows with prerequisites, readiness assertions, structured run history, and rollback guidance.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await loadRecipes() }
            } label: {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func recipeDetail(_ recipe: DeployRecipe) -> some View {
        GroupBox(recipe.name) {
            VStack(alignment: .leading, spacing: 14) {
                Text(recipe.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                if !recipe.variables.isEmpty {
                    variableEditor(recipe)
                }

                metadataRow(title: "Prerequisites", value: "\(recipe.prerequisites.count)")
                metadataRow(title: "Steps", value: "\(recipe.steps.count)")
                metadataRow(title: "Readiness Assertions", value: "\(recipe.readinessAssertions.count)")

                stepList(title: "Plan", steps: recipe.steps)

                HStack(spacing: 12) {
                    Button {
                        Task { await runRecipe(recipe) }
                    } label: {
                        if currentRun?.status == .running, currentRun?.recipeID == recipe.id {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Run Recipe", systemImage: "play.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(currentRun?.status == .running)

                    if !recipe.rollbackSteps.isEmpty {
                        Text("Rollback ready: \(recipe.rollbackSteps.count) step\(recipe.rollbackSteps.count == 1 ? "" : "s")")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func variableEditor(_ recipe: DeployRecipe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Variables")
                .font(.system(size: 12, weight: .medium))

            ForEach(recipe.variables) { variable in
                HStack {
                    Text(variable.label)
                        .font(.system(size: 12))
                        .frame(width: 140, alignment: .leading)
                    TextField(variable.defaultValue ?? variable.key, text: binding(for: variable))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private func stepList(title: String, steps: [DeployRecipeStep]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon(for: step.type))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.name)
                            .font(.system(size: 12, weight: .medium))
                        Text(step.type.rawValue)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(step.command)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 3)
            }
        }
    }

    private var rollbackCard: some View {
        GroupBox("Rollback Guidance") {
            VStack(alignment: .leading, spacing: 6) {
                Text("The recipe failed before completing. Review these rollback steps before retrying.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                ForEach(rollbackSuggestions) { step in
                    Text("• \(step.name): \(step.command)")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var recentRunsCard: some View {
        GroupBox("Recent Runs") {
            if recentRuns.isEmpty {
                Text("Recipe execution history will appear here after the first run.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(recentRuns) { run in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(run.recipeName)
                                    .font(.system(size: 12, weight: .medium))
                                Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(run.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(color(for: run.status))
                        }
                        .padding(.vertical, 8)

                        if run.id != recentRuns.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func executionLogView(run: RecipeRun) -> some View {
        GroupBox("Structured Run Log") {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(run.logs) { line in
                        Text("[\(line.timestamp)] \(line.level.uppercased()) \(line.message)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(logColor(for: line.level))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 220)
        }
    }

    private func metadataRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
            Spacer()
        }
    }

    private func loadRecipes() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let loadedRecipes = appState.loadDeployRecipes()
            async let loadedRuns = appState.recentRecipeRuns(for: deviceID)
            recipes = try await loadedRecipes
            recentRuns = try await loadedRuns
            if selectedRecipeID == nil {
                selectedRecipeID = recipes.first?.id
            }
            if let recipe = selectedRecipe {
                hydrateVariables(for: recipe)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func hydrateVariables(for recipe: DeployRecipe) {
        var next = variableValues
        for variable in recipe.variables {
            if next[variable.key]?.isEmpty != false {
                next[variable.key] = variable.defaultValue ?? ""
            }
        }
        variableValues = next
    }

    private func runRecipe(_ recipe: DeployRecipe) async {
        guard let client = appState.connector?.agentClient(for: deviceID) else {
            errorMessage = "Device not connected"
            return
        }

        rollbackSuggestions = []
        errorMessage = nil

        do {
            let variables = try resolvedVariables(for: recipe)
            var run = RecipeRun(
                deviceID: deviceID,
                recipeID: recipe.id,
                recipeName: recipe.name,
                status: .running,
                logs: []
            )

            appendLog(to: &run, level: "info", "Starting recipe on \(device.displayName)")

            let prerequisitesOk = try await runPrerequisites(recipe.prerequisites, variables: variables, client: client, run: &run)
            guard prerequisitesOk else {
                run.status = .failed
                run.finishedAt = Date()
                currentRun = try await appState.recordRecipeRun(run)
                recentRuns = try await appState.recentRecipeRuns(for: deviceID)
                rollbackSuggestions = recipe.rollbackSteps
                return
            }

            var failed = false
            for step in recipe.steps {
                let result = try await execute(step: step, variables: variables, client: client)
                appendLog(to: &run, level: result.success ? "success" : "error", "\(step.name): \(result.message)")
                if !result.success {
                    failed = true
                    if step.stopOnFailure {
                        break
                    }
                }
            }

            if !failed {
                let assertionsOk = try await runAssertions(recipe.readinessAssertions, variables: variables, client: client, run: &run)
                failed = !assertionsOk
            }

            run.status = failed ? .failed : .success
            run.finishedAt = Date()
            currentRun = try await appState.recordRecipeRun(run)
            recentRuns = try await appState.recentRecipeRuns(for: deviceID)
            rollbackSuggestions = failed ? recipe.rollbackSteps : []
            errorMessage = failed ? "Recipe failed. Review the structured run log and rollback guidance." : nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runPrerequisites(
        _ prerequisites: [DeployRecipePrerequisite],
        variables: [String: String],
        client: AgentClient,
        run: inout RecipeRun
    ) async throws -> Bool {
        guard !prerequisites.isEmpty else { return true }

        for prerequisite in prerequisites {
            let command = substitute(prerequisite.command, variables: variables)
            let result = try await client.exec(command: command, timeout: 20)
            let combined = [result.stdout, result.stderr].joined(separator: "\n")
            let matched = prerequisite.expectedSubstring.map { combined.contains($0) } ?? (result.exitCode == 0)
            appendLog(
                to: &run,
                level: matched ? "success" : "error",
                "Prerequisite \(prerequisite.name): \(matched ? "passed" : "failed")"
            )
            if !matched || result.exitCode != 0 {
                return false
            }
        }

        return true
    }

    private func runAssertions(
        _ assertions: [DeployRecipeAssertion],
        variables: [String: String],
        client: AgentClient,
        run: inout RecipeRun
    ) async throws -> Bool {
        guard !assertions.isEmpty else { return true }

        for assertion in assertions {
            let command = substitute(assertion.command, variables: variables)
            let result = try await client.exec(command: command, timeout: 20)
            let combined = [result.stdout, result.stderr].joined(separator: "\n")
            let matched = assertion.expectedSubstring.map { combined.contains($0) } ?? (result.exitCode == 0)
            appendLog(
                to: &run,
                level: matched ? "success" : "error",
                "Assertion \(assertion.name): \(matched ? "passed" : "failed")"
            )
            if !matched || result.exitCode != 0 {
                return false
            }
        }

        return true
    }

    private func execute(
        step: DeployRecipeStep,
        variables: [String: String],
        client: AgentClient
    ) async throws -> (success: Bool, message: String) {
        let command = substitute(step.command, variables: variables)

        switch step.type {
        case .registryPreflight:
            let registry = command.split(separator: "/").first.map(String.init) ?? command
            let response = try await client.validateDeviceRegistry(
                registryAddress: registry,
                image: command
            )
            let summary = response.stages.map { "\($0.name)=\($0.status.rawValue)" }.joined(separator: ", ")
            return (response.ready, summary.isEmpty ? response.status.rawValue : summary)

        case .dockerPull:
            let actualCommand = command.hasPrefix("docker ") ? command : "docker pull \(command)"
            let result = try await client.exec(command: actualCommand, timeout: step.timeout)
            return (result.exitCode == 0, commandPreview(from: result))

        default:
            let result = try await client.exec(command: command, timeout: step.timeout)
            return (result.exitCode == 0, commandPreview(from: result))
        }
    }

    private func resolvedVariables(for recipe: DeployRecipe) throws -> [String: String] {
        var values: [String: String] = [:]
        for variable in recipe.variables {
            let value = (variableValues[variable.key] ?? variable.defaultValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if variable.required && value.isEmpty {
                throw DeployViewError.missingRequiredVariable(variable.label)
            }
            values[variable.key] = value
        }
        return values
    }

    private func substitute(_ template: String, variables: [String: String]) -> String {
        variables.reduce(template) { partialResult, entry in
            partialResult.replacingOccurrences(of: "{{\(entry.key)}}", with: entry.value)
        }
    }

    private func commandPreview(from result: AgentExecResponse) -> String {
        let trimmed = [result.stdout, result.stderr]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return result.exitCode == 0 ? "completed" : "exit \(result.exitCode)"
        }
        return String(trimmed.prefix(200))
    }

    private func appendLog(to run: inout RecipeRun, level: String, _ message: String) {
        run.logs.append(
            RecipeRunLogLine(
                timestamp: Date().formatted(date: .omitted, time: .standard),
                level: level,
                message: message
            )
        )
    }

    private func binding(for variable: DeployRecipeVariable) -> Binding<String> {
        Binding(
            get: { variableValues[variable.key] ?? variable.defaultValue ?? "" },
            set: { variableValues[variable.key] = $0 }
        )
    }

    private func icon(for type: DeployRecipeStepType) -> String {
        switch type {
        case .registryPreflight:
            "checkmark.shield"
        case .dockerPull:
            "arrow.down.circle"
        case .dockerComposeUp:
            "play.circle"
        case .dockerComposeDown:
            "stop.circle"
        case .ros2LaunchStart:
            "point.3.connected.trianglepath.dotted"
        case .ros2LaunchStop:
            "stop.fill"
        case .ros2BagRecord:
            "record.circle"
        case .copyFiles:
            "doc.on.doc"
        case .modelWarmup:
            "flame"
        case .healthCheck:
            "heart.text.square"
        case .readOnlyShell:
            "terminal"
        }
    }

    private func logColor(for level: String) -> Color {
        switch level {
        case "success":
            .green
        case "error":
            .red
        default:
            .primary
        }
    }

    private func color(for status: RecipeRunStatus) -> Color {
        switch status {
        case .created, .running:
            .orange
        case .success:
            .green
        case .failed:
            .red
        case .rolledBack:
            .secondary
        }
    }
}

private enum DeployViewError: LocalizedError {
    case missingRequiredVariable(String)

    var errorDescription: String? {
        switch self {
        case .missingRequiredVariable(let label):
            return "Missing required variable: \(label)"
        }
    }
}
