import CryptoKit
import Foundation

enum FeatureSessionWorktreeFactory {
    static func worktrees(for project: Project) -> [Worktree]? {
        guard let featureSession = project.featureSession,
              !featureSession.repositories.isEmpty
        else {
            return nil
        }

        let primaryRepositoryID = featureSession.primaryRepositoryID
            ?? featureSession.repositories.first?.id

        return featureSession.repositories.enumerated().map { index, repository in
            Worktree(
                id: worktreeID(for: repository),
                name: repository.name,
                path: repository.sessionPath,
                branch: repository.sessionBranch,
                source: .featureSession,
                isPrimary: repository.id == primaryRepositoryID ||
                    (primaryRepositoryID == nil && index == 0),
                createdAt: project.createdAt.addingTimeInterval(Double(index))
            )
        }
    }

    private static func worktreeID(for repository: SessionRepository) -> UUID {
        let canonicalPath = URL(fileURLWithPath: repository.sessionPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path(percentEncoded: false)
        let digest = SHA256.hash(data: Data(canonicalPath.utf8))
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
