import AppKit
import SwiftUI

struct CreateFeatureSessionSheet: View {
    enum Mode: Hashable, Identifiable {
        case create
        case append(Project)

        var id: String {
            switch self {
            case .create:
                "create"
            case let .append(project):
                "append-\(project.id.uuidString)"
            }
        }
    }

    @Environment(\.dismiss) var dismiss

    let mode: Mode
    let onSubmit: @MainActor (
        Mode,
        String,
        [FeatureSessionRepositorySelection],
        Bool,
        @escaping FeatureSessionCreationProgressHandler
    ) async throws -> Void

    @State var sessionName = ""
    @State var repositories: [FeatureSessionRepositorySelection] = []
    @State var copyHiddenAndIgnoredFiles = false
    @State var availableBranchesByRepositoryID: [String: [String]] = [:]
    @State var loadingRepositoryIDs: Set<String> = []
    @State var errorMessage: String?
    @State var isInspectingRepositories = false
    @State var isCreatingSession = false
    @State var progressStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(sheetTitle)
                .font(.system(size: 16, weight: .semibold))

            if case let .append(project) = mode {
                Text("Adding repositories to \(project.name)")
                    .font(.system(size: 12))
                    .foregroundStyle(MuxyTheme.fgDim)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Session Name")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MuxyTheme.fgMuted)
                    TextField("feature/session-name", text: $sessionName)
                        .textFieldStyle(.roundedBorder)
                }
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

            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $copyHiddenAndIgnoredFiles) {
                    Text("Copy hidden & ignored files")
                        .font(.system(size: 12, weight: .medium))
                }
                .toggleStyle(.switch)
                .disabled(isBusy)
                Text(
                    "Copies untracked and gitignored files such as .env, .vscode, and local configs into each new worktree. node_modules is never copied, even when this is enabled. Large ignored file sets can still take a while."
                )
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.fgDim)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(MuxyTheme.diffRemoveFg)
            }

            if isCreatingSession, let progressStatus {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(progressStatus)
                        .font(.system(size: 12))
                        .foregroundStyle(MuxyTheme.fgMuted)
                        .animation(.easeInOut(duration: 0.15), value: progressStatus)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .disabled(isBusy)
                Button(isCreatingSession ? inProgressCTA : submitCTA) {
                    handleSubmit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitButtonDisabled)
            }
        }
        .padding(20)
        .frame(width: 600)
    }

    private var repositoryList: some View {
        VStack(spacing: 8) {
            ForEach(repositories) { repository in
                FeatureSessionRepositoryRow(
                    repository: repository,
                    availableBranches: availableBranches(for: repository),
                    isLoadingBranches: loadingRepositoryIDs.contains(repository.id),
                    isDisabled: isBusy,
                    onSelectBaseBranch: { selectedBaseBranch in
                        updateSelectedBaseBranch(repositoryID: repository.id, selectedBaseBranch: selectedBaseBranch)
                    },
                    onRefreshBranches: {
                        Task {
                            await loadAvailableBranches(for: repository, forceRefresh: true)
                        }
                    },
                    onRemove: {
                        repositories.removeAll { $0.id == repository.id }
                    }
                )
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
}
