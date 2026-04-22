import SwiftUI

extension Sidebar {
    @MainActor
    func appendRepositories(
        to project: Project,
        repositories: [FeatureSessionRepositorySelection],
        copyHiddenAndIgnoredFiles: Bool,
        onProgress: @escaping FeatureSessionCreationProgressHandler
    ) async throws {
        let preferredWorktreeID = appState.activeWorktreeID[project.id]
        let updatedProject = try await FeatureSessionService.addRepositories(
            to: project,
            repositories: repositories,
            copyHiddenAndIgnoredFiles: copyHiddenAndIgnoredFiles,
            onProgress: onProgress
        )
        guard let updatedFeatureSession = updatedProject.featureSession else { return }

        projectStore.updateFeatureSession(id: project.id, featureSession: updatedFeatureSession)
        worktreeStore.ensurePrimary(for: updatedProject)

        guard appState.activeProjectID == project.id,
              let preferredWorktree = worktreeStore.preferred(for: project.id, matching: preferredWorktreeID)
        else {
            return
        }
        appState.selectProject(updatedProject, worktree: preferredWorktree)
    }
}
