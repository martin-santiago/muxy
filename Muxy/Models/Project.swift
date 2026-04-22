import Foundation

struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var sortOrder: Int
    var createdAt: Date
    var icon: String?
    var logo: String?
    var iconColor: String?
    var mode: ProjectMode
    var featureSession: FeatureSession?

    init(
        name: String,
        path: String,
        sortOrder: Int = 0,
        mode: ProjectMode = .legacy,
        featureSession: FeatureSession? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.icon = nil
        self.logo = nil
        self.iconColor = nil
        self.mode = mode
        self.featureSession = featureSession
    }

    var pathExists: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    var isFeatureSession: Bool {
        mode == .featureSession && featureSession != nil
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case sortOrder
        case createdAt
        case icon
        case logo
        case iconColor
        case mode
        case featureSession
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        logo = try container.decodeIfPresent(String.self, forKey: .logo)
        iconColor = try container.decodeIfPresent(String.self, forKey: .iconColor)
        mode = try container.decodeIfPresent(ProjectMode.self, forKey: .mode) ?? .legacy
        featureSession = try container.decodeIfPresent(FeatureSession.self, forKey: .featureSession)
    }
}
