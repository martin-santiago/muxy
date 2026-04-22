import Foundation
import Testing

@testable import Muxy

@Suite("FeatureSessionService")
struct FeatureSessionServiceTests {
    @Test("createSession requires at least one repository")
    func createSessionRequiresRepositories() async {
        let dependencies = makeDependencies()

        do {
            _ = try await FeatureSessionService.createSession(
                name: "feature/session",
                repositories: [],
                sortOrder: 0,
                dependencies: dependencies
            )
            Issue.record("expected noRepositoriesSelected error")
        } catch let error as FeatureSessionError {
            guard case .noRepositoriesSelected = error else {
                Issue.record("unexpected error: \(error.localizedDescription)")
                return
            }
        } catch {
            Issue.record("unexpected error: \(error.localizedDescription)")
        }
    }

    @Test("createSession rejects invalid session names")
    func createSessionRejectsInvalidSessionNames() async {
        let dependencies = makeDependencies(isValidBranchName: false)

        do {
            _ = try await FeatureSessionService.createSession(
                name: "invalid session name",
                repositories: [selection(path: "/tmp/api")],
                sortOrder: 0,
                dependencies: dependencies
            )
            Issue.record("expected invalidSessionName error")
        } catch let error as FeatureSessionError {
            guard case .invalidSessionName = error else {
                Issue.record("unexpected error: \(error.localizedDescription)")
                return
            }
        } catch {
            Issue.record("unexpected error: \(error.localizedDescription)")
        }
    }

    @Test("createSession rejects duplicate repository folder names")
    func createSessionRejectsDuplicateRepositoryNames() async {
        let dependencies = makeDependencies()
        let repositories = [
            selection(path: "/tmp/source/api"),
            selection(path: "/tmp/other/api"),
        ]

        do {
            _ = try await FeatureSessionService.createSession(
                name: "feature/session",
                repositories: repositories,
                sortOrder: 0,
                dependencies: dependencies
            )
            Issue.record("expected duplicateRepositoryNames error")
        } catch let error as FeatureSessionError {
            guard case .duplicateRepositoryNames = error else {
                Issue.record("unexpected error: \(error.localizedDescription)")
                return
            }
        } catch {
            Issue.record("unexpected error: \(error.localizedDescription)")
        }
    }

    @Test("createSession rolls back created repositories after a later failure")
    func createSessionRollsBackCreatedRepositories() async {
        let sessionRoot = URL(fileURLWithPath: "/tmp/sessions/feature-session", isDirectory: true)
        let fileClient = FeatureSessionFileClientStub()
        let gitRepositoryClient = FeatureSessionGitRepositoryClientStub()
        let gitWorktreeClient = FeatureSessionGitWorktreeClientStub(
            addFailuresByPath: [sessionRoot.appendingPathComponent("web", isDirectory: true).path: "add failed"]
        )
        let dependencies = makeDependencies(
            fileClient: fileClient,
            gitRepositoryClient: gitRepositoryClient,
            gitWorktreeClient: gitWorktreeClient,
            sessionRoot: sessionRoot
        )

        do {
            _ = try await FeatureSessionService.createSession(
                name: "feature-session",
                repositories: [selection(path: "/tmp/source/api"), selection(path: "/tmp/source/web")],
                sortOrder: 2,
                dependencies: dependencies
            )
            Issue.record("expected repository operation failure")
        } catch let error as FeatureSessionError {
            guard case let .repositoryOperationFailed(repositoryName, message) = error else {
                Issue.record("unexpected error: \(error.localizedDescription)")
                return
            }
            #expect(repositoryName == "web")
            #expect(message == "add failed")
        } catch {
            Issue.record("unexpected error: \(error.localizedDescription)")
        }

        let removedWorktreePaths = gitWorktreeClient.removedWorktreePaths()
        let deletedBranches = gitWorktreeClient.deletedBranches()
        let removedFilePaths = fileClient.removedPaths

        #expect(removedWorktreePaths == [sessionRoot.appendingPathComponent("api", isDirectory: true).path])
        #expect(deletedBranches == ["feature-session"])
        #expect(removedFilePaths.contains(sessionRoot.appendingPathComponent("api", isDirectory: true).path))
        #expect(removedFilePaths.contains(sessionRoot.path))
        #expect(fileClient.existingPaths.contains(sessionRoot.path) == false)
    }

    @Test("createSession surfaces cleanup failures during rollback")
    func createSessionSurfacesCleanupFailures() async {
        let sessionRoot = URL(fileURLWithPath: "/tmp/sessions/feature-session", isDirectory: true)
        let fileClient = FeatureSessionFileClientStub()
        let gitWorktreeClient = FeatureSessionGitWorktreeClientStub(
            addFailuresByPath: [sessionRoot.appendingPathComponent("web", isDirectory: true).path: "add failed"],
            removeFailuresByPath: [sessionRoot.appendingPathComponent("api", isDirectory: true).path: "remove failed"]
        )
        let dependencies = makeDependencies(
            fileClient: fileClient,
            gitWorktreeClient: gitWorktreeClient,
            sessionRoot: sessionRoot
        )

        do {
            _ = try await FeatureSessionService.createSession(
                name: "feature-session",
                repositories: [selection(path: "/tmp/source/api"), selection(path: "/tmp/source/web")],
                sortOrder: 2,
                dependencies: dependencies
            )
            Issue.record("expected cleanup failure")
        } catch let error as FeatureSessionError {
            guard case let .cleanupFailed(message, cleanupSummary) = error else {
                Issue.record("unexpected error: \(error.localizedDescription)")
                return
            }
            #expect(message.contains("web: add failed"))
            #expect(cleanupSummary.contains("api: remove worktree: remove failed"))
        } catch {
            Issue.record("unexpected error: \(error.localizedDescription)")
        }
    }

    @Test("deleteSession reports each cleanup issue")
    func deleteSessionReportsCleanupIssues() async {
        let sessionRoot = URL(fileURLWithPath: "/tmp/sessions/feature-session", isDirectory: true)
        let sessionPath = sessionRoot.appendingPathComponent("api", isDirectory: true).path
        let fileClient = FeatureSessionFileClientStub(
            existingPaths: [sessionRoot.path, sessionPath],
            removeFailuresByPath: [sessionRoot.path: "root locked", sessionPath: "folder locked"]
        )
        let gitWorktreeClient = FeatureSessionGitWorktreeClientStub(
            removeFailuresByPath: [sessionPath: "remove failed"],
            deleteFailuresByBranch: ["feature-session": "delete failed"]
        )
        let project = Project(
            name: "feature-session",
            path: sessionRoot.path,
            mode: .featureSession,
            featureSession: FeatureSession(
                rootPath: sessionRoot.path,
                repositories: [
                    SessionRepository(
                        name: "api",
                        sourcePath: "/tmp/source/api",
                        sessionPath: sessionPath,
                        originalBranch: "main",
                        sessionBranch: "feature-session"
                    )
                ]
            )
        )
        let dependencies = makeDependencies(
            fileClient: fileClient,
            gitWorktreeClient: gitWorktreeClient,
            sessionRoot: sessionRoot
        )

        let report = await FeatureSessionService.deleteSession(project: project, dependencies: dependencies)

        #expect(report.sessionName == "feature-session")
        #expect(report.issues.count == 4)
        #expect(report.alertMessage.contains("api: remove worktree: remove failed"))
        #expect(report.alertMessage.contains("api: delete branch: delete failed"))
        #expect(report.alertMessage.contains("api: remove session folder: folder locked"))
        #expect(report.alertMessage.contains("feature-session: remove session root folder: root locked"))
    }

    @Test("createSession rejects when session already exists")
    func createSessionRejectsWhenSessionAlreadyExists() async {
        let sessionRoot = URL(fileURLWithPath: "/tmp/sessions/feature-session", isDirectory: true)
        let fileClient = FeatureSessionFileClientStub(existingPaths: [sessionRoot.path])
        let dependencies = makeDependencies(fileClient: fileClient, sessionRoot: sessionRoot)

        do {
            _ = try await FeatureSessionService.createSession(
                name: "feature-session",
                repositories: [selection(path: "/tmp/api")],
                sortOrder: 0,
                dependencies: dependencies
            )
            Issue.record("expected sessionAlreadyExists error")
        } catch let error as FeatureSessionError {
            guard case .sessionAlreadyExists = error else {
                Issue.record("unexpected error: \(error.localizedDescription)")
                return
            }
        } catch {
            Issue.record("unexpected error: \(error.localizedDescription)")
        }
    }

    @Test("createSession rejects repositories on detached HEAD")
    func createSessionRejectsDetachedHead() async {
        let gitRepositoryClient = FeatureSessionGitRepositoryClientStub(
            currentBranchesByPath: ["/tmp/api": "HEAD"]
        )
        let dependencies = makeDependencies(gitRepositoryClient: gitRepositoryClient)

        do {
            _ = try await FeatureSessionService.createSession(
                name: "feature-session",
                repositories: [selection(path: "/tmp/api")],
                sortOrder: 0,
                dependencies: dependencies
            )
            Issue.record("expected detachedHead error")
        } catch let error as FeatureSessionError {
            guard case let .detachedHead(path) = error else {
                Issue.record("unexpected error: \(error.localizedDescription)")
                return
            }
            #expect(path == "/tmp/api")
        } catch {
            Issue.record("unexpected error: \(error.localizedDescription)")
        }
    }

    @Test("createSession rejects non-git repositories")
    func createSessionRejectsNonGitRepository() async {
        let gitWorktreeClient = FeatureSessionGitWorktreeClientStub(gitRepositoryPaths: [])
        let dependencies = makeDependencies(gitWorktreeClient: gitWorktreeClient)

        do {
            _ = try await FeatureSessionService.createSession(
                name: "feature-session",
                repositories: [selection(path: "/tmp/not-git")],
                sortOrder: 0,
                dependencies: dependencies
            )
            Issue.record("expected notGitRepository error")
        } catch let error as FeatureSessionError {
            guard case let .notGitRepository(path) = error else {
                Issue.record("unexpected error: \(error.localizedDescription)")
                return
            }
            #expect(path == "/tmp/not-git")
        } catch {
            Issue.record("unexpected error: \(error.localizedDescription)")
        }
    }

    @Test("createSession rejects when session repository path already exists")
    func createSessionRejectsWhenSessionRepositoryPathAlreadyExists() async {
        let sessionRoot = URL(fileURLWithPath: "/tmp/sessions/feature-session", isDirectory: true)
        let existingSessionRepoPath = sessionRoot.appendingPathComponent("api", isDirectory: true).path
        let fileClient = FeatureSessionFileClientStub(existingPaths: [existingSessionRepoPath])
        let dependencies = makeDependencies(fileClient: fileClient, sessionRoot: sessionRoot)

        do {
            _ = try await FeatureSessionService.createSession(
                name: "feature-session",
                repositories: [selection(path: "/tmp/api")],
                sortOrder: 0,
                dependencies: dependencies
            )
            Issue.record("expected sessionRepositoryPathAlreadyExists error")
        } catch let error as FeatureSessionError {
            guard case let .sessionRepositoryPathAlreadyExists(path) = error else {
                Issue.record("unexpected error: \(error.localizedDescription)")
                return
            }
            #expect(path == existingSessionRepoPath)
        } catch {
            Issue.record("unexpected error: \(error.localizedDescription)")
        }
    }

    @Test("createSession rejects when session branch already exists in repository")
    func createSessionRejectsWhenSessionBranchAlreadyExists() async {
        let gitRepositoryClient = FeatureSessionGitRepositoryClientStub(
            branchesByPath: ["/tmp/api": ["main", "feature-session"]]
        )
        let dependencies = makeDependencies(gitRepositoryClient: gitRepositoryClient)

        do {
            _ = try await FeatureSessionService.createSession(
                name: "feature-session",
                repositories: [selection(path: "/tmp/api")],
                sortOrder: 0,
                dependencies: dependencies
            )
            Issue.record("expected sessionBranchAlreadyExists error")
        } catch let error as FeatureSessionError {
            guard case let .sessionBranchAlreadyExists(path, branch) = error else {
                Issue.record("unexpected error: \(error.localizedDescription)")
                return
            }
            #expect(path == "/tmp/api")
            #expect(branch == "feature-session")
        } catch {
            Issue.record("unexpected error: \(error.localizedDescription)")
        }
    }

    @Test("createSession rolls back after pull failure with earlier successful repositories")
    func createSessionRollsBackAfterPullFailureWithEarlierSuccess() async {
        let sessionRoot = URL(fileURLWithPath: "/tmp/sessions/feature-session", isDirectory: true)
        let fileClient = FeatureSessionFileClientStub()
        let gitRepositoryClient = FeatureSessionGitRepositoryClientStub(
            pullFailuresByPath: ["/tmp/web": "pull failed"]
        )
        let gitWorktreeClient = FeatureSessionGitWorktreeClientStub()
        let dependencies = makeDependencies(
            fileClient: fileClient,
            gitRepositoryClient: gitRepositoryClient,
            gitWorktreeClient: gitWorktreeClient,
            sessionRoot: sessionRoot
        )

        do {
            _ = try await FeatureSessionService.createSession(
                name: "feature-session",
                repositories: [selection(path: "/tmp/api"), selection(path: "/tmp/web")],
                sortOrder: 2,
                dependencies: dependencies
            )
            Issue.record("expected repository operation failure")
        } catch let error as FeatureSessionError {
            guard case let .repositoryOperationFailed(repositoryName, message) = error else {
                Issue.record("unexpected error: \(error.localizedDescription)")
                return
            }
            #expect(repositoryName == "web")
            #expect(message == "pull failed")
        } catch {
            Issue.record("unexpected error: \(error.localizedDescription)")
        }

        let removedWorktreePaths = gitWorktreeClient.removedWorktreePaths()
        let deletedBranches = gitWorktreeClient.deletedBranches()
        let removedFilePaths = fileClient.removedPaths

        #expect(removedWorktreePaths.isEmpty)
        #expect(deletedBranches == ["feature-session"])
        #expect(removedFilePaths.contains(sessionRoot.path))
        #expect(fileClient.existingPaths.contains(sessionRoot.path) == false)
    }

    @Test("inspectRepositories rejects repositories on detached HEAD")
    func inspectRepositoriesRejectsDetachedHead() async {
        let gitRepositoryClient = FeatureSessionGitRepositoryClientStub(
            currentBranchesByPath: ["/tmp/api": "HEAD"]
        )
        let dependencies = makeDependencies(gitRepositoryClient: gitRepositoryClient)

        do {
            _ = try await FeatureSessionService.inspectRepositories(
                paths: ["/tmp/api"],
                dependencies: dependencies
            )
            Issue.record("expected detachedHead error")
        } catch let error as FeatureSessionError {
            guard case let .detachedHead(path) = error else {
                Issue.record("unexpected error: \(error.localizedDescription)")
                return
            }
            #expect(path == "/tmp/api")
        } catch {
            Issue.record("unexpected error: \(error.localizedDescription)")
        }
    }

    @Test("inspectRepositories rejects non-git repositories")
    func inspectRepositoriesRejectsNonGitRepository() async {
        let gitWorktreeClient = FeatureSessionGitWorktreeClientStub(gitRepositoryPaths: [])
        let dependencies = makeDependencies(gitWorktreeClient: gitWorktreeClient)

        do {
            _ = try await FeatureSessionService.inspectRepositories(
                paths: ["/tmp/not-git"],
                dependencies: dependencies
            )
            Issue.record("expected notGitRepository error")
        } catch let error as FeatureSessionError {
            guard case let .notGitRepository(path) = error else {
                Issue.record("unexpected error: \(error.localizedDescription)")
                return
            }
            #expect(path == "/tmp/not-git")
        } catch {
            Issue.record("unexpected error: \(error.localizedDescription)")
        }
    }

    @Test("createSession handles current branch retrieval failure during validation")
    func createSessionHandlesCurrentBranchFailureDuringValidation() async {
        let gitRepositoryClient = FeatureSessionGitRepositoryClientStub(
            currentBranchesByPath: ["/tmp/api": "main"]
        )
        let dependencies = makeDependencies(gitRepositoryClient: gitRepositoryClient)

        let modifiedClient = FeatureSessionGitRepositoryClient(
            currentBranch: { _ in throw FeatureSessionStubError(message: "git error") },
            isValidBranchName: gitRepositoryClient.client(isValidBranchName: true).isValidBranchName,
            listBranches: gitRepositoryClient.client(isValidBranchName: true).listBranches,
            pull: gitRepositoryClient.client(isValidBranchName: true).pull
        )

        let modifiedDependencies = FeatureSessionServiceDependencies(
            fileClient: dependencies.fileClient,
            gitRepositoryClient: modifiedClient,
            gitWorktreeClient: dependencies.gitWorktreeClient,
            sessionRoot: dependencies.sessionRoot
        )

        do {
            _ = try await FeatureSessionService.createSession(
                name: "feature-session",
                repositories: [selection(path: "/tmp/api")],
                sortOrder: 0,
                dependencies: modifiedDependencies
            )
            Issue.record("expected repository operation failure")
        } catch let error as FeatureSessionError {
            guard case let .repositoryOperationFailed(repositoryName, message) = error else {
                Issue.record("unexpected error: \(error.localizedDescription)")
                return
            }
            #expect(repositoryName == "api")
            #expect(message == "git error")
        } catch {
            Issue.record("unexpected error: \(error.localizedDescription)")
        }
    }

    @Test("createSession handles branch listing failure during validation")
    func createSessionHandlesBranchListingFailureDuringValidation() async {
        let gitRepositoryClient = FeatureSessionGitRepositoryClientStub()
        let dependencies = makeDependencies(gitRepositoryClient: gitRepositoryClient)

        let modifiedClient = FeatureSessionGitRepositoryClient(
            currentBranch: gitRepositoryClient.client(isValidBranchName: true).currentBranch,
            isValidBranchName: gitRepositoryClient.client(isValidBranchName: true).isValidBranchName,
            listBranches: { _ in throw FeatureSessionStubError(message: "branch list error") },
            pull: gitRepositoryClient.client(isValidBranchName: true).pull
        )

        let modifiedDependencies = FeatureSessionServiceDependencies(
            fileClient: dependencies.fileClient,
            gitRepositoryClient: modifiedClient,
            gitWorktreeClient: dependencies.gitWorktreeClient,
            sessionRoot: dependencies.sessionRoot
        )

        do {
            _ = try await FeatureSessionService.createSession(
                name: "feature-session",
                repositories: [selection(path: "/tmp/api")],
                sortOrder: 0,
                dependencies: modifiedDependencies
            )
            Issue.record("expected repository operation failure")
        } catch let error as FeatureSessionError {
            guard case let .repositoryOperationFailed(repositoryName, message) = error else {
                Issue.record("unexpected error: \(error.localizedDescription)")
                return
            }
            #expect(repositoryName == "api")
            #expect(message == "branch list error")
        } catch {
            Issue.record("unexpected error: \(error.localizedDescription)")
        }
    }

    @Test("repository selection merge updates existing entries in place and appends new ones")
    func repositorySelectionMergeUpdatesAndAppends() {
        let existingRepositories = [
            FeatureSessionRepositorySelection(path: "/tmp/source/api", currentBranch: "main"),
            FeatureSessionRepositorySelection(path: "/tmp/source/web", currentBranch: "main"),
        ]
        let incomingRepositories = [
            FeatureSessionRepositorySelection(path: "/tmp/source/api", currentBranch: "release"),
            FeatureSessionRepositorySelection(path: "/tmp/source/docs", currentBranch: "main"),
        ]

        let mergedRepositories = FeatureSessionRepositorySelectionMerger.merge(
            existingRepositories: existingRepositories,
            incomingRepositories: incomingRepositories
        )

        #expect(mergedRepositories.map(\.name) == ["api", "web", "docs"])
        #expect(mergedRepositories.map(\.currentBranch) == ["release", "main", "main"])
    }

    private func makeDependencies(
        isValidBranchName: Bool = true,
        fileClient: FeatureSessionFileClientStub = FeatureSessionFileClientStub(),
        gitRepositoryClient: FeatureSessionGitRepositoryClientStub = FeatureSessionGitRepositoryClientStub(),
        gitWorktreeClient: FeatureSessionGitWorktreeClientStub = FeatureSessionGitWorktreeClientStub(),
        sessionRoot: URL = URL(fileURLWithPath: "/tmp/sessions/default-session", isDirectory: true)
    ) -> FeatureSessionServiceDependencies {
        FeatureSessionServiceDependencies(
            fileClient: fileClient.client,
            gitRepositoryClient: gitRepositoryClient.client(isValidBranchName: isValidBranchName),
            gitWorktreeClient: gitWorktreeClient.client,
            sessionRoot: { _ in sessionRoot }
        )
    }

    private func selection(path: String, currentBranch: String = "main") -> FeatureSessionRepositorySelection {
        FeatureSessionRepositorySelection(path: path, currentBranch: currentBranch)
    }
}
