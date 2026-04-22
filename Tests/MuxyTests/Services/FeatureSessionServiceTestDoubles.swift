import Foundation

@testable import Muxy

final class FeatureSessionFileClientStub: @unchecked Sendable {
    var existingPaths: Set<String>
    var removedPaths: [String] = []
    private let removeFailuresByPath: [String: String]

    init(existingPaths: Set<String> = [], removeFailuresByPath: [String: String] = [:]) {
        self.existingPaths = existingPaths
        self.removeFailuresByPath = removeFailuresByPath
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
        branchesByPath[path] ?? []
    }

    private func pull(path: String) throws {
        if let message = pullFailuresByPath[path] {
            throw FeatureSessionStubError(message: message)
        }
    }
}

final class FeatureSessionGitWorktreeClientStub: @unchecked Sendable {
    private let gitRepositoryPaths: Set<String>
    private let addFailuresByPath: [String: String]
    private let removeFailuresByPath: [String: String]
    private let deleteFailuresByBranch: [String: String]
    private var removedPathsStore: [String] = []
    private var deletedBranchesStore: [String] = []

    init(
        gitRepositoryPaths: Set<String> = [],
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
            addWorktree: { _, path, _, _ in
                try self.addWorktree(path: path)
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

    func deletedBranches() -> [String] {
        deletedBranchesStore
    }

    private func isGitRepository(path: String) -> Bool {
        gitRepositoryPaths.isEmpty || gitRepositoryPaths.contains(path)
    }

    private func addWorktree(path: String) throws {
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
