import Foundation

enum FeatureSessionError: LocalizedError {
    case invalidSessionName
    case noRepositoriesSelected
    case sessionAlreadyExists
    case duplicateRepositoryNames
    case detachedHead(String)
    case sessionBranchAlreadyExists(String, String)
    case sessionRepositoryPathAlreadyExists(String)
    case notGitRepository(String)
    case repositoryOperationFailed(String, String)
    case cleanupFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .invalidSessionName:
            "Use a session name that is also a valid Git branch name."
        case .noRepositoriesSelected:
            "Select at least one Git repository."
        case .sessionAlreadyExists:
            "A session with that name already exists."
        case let .notGitRepository(path):
            "\(URL(fileURLWithPath: path).lastPathComponent) is not a Git repository."
        case .duplicateRepositoryNames:
            "Selected repositories must have unique folder names."
        case let .detachedHead(path):
            "\(URL(fileURLWithPath: path).lastPathComponent) is on a detached HEAD. Check out a branch first."
        case let .sessionBranchAlreadyExists(path, branch):
            "\(URL(fileURLWithPath: path).lastPathComponent) already has a branch named \(branch)."
        case let .sessionRepositoryPathAlreadyExists(path):
            "A session repository folder already exists at \(path)."
        case let .repositoryOperationFailed(repositoryName, message):
            "\(repositoryName): \(message.trimmingCharacters(in: .whitespacesAndNewlines))"
        case let .cleanupFailed(message, cleanupSummary):
            message + "\n\nCleanup was incomplete:\n" + cleanupSummary
        }
    }
}
