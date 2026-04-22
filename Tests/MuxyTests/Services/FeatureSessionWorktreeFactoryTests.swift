import Foundation
import Testing

@testable import Muxy

@Suite("FeatureSessionWorktreeFactory")
struct FeatureSessionWorktreeFactoryTests {
    @Test("worktrees prepends root worktree at position 0")
    func rootWorktreeIsFirst() throws {
        let project = makeFeatureSessionProject(repositoryNames: ["api", "web"])

        let worktrees = try #require(FeatureSessionWorktreeFactory.worktrees(for: project))

        #expect(worktrees.count == 3)
        #expect(worktrees[0].source == .featureSessionRoot)
        #expect(worktrees[0].isPrimary)
        #expect(worktrees[0].canBeRemoved == false)
        #expect(worktrees[0].name == project.name)
        #expect(worktrees[0].path == project.featureSession?.rootPath)
        #expect(worktrees[0].branch == nil)
    }

    @Test("repository worktrees are not primary when root is present")
    func repositoryWorktreesAreNotPrimary() throws {
        let project = makeFeatureSessionProject(repositoryNames: ["api"])

        let worktrees = try #require(FeatureSessionWorktreeFactory.worktrees(for: project))

        #expect(worktrees.count == 2)
        #expect(worktrees[1].source == .featureSession)
        #expect(worktrees[1].isPrimary == false)
    }

    @Test("root worktree id is deterministic across factory calls")
    func rootWorktreeIDIsDeterministic() throws {
        let project = makeFeatureSessionProject(repositoryNames: ["api"])

        let firstWorktrees = try #require(FeatureSessionWorktreeFactory.worktrees(for: project))
        let secondWorktrees = try #require(FeatureSessionWorktreeFactory.worktrees(for: project))

        #expect(firstWorktrees[0].id == secondWorktrees[0].id)
    }

    @Test("root worktree id differs from repository worktree ids")
    func rootWorktreeIDDiffersFromRepositoryWorktreeIDs() throws {
        let project = makeFeatureSessionProject(repositoryNames: ["api"])

        let worktrees = try #require(FeatureSessionWorktreeFactory.worktrees(for: project))

        #expect(worktrees[0].id != worktrees[1].id)
    }

    @Test("legacy feature session without primaryRepositoryID still produces root")
    func legacyFeatureSessionStillProducesRoot() throws {
        let legacyFeatureSessionJSON = """
        {
          "rootPath": "/tmp/sessions/feature",
          "repositories": [
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "name": "api",
              "sourcePath": "/tmp/source/api",
              "sessionPath": "/tmp/sessions/feature/api",
              "originalBranch": "main",
              "sessionBranch": "feature",
              "kind": "git"
            }
          ]
        }
        """
        let featureSession = try JSONDecoder().decode(FeatureSession.self, from: Data(legacyFeatureSessionJSON.utf8))
        let project = Project(
            name: "feature",
            path: featureSession.rootPath,
            mode: .featureSession,
            featureSession: featureSession
        )

        let worktrees = try #require(FeatureSessionWorktreeFactory.worktrees(for: project))

        #expect(worktrees[0].source == .featureSessionRoot)
        #expect(worktrees[0].path == featureSession.rootPath)
    }

    private func makeFeatureSessionProject(repositoryNames: [String]) -> Project {
        let rootPath = "/tmp/sessions/feature"
        let repositories = repositoryNames.map { repositoryName in
            SessionRepository(
                name: repositoryName,
                sourcePath: "/tmp/source/\(repositoryName)",
                sessionPath: "\(rootPath)/\(repositoryName)",
                originalBranch: "main",
                baseBranch: "main",
                sessionBranch: "feature"
            )
        }

        return Project(
            name: "feature",
            path: rootPath,
            mode: .featureSession,
            featureSession: FeatureSession(rootPath: rootPath, repositories: repositories)
        )
    }
}
