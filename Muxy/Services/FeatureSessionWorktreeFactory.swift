import CryptoKit
import Foundation

enum FeatureSessionWorktreeFactory {
    static func worktrees(for project: Project) -> [Worktree]? {
        guard let featureSession = project.featureSession,
              !featureSession.repositories.isEmpty
        else {
            return nil
        }

        let rootWorktree = Worktree(
            id: rootWorktreeID(for: featureSession),
            name: project.name,
            path: featureSession.rootPath,
            branch: nil,
            source: .featureSessionRoot,
            isPrimary: true,
            createdAt: project.createdAt
        )

        let repositoryWorktrees = featureSession.repositories.enumerated().map { index, repository in
            Worktree(
                id: repositoryWorktreeID(for: repository),
                name: repository.name,
                path: repository.sessionPath,
                branch: repository.sessionBranch,
                source: .featureSession,
                isPrimary: false,
                createdAt: project.createdAt.addingTimeInterval(Double(index + 1))
            )
        }

        return [rootWorktree] + repositoryWorktrees
    }

    private static func rootWorktreeID(for featureSession: FeatureSession) -> UUID {
        let canonicalPath = URL(fileURLWithPath: featureSession.rootPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path(percentEncoded: false)
        return deterministicUUID(from: canonicalPath + "#ROOT")
    }

    private static func repositoryWorktreeID(for repository: SessionRepository) -> UUID {
        let canonicalPath = URL(fileURLWithPath: repository.sessionPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path(percentEncoded: false)
        return deterministicUUID(from: canonicalPath)
    }

    private static func deterministicUUID(from input: String) -> UUID {
        let digest = SHA256.hash(data: Data(input.utf8))
        let bytes = Array(digest.prefix(16))
        let uuidBytes: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuidBytes)
    }
}
