import Foundation

enum FeatureSessionCreationEvent: Equatable {
    case preparingSessionDirectory
    case validatingRepository(name: String)
    case pullingRepository(name: String)
    case creatingWorktree(name: String)
    case copyingHiddenFiles(name: String)
    case finishedRepository(name: String)
    case rollingBack

    var userFacingDescription: String {
        switch self {
        case .preparingSessionDirectory:
            "Preparing session directory…"
        case let .validatingRepository(name):
            "Validating \(name)…"
        case let .pullingRepository(name):
            "Pulling \(name)…"
        case let .creatingWorktree(name):
            "Creating worktree for \(name)…"
        case let .copyingHiddenFiles(name):
            "Copying hidden files for \(name)…"
        case let .finishedRepository(name):
            "Finished \(name)"
        case .rollingBack:
            "Rolling back…"
        }
    }
}

typealias FeatureSessionCreationProgressHandler = @Sendable @MainActor (FeatureSessionCreationEvent) -> Void
