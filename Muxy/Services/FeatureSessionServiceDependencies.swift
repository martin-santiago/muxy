import Foundation

struct FeatureSessionFileClient {
    let fileExists: @Sendable (String) -> Bool
    let createDirectory: @Sendable (URL, Bool, [FileAttributeKey: Any]?) throws -> Void
    let removeItemAtPath: @Sendable (String) throws -> Void
    let copyUntrackedAndIgnored: @Sendable (_ sourcePath: String, _ destinationPath: String) async throws -> Void

    static let live = FeatureSessionFileClient(
        fileExists: { FileManager.default.fileExists(atPath: $0) },
        createDirectory: { url, withIntermediateDirectories, attributes in
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: withIntermediateDirectories,
                attributes: attributes
            )
        },
        removeItemAtPath: { try FileManager.default.removeItem(atPath: $0) },
        copyUntrackedAndIgnored: { sourcePath, destinationPath in
            try await FeatureSessionFileCopy.copyUntrackedAndIgnored(
                from: sourcePath,
                to: destinationPath
            )
        }
    )
}

struct FeatureSessionGitRepositoryClient {
    let currentBranch: @Sendable (String) async throws -> String
    let isValidBranchName: @Sendable (String, String) async -> Bool
    let listBranches: @Sendable (String) async throws -> [String]
    let pull: @Sendable (String) async throws -> Void

    static let live = FeatureSessionGitRepositoryClient(
        currentBranch: { try await GitRepositoryService().currentBranch(repoPath: $0) },
        isValidBranchName: { await GitRepositoryService().isValidBranchName($0, workingDirectory: $1) },
        listBranches: { try await GitRepositoryService().listBranches(repoPath: $0) },
        pull: { try await GitRepositoryService().pull(repoPath: $0) }
    )
}

struct FeatureSessionGitWorktreeClient {
    let isGitRepository: @Sendable (String) async -> Bool
    let addWorktree: @Sendable (String, String, String, Bool, String?) async throws -> Void
    let removeWorktree: @Sendable (String, String, Bool) async throws -> Void
    let deleteBranch: @Sendable (String, String) async throws -> Void

    static let live = FeatureSessionGitWorktreeClient(
        isGitRepository: { await GitWorktreeService.shared.isGitRepository($0) },
        addWorktree: {
            try await GitWorktreeService.shared.addWorktree(
                repoPath: $0,
                path: $1,
                branch: $2,
                createBranch: $3,
                startPoint: $4
            )
        },
        removeWorktree: { try await GitWorktreeService.shared.removeWorktree(repoPath: $0, path: $1, force: $2) },
        deleteBranch: { try await GitWorktreeService.shared.deleteBranch(repoPath: $0, branch: $1) }
    )
}

struct FeatureSessionServiceDependencies {
    let fileClient: FeatureSessionFileClient
    let gitRepositoryClient: FeatureSessionGitRepositoryClient
    let gitWorktreeClient: FeatureSessionGitWorktreeClient
    let sessionRoot: @Sendable (String) -> URL

    static let live = FeatureSessionServiceDependencies(
        fileClient: .live,
        gitRepositoryClient: .live,
        gitWorktreeClient: .live,
        sessionRoot: { MuxyFileStorage.sessionRoot(for: $0) }
    )
}
