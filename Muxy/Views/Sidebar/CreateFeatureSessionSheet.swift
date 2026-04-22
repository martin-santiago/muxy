import AppKit
import SwiftUI

struct CreateFeatureSessionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onCreateSession: @MainActor (String, [FeatureSessionRepositorySelection]) async throws -> Void

    @State private var sessionName = ""
    @State private var repositories: [FeatureSessionRepositorySelection] = []
    @State private var errorMessage: String?
    @State private var isInspectingRepositories = false
    @State private var isCreatingSession = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Feature Session")
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Session Name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuxyTheme.fgMuted)
                TextField("feature/session-name", text: $sessionName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Repositories")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MuxyTheme.fgMuted)
                    Spacer()
                    Button(repositories.isEmpty ? "Add Git Repositories…" : "Add More Repositories…") {
                        handleSelectRepositories()
                    }
                    .disabled(isBusy)
                }

                if repositories.isEmpty {
                    emptyRepositoriesState
                } else {
                    repositoryList
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(MuxyTheme.diffRemoveFg)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .disabled(isBusy)
                Button(isCreatingSession ? "Creating…" : "Create Session") {
                    handleCreateSession()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isCreateButtonDisabled)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var repositoryList: some View {
        VStack(spacing: 8) {
            ForEach(repositories) { repository in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(repository.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MuxyTheme.fg)
                        Text(repository.currentBranch)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(MuxyTheme.fgDim)
                    }
                    Spacer()
                    Button {
                        repositories.removeAll { $0.id == repository.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(MuxyTheme.fgDim)
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var emptyRepositoriesState: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(MuxyTheme.surface)
            .overlay {
                Text(isInspectingRepositories ? "Inspecting repositories…" : "Select one or more Git repositories.")
                    .font(.system(size: 12))
                    .foregroundStyle(MuxyTheme.fgDim)
            }
            .frame(height: 88)
    }

    private var isBusy: Bool {
        isInspectingRepositories || isCreatingSession
    }

    private var isCreateButtonDisabled: Bool {
        isBusy || sessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || repositories.isEmpty
    }

    private func handleSelectRepositories() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "Select Git repositories"
        guard panel.runModal() == .OK else { return }
        let selectedPaths = panel.urls.map { $0.path(percentEncoded: false) }

        Task {
            await loadRepositories(selectedPaths)
        }
    }

    @MainActor
    private func loadRepositories(_ selectedPaths: [String]) async {
        isInspectingRepositories = true
        errorMessage = nil
        do {
            let selectedRepositories = try await FeatureSessionService.inspectRepositories(paths: selectedPaths)
            repositories = mergeRepositories(selectedRepositories)
        } catch {
            errorMessage = error.localizedDescription
        }
        isInspectingRepositories = false
    }

    private func handleCreateSession() {
        let currentSessionName = sessionName
        let selectedRepositories = repositories

        Task {
            await submitSessionCreation(currentSessionName, selectedRepositories)
        }
    }

    @MainActor
    private func submitSessionCreation(
        _ selectedSessionName: String,
        _ selectedRepositories: [FeatureSessionRepositorySelection]
    ) async {
        isCreatingSession = true
        errorMessage = nil
        do {
            try await onCreateSession(selectedSessionName, selectedRepositories)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isCreatingSession = false
    }

    private func mergeRepositories(
        _ incomingRepositories: [FeatureSessionRepositorySelection]
    ) -> [FeatureSessionRepositorySelection] {
        FeatureSessionRepositorySelectionMerger.merge(
            existingRepositories: repositories,
            incomingRepositories: incomingRepositories
        )
    }
}
