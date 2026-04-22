import Foundation
import Foundation
import Testing

@testable import Muxy

@Suite("FeatureSessionService")
struct FeatureSessionServiceTests {
    @Test("createSession emits progress events in order for happy path")
    func createSessionEmitsProgressEvents() async throws {
        let dependencies = makeDependencies(
            sessionRoot: URL(fileURLWithPath: "/tmp/sessions/feature-session", isDirectory: true)
        )
        let eventCollector = EventCollector()

        _ = try await FeatureSessionService.createSession(
            name: "feature-session",
            repositories: [selection(path: "/tmp/source/api"), selection(path: "/tmp/source/web")],
            sortOrder: 0,
            onProgress: { featureSessionCreationEvent in
                eventCollector.append(featureSessionCreationEvent)
            },
            dependencies: dependencies
        )

        let featureSessionCreationEvents = await MainActor.run { eventCollector.all }

        #expect(featureSessionCreationEvents == [
            .validatingRepository(name: "api"),
            .validatingRepository(name: "web"),
            .preparingSessionDirectory,
            .pullingRepository(name: "api"),
            .creatingWorktree(name: "api"),
            .finishedRepository(name: "api"),
            .pullingRepository(name: "web"),
            .creatingWorktree(name: "web"),
            .finishedRepository(name: "web"),
        ])
    }

    @Test("createSession emits copyingHiddenFiles when toggle is on")
    func createSessionEmitsCopyingHiddenFilesWhenEnabled() async throws {
        let dependencies = makeDependencies(
            sessionRoot: URL(fileURLWithPath: "/tmp/sessions/feature-session", isDirectory: true)
        )
        let eventCollector = EventCollector()

        _ = try await FeatureSessionService.createSession(
            name: "feature-session",
            repositories: [selection(path: "/tmp/source/api")],
            sortOrder: 0,
            copyHiddenAndIgnoredFiles: true,
            onProgress: { featureSessionCreationEvent in
                eventCollector.append(featureSessionCreationEvent)
            },
            dependencies: dependencies
        )

        let featureSessionCreationEvents = await MainActor.run { eventCollector.all }

        #expect(featureSessionCreationEvents.contains(.copyingHiddenFiles(name: "api")))
    }

    @Test("createSession emits rollingBack when a later step fails")
    func createSessionEmitsRollingBackOnFailure() async {
        let sessionRoot = URL(fileURLWithPath: "/tmp/sessions/feature-session", isDirectory: true)
        let dependencies = makeDependencies(
            gitWorktreeClient: FeatureSessionGitWorktreeClientStub(
                addFailuresByPath: [sessionRoot.appendingPathComponent("web", isDirectory: true).path: "add failed"]
            ),
            sessionRoot: sessionRoot
        )
        let eventCollector = EventCollector()

        do {
            _ = try await FeatureSessionService.createSession(
                name: "feature-session",
                repositories: [selection(path: "/tmp/source/api"), selection(path: "/tmp/source/web")],
                sortOrder: 0,
                onProgress: { featureSessionCreationEvent in
                    eventCollector.append(featureSessionCreationEvent)
                },
                dependencies: dependencies
            )
            Issue.record("expected repository operation failure")
        } catch {
        }

        let featureSessionCreationEvents = await MainActor.run { eventCollector.all }

        #expect(featureSessionCreationEvents.contains(.rollingBack))
    }

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
                        baseBranch: "main",
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
            #expect(path == URL(fileURLWithPath: "/tmp/not-git").standardizedFileURL.path(percentEncoded: false))
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
        let apiSessionPath = sessionRoot.appendingPathComponent("api", isDirectory: true).path

        #expect(removedWorktreePaths == [apiSessionPath])
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
            #expect(path == URL(fileURLWithPath: "/tmp/not-git").standardizedFileURL.path(percentEncoded: false))
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

    @Test("createSession invokes copy once per repository when copyHiddenAndIgnoredFiles is true")
    func createSessionCopiesHiddenAndIgnoredFilesPerRepository() async throws {
        let sessionRoot = URL(fileURLWithPath: "/tmp/sessions/feature-session", isDirectory: true)
        let fileClient = FeatureSessionFileClientStub()
        let dependencies = makeDependencies(fileClient: fileClient, sessionRoot: sessionRoot)

        _ = try await FeatureSessionService.createSession(
            name: "feature-session",
            repositories: [selection(path: "/tmp/source/api"), selection(path: "/tmp/source/web")],
            sortOrder: 0,
            copyHiddenAndIgnoredFiles: true,
            dependencies: dependencies
        )

        let copyCalls = fileClient.copyUntrackedAndIgnoredCalls
        #expect(copyCalls.count == 2)
        #expect(copyCalls[0].source == "/tmp/source/api")
        #expect(copyCalls[0].destination == sessionRoot.appendingPathComponent("api", isDirectory: true).path)
        #expect(copyCalls[1].source == "/tmp/source/web")
        #expect(copyCalls[1].destination == sessionRoot.appendingPathComponent("web", isDirectory: true).path)
    }

    @Test("createSession does not invoke copy when copyHiddenAndIgnoredFiles is false")
    func createSessionSkipsCopyWhenDisabled() async throws {
        let sessionRoot = URL(fileURLWithPath: "/tmp/sessions/feature-session", isDirectory: true)
        let fileClient = FeatureSessionFileClientStub()
        let dependencies = makeDependencies(fileClient: fileClient, sessionRoot: sessionRoot)

        _ = try await FeatureSessionService.createSession(
            name: "feature-session",
            repositories: [selection(path: "/tmp/source/api"), selection(path: "/tmp/source/web")],
            sortOrder: 0,
            dependencies: dependencies
        )

        #expect(fileClient.copyUntrackedAndIgnoredCalls.isEmpty)
    }

    @Test("createSession rolls back when copy fails")
    func createSessionRollsBackWhenCopyFails() async {
        let sessionRoot = URL(fileURLWithPath: "/tmp/sessions/feature-session", isDirectory: true)
        let fileClient = FeatureSessionFileClientStub(
            copyFailuresBySourcePath: ["/tmp/source/web": "disk full"]
        )
        let gitWorktreeClient = FeatureSessionGitWorktreeClientStub()
        let dependencies = makeDependencies(
            fileClient: fileClient,
            gitWorktreeClient: gitWorktreeClient,
            sessionRoot: sessionRoot
        )

        do {
            _ = try await FeatureSessionService.createSession(
                name: "feature-session",
                repositories: [selection(path: "/tmp/source/api"), selection(path: "/tmp/source/web")],
                sortOrder: 0,
                copyHiddenAndIgnoredFiles: true,
                dependencies: dependencies
            )
            Issue.record("expected repository operation failure")
        } catch let error as FeatureSessionError {
            guard case let .repositoryOperationFailed(repositoryName, message) = error else {
                Issue.record("unexpected error: \(error.localizedDescription)")
                return
            }
            #expect(repositoryName == "web")
            #expect(message.contains("disk full"))
        } catch {
            Issue.record("unexpected error: \(error.localizedDescription)")
        }

        let removedWorktreePaths = gitWorktreeClient.removedWorktreePaths()
        let deletedBranches = gitWorktreeClient.deletedBranches()
        let removedFilePaths = fileClient.removedPaths
        let apiSessionPath = sessionRoot.appendingPathComponent("api", isDirectory: true).path
        let webSessionPath = sessionRoot.appendingPathComponent("web", isDirectory: true).path

        #expect(removedWorktreePaths.contains(apiSessionPath))
        #expect(removedWorktreePaths.contains(webSessionPath))
        #expect(deletedBranches == ["feature-session", "feature-session"])
        #expect(removedFilePaths.contains(sessionRoot.path))
        #expect(fileClient.existingPaths.contains(sessionRoot.path) == false)
    }

    @Test("repository selection merge updates existing entries in place and appends new ones")
    func repositorySelectionMergeUpdatesAndAppends() {
        let existingRepositories = [
            FeatureSessionRepositorySelection(
                path: "/tmp/source/api",
                currentBranch: "main",
                selectedBaseBranch: "release/1"
            ),
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
        #expect(mergedRepositories.map(\.selectedBaseBranch) == ["release/1", "main", "main"])
    }

    @Test("createSession uses selected base branch as worktree start point and persists it")
    func createSessionUsesSelectedBaseBranchAsWorktreeStartPointAndPersistsIt() async throws {
        let gitWorktreeClient = FeatureSessionGitWorktreeClientStub()
        let gitRepositoryClient = FeatureSessionGitRepositoryClientStub(
            branchesByPath: ["/tmp/source/api": ["main", "release/1"]]
        )
        let dependencies = makeDependencies(
            gitRepositoryClient: gitRepositoryClient,
            gitWorktreeClient: gitWorktreeClient
        )

        let project = try await FeatureSessionService.createSession(
            name: "feature-session",
            repositories: [selection(path: "/tmp/source/api", selectedBaseBranch: "release/1")],
            sortOrder: 0,
            dependencies: dependencies
        )

        let addWorktreeCall = try #require(gitWorktreeClient.addWorktreeCalls().first)
        #expect(addWorktreeCall.startPoint == "release/1")
        #expect(project.featureSession?.repositories.first?.baseBranch == "release/1")
    }

    @Test("createSession rejects missing selected base branch")
    func createSessionRejectsMissingSelectedBaseBranch() async {
        let gitRepositoryClient = FeatureSessionGitRepositoryClientStub(
            branchesByPath: ["/tmp/source/api": ["main", "develop"]]
        )
        let dependencies = makeDependencies(gitRepositoryClient: gitRepositoryClient)

        do {
            _ = try await FeatureSessionService.createSession(
                name: "feature-session",
                repositories: [selection(path: "/tmp/source/api", selectedBaseBranch: "release/1")],
                sortOrder: 0,
                dependencies: dependencies
            )
            Issue.record("expected selectedBaseBranchMissing error")
        } catch let error as FeatureSessionError {
            guard case let .selectedBaseBranchMissing(repositoryName, branch) = error else {
                Issue.record("unexpected error: \(error.localizedDescription)")
                return
            }
            #expect(repositoryName == "api")
            #expect(branch == "release/1")
        } catch {
            Issue.record("unexpected error: \(error.localizedDescription)")
        }
    }

    @Test("addRepositories appends repositories and preserves primary repository selection")
    func addRepositoriesAppendsRepositoriesAndPreservesPrimaryRepositorySelection() async throws {
        let existingRepository = SessionRepository(
            name: "api",
            sourcePath: "/tmp/source/api",
            sessionPath: "/tmp/sessions/feature-session/api",
            originalBranch: "main",
            baseBranch: "main",
            sessionBranch: "feature-session"
        )
        let project = Project(
            name: "feature-session",
            path: "/tmp/sessions/feature-session",
            mode: .featureSession,
            featureSession: FeatureSession(
                rootPath: "/tmp/sessions/feature-session",
                repositories: [existingRepository],
                primaryRepositoryID: existingRepository.id
            )
        )
        let gitRepositoryClient = FeatureSessionGitRepositoryClientStub(
            branchesByPath: ["/tmp/source/web": ["main", "develop"]]
        )

        let updatedProject = try await FeatureSessionService.addRepositories(
            to: project,
            repositories: [selection(path: "/tmp/source/web", selectedBaseBranch: "develop")],
            dependencies: makeDependencies(gitRepositoryClient: gitRepositoryClient)
        )

        #expect(updatedProject.featureSession?.repositories.map(\.name) == ["api", "web"])
        #expect(updatedProject.featureSession?.primaryRepositoryID == existingRepository.id)
        #expect(updatedProject.featureSession?.repositories.last?.baseBranch == "develop")
    }

    @Test("addRepositories rejects repositories already present in the session")
    func addRepositoriesRejectsRepositoriesAlreadyPresentInTheSession() async {
        let existingRepository = SessionRepository(
            name: "api",
            sourcePath: "/tmp/source/api",
            sessionPath: "/tmp/sessions/feature-session/api",
            originalBranch: "main",
            baseBranch: "main",
            sessionBranch: "feature-session"
        )
        let project = Project(
            name: "feature-session",
            path: "/tmp/sessions/feature-session",
            mode: .featureSession,
            featureSession: FeatureSession(rootPath: "/tmp/sessions/feature-session", repositories: [existingRepository])
        )

        do {
            _ = try await FeatureSessionService.addRepositories(
                to: project,
                repositories: [selection(path: "/tmp/source/api")],
                dependencies: makeDependencies()
            )
            Issue.record("expected repositoriesAlreadyInSession error")
        } catch let error as FeatureSessionError {
            guard case let .repositoriesAlreadyInSession(repositoryNames) = error else {
                Issue.record("unexpected error: \(error.localizedDescription)")
                return
            }
            #expect(repositoryNames == ["api"])
        } catch {
            Issue.record("unexpected error: \(error.localizedDescription)")
        }
    }

    @Test("addRepositories rolls back only newly created repositories")
    func addRepositoriesRollsBackOnlyNewlyCreatedRepositories() async {
        let sessionRoot = URL(fileURLWithPath: "/tmp/sessions/feature-session", isDirectory: true)
        let fileClient = FeatureSessionFileClientStub(existingPaths: [sessionRoot.path])
        let gitWorktreeClient = FeatureSessionGitWorktreeClientStub(
            addFailuresByPath: [sessionRoot.appendingPathComponent("web", isDirectory: true).path: "add failed"]
        )
        let existingRepository = SessionRepository(
            name: "api",
            sourcePath: "/tmp/source/api",
            sessionPath: sessionRoot.appendingPathComponent("api", isDirectory: true).path,
            originalBranch: "main",
            baseBranch: "main",
            sessionBranch: "feature-session"
        )
        let project = Project(
            name: "feature-session",
            path: sessionRoot.path,
            mode: .featureSession,
            featureSession: FeatureSession(rootPath: sessionRoot.path, repositories: [existingRepository])
        )
        let dependencies = makeDependencies(
            fileClient: fileClient,
            gitWorktreeClient: gitWorktreeClient,
            sessionRoot: sessionRoot
        )

        do {
            _ = try await FeatureSessionService.addRepositories(
                to: project,
                repositories: [selection(path: "/tmp/source/docs"), selection(path: "/tmp/source/web")],
                dependencies: dependencies
            )
            Issue.record("expected repository operation failure")
        } catch let error as FeatureSessionError {
            guard case let .repositoryOperationFailed(repositoryName, message) = error else {
                Issue.record("unexpected error: \(error.localizedDescription)")
                return
            }
            #expect(repositoryName == "web")
            #expect(message.contains("add failed"))
        } catch {
            Issue.record("unexpected error: \(error.localizedDescription)")
        }

        #expect(gitWorktreeClient.removedWorktreePaths() == [sessionRoot.appendingPathComponent("docs", isDirectory: true).path])
        #expect(fileClient.removedPaths.contains(sessionRoot.path) == false)
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

    private func selection(
        path: String,
        currentBranch: String = "main",
        selectedBaseBranch: String? = nil
    ) -> FeatureSessionRepositorySelection {
        FeatureSessionRepositorySelection(
            path: path,
            currentBranch: currentBranch,
            selectedBaseBranch: selectedBaseBranch
        )
    }
}

@MainActor
final class EventCollector {
    private(set) var all: [FeatureSessionCreationEvent] = []

    func append(_ featureSessionCreationEvent: FeatureSessionCreationEvent) {
        all.append(featureSessionCreationEvent)
    }
}
