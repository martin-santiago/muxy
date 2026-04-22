import Foundation

enum SessionRepositoryKind: String, Codable, Hashable {
    case git
}

struct SessionRepository: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var sourcePath: String
    var sessionPath: String
    var originalBranch: String
    var sessionBranch: String
    var kind: SessionRepositoryKind

    init(
        id: UUID = UUID(),
        name: String,
        sourcePath: String,
        sessionPath: String,
        originalBranch: String,
        sessionBranch: String,
        kind: SessionRepositoryKind = .git
    ) {
        self.id = id
        self.name = name
        self.sourcePath = sourcePath
        self.sessionPath = sessionPath
        self.originalBranch = originalBranch
        self.sessionBranch = sessionBranch
        self.kind = kind
    }
}

struct FeatureSession: Codable, Hashable {
    var rootPath: String
    var repositories: [SessionRepository]
    var primaryRepositoryID: UUID?

    init(
        rootPath: String,
        repositories: [SessionRepository],
        primaryRepositoryID: UUID? = nil
    ) {
        self.rootPath = rootPath
        self.repositories = repositories
        self.primaryRepositoryID = primaryRepositoryID
    }
}

enum ProjectMode: String, Codable, Hashable {
    case legacy
    case featureSession
}
