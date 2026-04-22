import Foundation

extension FeatureSessionService {
    static func cleanupRepositories(
        _ repositories: [SessionRepository],
        sessionName: String,
        sessionRootPath: String,
        dependencies: FeatureSessionServiceDependencies
    ) async -> FeatureSessionCleanupReport {
        var issues: [FeatureSessionCleanupIssue] = []

        for repository in repositories {
            do {
                try await dependencies.gitWorktreeClient.removeWorktree(
                    repository.sourcePath,
                    repository.sessionPath,
                    true
                )
            } catch {
                issues.append(FeatureSessionCleanupIssue(
                    scope: repository.name,
                    action: "remove worktree",
                    message: error.localizedDescription
                ))
            }

            do {
                try await dependencies.gitWorktreeClient.deleteBranch(
                    repository.sourcePath,
                    repository.sessionBranch
                )
            } catch {
                issues.append(FeatureSessionCleanupIssue(
                    scope: repository.name,
                    action: "delete branch",
                    message: error.localizedDescription
                ))
            }

            do {
                try dependencies.fileClient.removeItemAtPath(repository.sessionPath)
            } catch {
                let standardizedPath = URL(fileURLWithPath: repository.sessionPath)
                    .standardizedFileURL
                    .path(percentEncoded: false)
                if dependencies.fileClient.fileExists(standardizedPath) {
                    issues.append(FeatureSessionCleanupIssue(
                        scope: repository.name,
                        action: "remove session folder",
                        message: error.localizedDescription
                    ))
                }
            }
        }

        do {
            try dependencies.fileClient.removeItemAtPath(sessionRootPath)
        } catch {
            let standardizedPath = URL(fileURLWithPath: sessionRootPath)
                .standardizedFileURL
                .path(percentEncoded: false)
            if dependencies.fileClient.fileExists(standardizedPath) {
                issues.append(FeatureSessionCleanupIssue(
                    scope: sessionName,
                    action: "remove session root folder",
                    message: error.localizedDescription
                ))
            }
        }

        return FeatureSessionCleanupReport(sessionName: sessionName, issues: issues)
    }

    static func validateSessionName(
        _ sessionName: String,
        repositories: [FeatureSessionRepositorySelection],
        dependencies: FeatureSessionServiceDependencies
    ) async throws {
        guard !sessionName.isEmpty else {
            throw FeatureSessionError.invalidSessionName
        }

        let validationPath = repositories.first?.path
            ?? FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let isValidBranchName = await dependencies.gitRepositoryClient.isValidBranchName(
            sessionName,
            validationPath
        )
        guard isValidBranchName else {
            throw FeatureSessionError.invalidSessionName
        }
    }

    static func validateRepositoryNames(_ repositories: [FeatureSessionRepositorySelection]) throws {
        let uniqueNames = Set(repositories.map(\.name))
        guard uniqueNames.count == repositories.count else {
            throw FeatureSessionError.duplicateRepositoryNames
        }
    }

    static func validateRepositoriesSelected(_ repositories: [FeatureSessionRepositorySelection]) throws {
        guard !repositories.isEmpty else {
            throw FeatureSessionError.noRepositoriesSelected
        }
    }

    static func validateRepositoriesForCreation(
        _ repositories: [FeatureSessionRepositorySelection],
        sessionName: String,
        sessionRoot: URL,
        dependencies: FeatureSessionServiceDependencies
    ) async throws -> [ValidatedFeatureSessionRepository] {
        var validatedRepositories: [ValidatedFeatureSessionRepository] = []

        for repository in repositories {
            let standardizedPath = URL(fileURLWithPath: repository.path).standardizedFileURL.path(percentEncoded: false)
            guard await dependencies.gitWorktreeClient.isGitRepository(standardizedPath) else {
                throw FeatureSessionError.notGitRepository(standardizedPath)
            }

            let currentBranch: String
            do {
                currentBranch = try await dependencies.gitRepositoryClient.currentBranch(standardizedPath)
            } catch {
                throw FeatureSessionError.repositoryOperationFailed(repository.name, error.localizedDescription)
            }

            guard currentBranch != "HEAD" else {
                throw FeatureSessionError.detachedHead(standardizedPath)
            }

            let existingBranches: [String]
            do {
                existingBranches = try await dependencies.gitRepositoryClient.listBranches(standardizedPath)
            } catch {
                throw FeatureSessionError.repositoryOperationFailed(repository.name, error.localizedDescription)
            }

            guard !existingBranches.contains(sessionName) else {
                throw FeatureSessionError.sessionBranchAlreadyExists(standardizedPath, sessionName)
            }

            let sessionPath = sessionRoot.appendingPathComponent(repository.name, isDirectory: true).path
            guard !dependencies.fileClient.fileExists(sessionPath) else {
                throw FeatureSessionError.sessionRepositoryPathAlreadyExists(sessionPath)
            }

            validatedRepositories.append(ValidatedFeatureSessionRepository(
                name: repository.name,
                path: standardizedPath,
                sessionPath: sessionPath,
                currentBranch: currentBranch
            ))
        }

        return validatedRepositories
    }

    static func uniquePathsPreservingOrder(_ paths: [String]) -> [String] {
        var seenPaths: Set<String> = []
        var uniquePaths: [String] = []

        for path in paths {
            let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path(percentEncoded: false)
            guard seenPaths.insert(standardizedPath).inserted else { continue }
            uniquePaths.append(standardizedPath)
        }

        return uniquePaths
    }
}
