import AppKit
import Foundation

extension CreateFeatureSessionSheet {
    var isBusy: Bool {
        isInspectingRepositories || isCreatingSession
    }

    var isSubmitButtonDisabled: Bool {
        if isBusy || repositories.isEmpty {
            return true
        }
        guard case .create = mode else { return false }
        return sessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var sheetTitle: String {
        switch mode {
        case .create:
            "Create Feature Session"
        case .append:
            "Add Repositories"
        }
    }

    var submitCTA: String {
        switch mode {
        case .create:
            "Create Session"
        case .append:
            "Add Repositories"
        }
    }

    var inProgressCTA: String {
        switch mode {
        case .create:
            "Creating…"
        case .append:
            "Adding…"
        }
    }

    var resolvedSessionName: String {
        switch mode {
        case .create:
            sessionName
        case let .append(project):
            project.name
        }
    }

    var existingRepositoryPaths: Set<String> {
        guard case let .append(project) = mode,
              let featureSession = project.featureSession
        else {
            return []
        }
        return Set(featureSession.repositories.map { FeatureSessionService.canonicalPath($0.sourcePath) })
    }

    func handleSelectRepositories() {
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
    func loadRepositories(_ selectedPaths: [String]) async {
        isInspectingRepositories = true
        errorMessage = nil
        do {
            let selectedRepositories = try await FeatureSessionService.inspectRepositories(paths: selectedPaths)
            let filteredRepositories = selectedRepositories.filter {
                !existingRepositoryPaths.contains(FeatureSessionService.canonicalPath($0.path))
            }
            repositories = mergeRepositories(filteredRepositories)
            await loadAvailableBranches(for: repositories)
        } catch {
            errorMessage = error.localizedDescription
        }
        isInspectingRepositories = false
    }

    func handleSubmit() {
        let currentSessionName = resolvedSessionName
        let selectedRepositories = repositories
        let shouldCopyHiddenAndIgnoredFiles = copyHiddenAndIgnoredFiles
        let currentMode = mode

        Task {
            await submit(
                currentMode,
                currentSessionName,
                selectedRepositories,
                shouldCopyHiddenAndIgnoredFiles
            )
        }
    }

    @MainActor
    func submit(
        _ currentMode: Mode,
        _ selectedSessionName: String,
        _ selectedRepositories: [FeatureSessionRepositorySelection],
        _ shouldCopyHiddenAndIgnoredFiles: Bool
    ) async {
        isCreatingSession = true
        errorMessage = nil
        progressStatus = nil
        do {
            try await onSubmit(
                currentMode,
                selectedSessionName,
                selectedRepositories,
                shouldCopyHiddenAndIgnoredFiles
            ) { creationEvent in
                progressStatus = creationEvent.userFacingDescription
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isCreatingSession = false
        progressStatus = nil
    }

    func mergeRepositories(
        _ incomingRepositories: [FeatureSessionRepositorySelection]
    ) -> [FeatureSessionRepositorySelection] {
        FeatureSessionRepositorySelectionMerger.merge(
            existingRepositories: repositories,
            incomingRepositories: incomingRepositories
        )
    }

    @MainActor
    func loadAvailableBranches(
        for repositories: [FeatureSessionRepositorySelection]
    ) async {
        for repository in repositories {
            await loadAvailableBranches(for: repository, forceRefresh: false)
        }
    }

    @MainActor
    func loadAvailableBranches(
        for repository: FeatureSessionRepositorySelection,
        forceRefresh: Bool
    ) async {
        if !forceRefresh, availableBranchesByRepositoryID[repository.id] != nil {
            return
        }
        if loadingRepositoryIDs.contains(repository.id) {
            return
        }

        loadingRepositoryIDs.insert(repository.id)
        defer { loadingRepositoryIDs.remove(repository.id) }

        do {
            let branches = try await GitRepositoryService().listBranches(repoPath: repository.path)
            availableBranchesByRepositoryID[repository.id] = uniqueBranches(
                branches + [repository.currentBranch, repository.selectedBaseBranch]
            )
        } catch {
            availableBranchesByRepositoryID[repository.id] = uniqueBranches(availableBranches(for: repository))
            errorMessage = error.localizedDescription
        }
    }

    func availableBranches(for repository: FeatureSessionRepositorySelection) -> [String] {
        uniqueBranches(
            (availableBranchesByRepositoryID[repository.id] ?? []) +
                [repository.currentBranch, repository.selectedBaseBranch]
        )
    }

    func uniqueBranches(_ branches: [String]) -> [String] {
        var seenBranches: Set<String> = []
        var uniqueBranches: [String] = []

        for branch in branches where !branch.isEmpty {
            guard seenBranches.insert(branch).inserted else { continue }
            uniqueBranches.append(branch)
        }

        return uniqueBranches
    }

    func updateSelectedBaseBranch(repositoryID: String, selectedBaseBranch: String) {
        guard let repositoryIndex = repositories.firstIndex(where: { $0.id == repositoryID }) else { return }
        repositories[repositoryIndex].selectedBaseBranch = selectedBaseBranch
    }
}
