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
    var baseBranch: String
    var sessionBranch: String
    var kind: SessionRepositoryKind

    init(
        id: UUID = UUID(),
        name: String,
        sourcePath: String,
        sessionPath: String,
        originalBranch: String,
        baseBranch: String,
        sessionBranch: String,
        kind: SessionRepositoryKind = .git
    ) {
        self.id = id
        self.name = name
        self.sourcePath = sourcePath
        self.sessionPath = sessionPath
        self.originalBranch = originalBranch
        self.baseBranch = baseBranch
        self.sessionBranch = sessionBranch
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case sourcePath
        case sessionPath
        case originalBranch
        case baseBranch
        case sessionBranch
        case kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sourcePath = try container.decode(String.self, forKey: .sourcePath)
        sessionPath = try container.decode(String.self, forKey: .sessionPath)
        originalBranch = try container.decode(String.self, forKey: .originalBranch)
        baseBranch = try container.decodeIfPresent(String.self, forKey: .baseBranch) ?? originalBranch
        sessionBranch = try container.decode(String.self, forKey: .sessionBranch)
        kind = try container.decode(SessionRepositoryKind.self, forKey: .kind)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(sourcePath, forKey: .sourcePath)
        try container.encode(sessionPath, forKey: .sessionPath)
        try container.encode(originalBranch, forKey: .originalBranch)
        try container.encode(baseBranch, forKey: .baseBranch)
        try container.encode(sessionBranch, forKey: .sessionBranch)
        try container.encode(kind, forKey: .kind)
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
