import Foundation
import os

private let logger = Logger(subsystem: "app.muxy", category: "FeatureSessionService")

enum FeatureSessionService {
    static func inspectRepositories(paths: [String]) async throws -> [FeatureSessionRepositorySelection] {
        try await inspectRepositories(paths: paths, dependencies: .live)
    }

    static func inspectRepositories(
        paths: [String],
        dependencies: FeatureSessionServiceDependencies
    ) async throws -> [FeatureSessionRepositorySelection] {
        let uniquePaths = uniquePathsPreservingOrder(paths)
        var selections: [FeatureSessionRepositorySelection] = []
        for path in uniquePaths {
            let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path(percentEncoded: false)
            guard await dependencies.gitWorktreeClient.isGitRepository(standardizedPath) else {
                throw FeatureSessionError.notGitRepository(standardizedPath)
            }
            let currentBranch = try await dependencies.gitRepositoryClient.currentBranch(standardizedPath)
            guard currentBranch != "HEAD" else {
                throw FeatureSessionError.detachedHead(standardizedPath)
            }
            selections.append(FeatureSessionRepositorySelection(path: standardizedPath, currentBranch: currentBranch))
        }
        return selections
    }

    static func createSession(
        name: String,
        repositories: [FeatureSessionRepositorySelection],
        sortOrder: Int
    ) async throws -> Project {
        try await createSession(
            name: name,
            repositories: repositories,
            sortOrder: sortOrder,
            dependencies: .live
        )
    }

    static func createSession(
        name: String,
        repositories: [FeatureSessionRepositorySelection],
        sortOrder: Int,
        dependencies: FeatureSessionServiceDependencies
    ) async throws -> Project {
        let sessionName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try validateRepositoriesSelected(repositories)
        try await validateSessionName(sessionName, repositories: repositories, dependencies: dependencies)
        try validateRepositoryNames(repositories)

        let sessionRoot = dependencies.sessionRoot(sessionName)
        guard !dependencies.fileClient.fileExists(sessionRoot.path) else {
            throw FeatureSessionError.sessionAlreadyExists
        }

        let validatedRepositories = try await validateRepositoriesForCreation(
            repositories,
            sessionName: sessionName,
            sessionRoot: sessionRoot,
            dependencies: dependencies
        )

        try dependencies.fileClient.createDirectory(
            at: sessionRoot,
            true,
            [.posixPermissions: 0o700]
        )

        var createdRepositories: [SessionRepository] = []

        do {
            for repository in validatedRepositories {
                do {
                    try await dependencies.gitRepositoryClient.pull(repository.path)
                } catch {
                    throw FeatureSessionError.repositoryOperationFailed(
                        repository.name,
                        error.localizedDescription
                    )
                }

                do {
                    try await dependencies.gitWorktreeClient.addWorktree(
                        repository.path,
                        repository.sessionPath,
                        sessionName,
                        true
                    )
                } catch {
                    throw FeatureSessionError.repositoryOperationFailed(
                        repository.name,
                        error.localizedDescription
                    )
                }

                createdRepositories.append(SessionRepository(
                    name: repository.name,
                    sourcePath: repository.path,
                    sessionPath: repository.sessionPath,
                    originalBranch: repository.currentBranch,
                    sessionBranch: sessionName
                ))
            }
        } catch {
            let cleanupReport = await cleanupRepositories(
                createdRepositories,
                sessionName: sessionName,
                sessionRootPath: sessionRoot.path,
                dependencies: dependencies
            )
            if cleanupReport.hasIssues {
                logger.error("Feature session cleanup incomplete for \(sessionName): \(cleanupReport.alertMessage)")
                throw FeatureSessionError.cleanupFailed(error.localizedDescription, cleanupReport.alertMessage)
            }
            throw error
        }

        let featureSession = FeatureSession(
            rootPath: sessionRoot.path,
            repositories: createdRepositories,
            primaryRepositoryID: createdRepositories.first?.id
        )
        return Project(
            name: sessionName,
            path: sessionRoot.path,
            sortOrder: sortOrder,
            mode: .featureSession,
            featureSession: featureSession
        )
    }

    static func deleteSession(project: Project) async -> FeatureSessionCleanupReport {
        await deleteSession(project: project, dependencies: .live)
    }

    static func deleteSession(
        project: Project,
        dependencies: FeatureSessionServiceDependencies
    ) async -> FeatureSessionCleanupReport {
        guard let featureSession = project.featureSession else {
            return FeatureSessionCleanupReport(sessionName: project.name, issues: [])
        }
        let cleanupReport = await cleanupRepositories(
            featureSession.repositories,
            sessionName: project.name,
            sessionRootPath: featureSession.rootPath,
            dependencies: dependencies
        )
        if cleanupReport.hasIssues {
            logger.error("Feature session cleanup incomplete for \(project.name): \(cleanupReport.alertMessage)")
        }
        return cleanupReport
    }

}
