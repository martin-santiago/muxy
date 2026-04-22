import Foundation

struct FeatureSessionRepositorySelection: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let currentBranch: String

    init(path: String, currentBranch: String) {
        self.id = path
        self.name = URL(fileURLWithPath: path).lastPathComponent
        self.path = path
        self.currentBranch = currentBranch
    }
}
