import Foundation

enum FeatureSessionFileCopyError: LocalizedError {
    case gitNotFound
    case listingFailed(String)
    case copyFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .gitNotFound:
            "git executable not found in standard search paths"
        case let .listingFailed(stderr):
            "failed to list untracked and ignored files: \(stderr)"
        case let .copyFailed(relativePath, underlyingMessage):
            "failed to copy \(relativePath): \(underlyingMessage)"
        }
    }
}

enum FeatureSessionFileCopy {
    static func copyUntrackedAndIgnored(from sourcePath: String, to destinationPath: String) async throws {
        guard GitProcessRunner.resolveExecutable("git") != nil else {
            throw FeatureSessionFileCopyError.gitNotFound
        }
        let listingResult = try await GitProcessRunner.runGit(
            repoPath: sourcePath,
            arguments: ["ls-files", "-z", "-o"]
        )
        guard listingResult.status == 0 else {
            throw FeatureSessionFileCopyError.listingFailed(listingResult.stderr)
        }

        let relativePaths = parseNullSeparatedPaths(listingResult.stdoutData)
        let sourceRoot = URL(fileURLWithPath: sourcePath)
        let destinationRoot = URL(fileURLWithPath: destinationPath)

        for relativePath in relativePaths {
            guard !shouldSkipCopy(relativePath: relativePath) else { continue }
            try copyEntry(
                relativePath: relativePath,
                sourceRoot: sourceRoot,
                destinationRoot: destinationRoot
            )
        }
    }

    static func parseNullSeparatedPaths(_ rawData: Data) -> [String] {
        guard !rawData.isEmpty else { return [] }
        return rawData
            .split(separator: 0x00, omittingEmptySubsequences: true)
            .compactMap { String(data: Data($0), encoding: .utf8) }
    }

    static func shouldSkipCopy(relativePath: String) -> Bool {
        guard !relativePath.isEmpty else { return true }
        if relativePath.hasPrefix(".git/") { return true }
        return pathSegments(for: relativePath).contains("node_modules")
    }

    static func pathSegments(for relativePath: String) -> [String] {
        relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private static func copyEntry(
        relativePath: String,
        sourceRoot: URL,
        destinationRoot: URL
    ) throws {
        let sourceFileURL = sourceRoot.appendingPathComponent(relativePath)
        let destinationFileURL = destinationRoot.appendingPathComponent(relativePath)
        let destinationParentURL = destinationFileURL.deletingLastPathComponent()

        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(
                at: destinationParentURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw FeatureSessionFileCopyError.copyFailed(relativePath, error.localizedDescription)
        }

        if fileManager.fileExists(atPath: destinationFileURL.path) {
            do {
                try fileManager.removeItem(at: destinationFileURL)
            } catch {
                throw FeatureSessionFileCopyError.copyFailed(relativePath, error.localizedDescription)
            }
        }

        do {
            try fileManager.copyItem(at: sourceFileURL, to: destinationFileURL)
        } catch {
            throw FeatureSessionFileCopyError.copyFailed(relativePath, error.localizedDescription)
        }
    }
}
