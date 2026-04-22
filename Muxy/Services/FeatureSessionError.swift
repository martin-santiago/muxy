import Foundation

enum FeatureSessionError: LocalizedError {
    case invalidSessionName
    case noRepositoriesSelected
    case sessionAlreadyExists
    case notFeatureSessionProject
    case duplicateRepositoryNames
    case detachedHead(String)
    case sessionBranchAlreadyExists(String, String)
    case sessionRepositoryPathAlreadyExists(String)
    case selectedBaseBranchMissing(String, String)
    case repositoriesAlreadyInSession([String])
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
        case .notFeatureSessionProject:
            "This project is not a feature session."
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
        case let .selectedBaseBranchMissing(repositoryName, branch):
            "\(repositoryName) does not have a branch named \(branch)."
        case let .repositoriesAlreadyInSession(repositoryNames):
            "These repositories are already in the session: \(repositoryNames.joined(separator: ", "))."
        case let .repositoryOperationFailed(repositoryName, message):
            "\(repositoryName): \(message.trimmingCharacters(in: .whitespacesAndNewlines))"
        case let .cleanupFailed(message, cleanupSummary):
            message + "\n\nCleanup was incomplete:\n" + cleanupSummary
        }
    }
}
