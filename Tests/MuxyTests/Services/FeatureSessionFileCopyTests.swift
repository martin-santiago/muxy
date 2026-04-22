import Foundation
import Testing

@testable import Muxy

@Suite("FeatureSessionFileCopy")
struct FeatureSessionFileCopyTests {
    @Test("parseNullSeparatedPaths decodes nul separated output")
    func parseNullSeparatedPathsDecodesNulSeparatedOutput() {
        let rawData = Data(".env\0.vscode/settings.json\0dist/index.js\0".utf8)

        let relativePaths = FeatureSessionFileCopy.parseNullSeparatedPaths(rawData)

        #expect(relativePaths == [".env", ".vscode/settings.json", "dist/index.js"])
    }

    @Test("shouldSkipCopy allows local config files outside node_modules")
    func shouldSkipCopyAllowsLocalConfigFilesOutsideNodeModules() {
        #expect(FeatureSessionFileCopy.shouldSkipCopy(relativePath: ".env") == false)
        #expect(FeatureSessionFileCopy.shouldSkipCopy(relativePath: ".vscode/settings.json") == false)
        #expect(FeatureSessionFileCopy.shouldSkipCopy(relativePath: "dist/index.js") == false)
    }

    @Test("shouldSkipCopy excludes node_modules at any depth")
    func shouldSkipCopyExcludesNodeModulesAtAnyDepth() {
        #expect(FeatureSessionFileCopy.shouldSkipCopy(relativePath: "node_modules/.bin/eslint"))
        #expect(FeatureSessionFileCopy.shouldSkipCopy(relativePath: "packages/app/node_modules/react/index.js"))
    }

    @Test("shouldSkipCopy excludes git internals but not false positives")
    func shouldSkipCopyExcludesGitInternalsButNotFalsePositives() {
        #expect(FeatureSessionFileCopy.shouldSkipCopy(relativePath: ".git/config"))
        #expect(FeatureSessionFileCopy.shouldSkipCopy(relativePath: "node_modules-cache/file") == false)
    }
}
