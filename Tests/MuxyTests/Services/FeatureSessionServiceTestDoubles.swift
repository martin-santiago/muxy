import Foundation

@testable import Muxy

final class FeatureSessionFileClientStub: @unchecked Sendable {
    var existingPaths: Set<String>
    var removedPaths: [String] = []
    var copyUntrackedAndIgnoredCalls: [(source: String, destination: String)] = []
    private let removeFailuresByPath: [String: String]
    private let copyFailuresBySourcePath: [String: String]

    init(
        existingPaths: Set<String> = [],
        removeFailuresByPath: [String: String] = [:],
        copyFailuresBySourcePath: [String: String] = [:]
    ) {
        self.existingPaths = existingPaths
        self.removeFailuresByPath = removeFailuresByPath
        self.copyFailuresBySourcePath = copyFailuresBySourcePath
    }

    var client: FeatureSessionFileClient {
        FeatureSessionFileClient(
            fileExists: { self.existingPaths.contains($0) },
            createDirectory: { url, _, _ in
                self.existingPaths.insert(url.path)
            },
            removeItemAtPath: { path in
                self.removedPaths.append(path)
                if let message = self.removeFailuresByPath[path], self.existingPaths.contains(path) {
                    throw FeatureSessionStubError(message: message)
                }
                self.existingPaths.remove(path)
            },
            copyUntrackedAndIgnored: { sourcePath, destinationPath in
                self.copyUntrackedAndIgnoredCalls.append((sourcePath, destinationPath))
                if let message = self.copyFailuresBySourcePath[sourcePath] {
                    throw FeatureSessionStubError(message: message)
                }
            }
        )
    }
}

final class FeatureSessionGitRepositoryClientStub: @unchecked Sendable {
    private let currentBranchesByPath: [String: String]
    private let branchesByPath: [String: [String]]
    private let pullFailuresByPath: [String: String]

    init(
        currentBranchesByPath: [String: String] = [:],
        branchesByPath: [String: [String]] = [:],
        pullFailuresByPath: [String: String] = [:]
    ) {
        self.currentBranchesByPath = currentBranchesByPath
        self.branchesByPath = branchesByPath
        self.pullFailuresByPath = pullFailuresByPath
    }

    func client(isValidBranchName: Bool) -> FeatureSessionGitRepositoryClient {
        FeatureSessionGitRepositoryClient(
            currentBranch: { path in
                try self.currentBranch(path: path)
            },
            isValidBranchName: { _, _ in isValidBranchName },
            listBranches: { path in
                try self.listBranches(path: path)
            },
            pull: { path in
                try self.pull(path: path)
            }
        )
    }

    private func currentBranch(path: String) throws -> String {
        currentBranchesByPath[path] ?? "main"
    }

    private func listBranches(path: String) throws -> [String] {
        if let branches = branchesByPath[path] {
            return branches
        }
        return [try currentBranch(path: path)]
    }

    private func pull(path: String) throws {
        if let message = pullFailuresByPath[path] {
            throw FeatureSessionStubError(message: message)
        }
    }
}

final class FeatureSessionGitWorktreeClientStub: @unchecked Sendable {
    private let gitRepositoryPaths: Set<String>?
    private let addFailuresByPath: [String: String]
    private let removeFailuresByPath: [String: String]
    private let deleteFailuresByBranch: [String: String]
    private var addWorktreeCallsStore: [(repoPath: String, path: String, branch: String, createBranch: Bool, startPoint: String?)] = []
    private var removedPathsStore: [String] = []
    private var deletedBranchesStore: [String] = []

    init(
        gitRepositoryPaths: Set<String>? = nil,
        addFailuresByPath: [String: String] = [:],
        removeFailuresByPath: [String: String] = [:],
        deleteFailuresByBranch: [String: String] = [:]
    ) {
        self.gitRepositoryPaths = gitRepositoryPaths
        self.addFailuresByPath = addFailuresByPath
        self.removeFailuresByPath = removeFailuresByPath
        self.deleteFailuresByBranch = deleteFailuresByBranch
    }

    var client: FeatureSessionGitWorktreeClient {
        FeatureSessionGitWorktreeClient(
            isGitRepository: { path in
                self.isGitRepository(path: path)
            },
            addWorktree: { repoPath, path, branch, createBranch, startPoint in
                try self.addWorktree(
                    repoPath: repoPath,
                    path: path,
                    branch: branch,
                    createBranch: createBranch,
                    startPoint: startPoint
                )
            },
            removeWorktree: { _, path, _ in
                try self.removeWorktree(path: path)
            },
            deleteBranch: { _, branch in
                try self.deleteBranch(branch: branch)
            }
        )
    }

    func removedWorktreePaths() -> [String] {
        removedPathsStore
    }

    func addWorktreeCalls() -> [(repoPath: String, path: String, branch: String, createBranch: Bool, startPoint: String?)] {
        addWorktreeCallsStore
    }

    func deletedBranches() -> [String] {
        deletedBranchesStore
    }

    private func isGitRepository(path: String) -> Bool {
        guard let gitRepositoryPaths else { return true }
        return gitRepositoryPaths.contains(path)
    }

    private func addWorktree(
        repoPath: String,
        path: String,
        branch: String,
        createBranch: Bool,
        startPoint: String?
    ) throws {
        addWorktreeCallsStore.append((repoPath, path, branch, createBranch, startPoint))
        if let message = addFailuresByPath[path] {
            throw FeatureSessionStubError(message: message)
        }
    }

    private func removeWorktree(path: String) throws {
        removedPathsStore.append(path)
        if let message = removeFailuresByPath[path] {
            throw FeatureSessionStubError(message: message)
        }
    }

    private func deleteBranch(branch: String) throws {
        deletedBranchesStore.append(branch)
        if let message = deleteFailuresByBranch[branch] {
            throw FeatureSessionStubError(message: message)
        }
    }
}

struct FeatureSessionStubError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
