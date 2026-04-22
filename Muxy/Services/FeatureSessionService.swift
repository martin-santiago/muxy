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
        sortOrder: Int,
        copyHiddenAndIgnoredFiles: Bool = false,
        onProgress: @escaping FeatureSessionCreationProgressHandler = { _ in }
    ) async throws -> Project {
        try await createSession(
            name: name,
            repositories: repositories,
            sortOrder: sortOrder,
            copyHiddenAndIgnoredFiles: copyHiddenAndIgnoredFiles,
            onProgress: onProgress,
            dependencies: .live
        )
    }

    static func createSession(
        name: String,
        repositories: [FeatureSessionRepositorySelection],
        sortOrder: Int,
        copyHiddenAndIgnoredFiles: Bool = false,
        onProgress: @escaping FeatureSessionCreationProgressHandler = { _ in },
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
            dependencies: dependencies,
            onProgress: onProgress
        )

        await onProgress(.preparingSessionDirectory)
        try dependencies.fileClient.createDirectory(
            sessionRoot,
            true,
            [.posixPermissions: 0o700]
        )

        do {
            let createdRepositories = try await createRepositories(
                validatedRepositories,
                sessionName: sessionName,
                copyHiddenAndIgnoredFiles: copyHiddenAndIgnoredFiles,
                onProgress: onProgress,
                dependencies: dependencies
            )

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
        } catch {
            await onProgress(.rollingBack)
            let cleanupReport = await cleanupRepositories(
                [],
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
    }

    static func addRepositories(
        to project: Project,
        repositories: [FeatureSessionRepositorySelection],
        copyHiddenAndIgnoredFiles: Bool = false,
        onProgress: @escaping FeatureSessionCreationProgressHandler = { _ in }
    ) async throws -> Project {
        try await addRepositories(
            to: project,
            repositories: repositories,
            copyHiddenAndIgnoredFiles: copyHiddenAndIgnoredFiles,
            onProgress: onProgress,
            dependencies: .live
        )
    }

    static func addRepositories(
        to project: Project,
        repositories: [FeatureSessionRepositorySelection],
        copyHiddenAndIgnoredFiles: Bool = false,
        onProgress: @escaping FeatureSessionCreationProgressHandler = { _ in },
        dependencies: FeatureSessionServiceDependencies
    ) async throws -> Project {
        guard let featureSession = project.featureSession else {
            throw FeatureSessionError.notFeatureSessionProject
        }

        try validateRepositoriesSelected(repositories)
        try validateRepositoryNames(repositories)

        let validatedRepositories = try await validateRepositoriesForAppend(
            repositories,
            sessionName: project.name,
            sessionRoot: URL(fileURLWithPath: featureSession.rootPath, isDirectory: true),
            existingRepositories: featureSession.repositories,
            dependencies: dependencies,
            onProgress: onProgress
        )

        var createdRepositories: [SessionRepository] = []

        do {
            createdRepositories = try await createRepositories(
                validatedRepositories,
                sessionName: project.name,
                copyHiddenAndIgnoredFiles: copyHiddenAndIgnoredFiles,
                onProgress: onProgress,
                dependencies: dependencies
            )
        } catch {
            await onProgress(.rollingBack)
            let cleanupReport = await cleanupRepositories(
                createdRepositories,
                sessionName: project.name,
                sessionRootPath: featureSession.rootPath,
                dependencies: dependencies,
                removeSessionRoot: false
            )
            if cleanupReport.hasIssues {
                logger.error("Feature session cleanup incomplete for \(project.name): \(cleanupReport.alertMessage)")
                throw FeatureSessionError.cleanupFailed(error.localizedDescription, cleanupReport.alertMessage)
            }
            throw error
        }

        var updatedProject = project
        updatedProject.featureSession = FeatureSession(
            rootPath: featureSession.rootPath,
            repositories: featureSession.repositories + createdRepositories,
            primaryRepositoryID: featureSession.primaryRepositoryID
        )
        return updatedProject
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

    private static func createRepositories(
        _ validatedRepositories: [ValidatedFeatureSessionRepository],
        sessionName: String,
        copyHiddenAndIgnoredFiles: Bool,
        onProgress: @escaping FeatureSessionCreationProgressHandler,
        dependencies: FeatureSessionServiceDependencies
    ) async throws -> [SessionRepository] {
        var createdRepositories: [SessionRepository] = []

        do {
            for validatedRepository in validatedRepositories {
                await onProgress(.pullingRepository(name: validatedRepository.name))
                do {
                    try await dependencies.gitRepositoryClient.pull(validatedRepository.path)
                } catch {
                    throw FeatureSessionError.repositoryOperationFailed(
                        validatedRepository.name,
                        error.localizedDescription
                    )
                }

                await onProgress(.creatingWorktree(name: validatedRepository.name))
                do {
                    try await dependencies.gitWorktreeClient.addWorktree(
                        validatedRepository.path,
                        validatedRepository.sessionPath,
                        sessionName,
                        true,
                        validatedRepository.baseBranch
                    )
                } catch {
                    throw FeatureSessionError.repositoryOperationFailed(
                        validatedRepository.name,
                        error.localizedDescription
                    )
                }

                let createdRepository = SessionRepository(
                    name: validatedRepository.name,
                    sourcePath: validatedRepository.path,
                    sessionPath: validatedRepository.sessionPath,
                    originalBranch: validatedRepository.currentBranch,
                    baseBranch: validatedRepository.baseBranch,
                    sessionBranch: sessionName
                )
                createdRepositories.append(createdRepository)

                if copyHiddenAndIgnoredFiles {
                    await onProgress(.copyingHiddenFiles(name: validatedRepository.name))
                    do {
                        try await dependencies.fileClient.copyUntrackedAndIgnored(
                            validatedRepository.path,
                            validatedRepository.sessionPath
                        )
                    } catch {
                        throw FeatureSessionError.repositoryOperationFailed(
                            validatedRepository.name,
                            error.localizedDescription
                        )
                    }
                }

                await onProgress(.finishedRepository(name: validatedRepository.name))
            }

            return createdRepositories
        } catch {
            let cleanupReport = await cleanupRepositories(
                createdRepositories,
                sessionName: sessionName,
                sessionRootPath: validatedRepositories.first.map {
                    URL(fileURLWithPath: $0.sessionPath).deletingLastPathComponent().path(percentEncoded: false)
                } ?? "",
                dependencies: dependencies,
                removeSessionRoot: false
            )
            if cleanupReport.hasIssues {
                logger.error("Feature session cleanup incomplete for \(sessionName): \(cleanupReport.alertMessage)")
                throw FeatureSessionError.cleanupFailed(error.localizedDescription, cleanupReport.alertMessage)
            }
            throw error
        }
    }
}
