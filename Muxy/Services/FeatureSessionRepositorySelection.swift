import Foundation

struct FeatureSessionRepositorySelection: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let currentBranch: String
    var selectedBaseBranch: String

    init(path: String, currentBranch: String, selectedBaseBranch: String? = nil) {
        self.id = path
        self.name = URL(fileURLWithPath: path).lastPathComponent
        self.path = path
        self.currentBranch = currentBranch
        self.selectedBaseBranch = selectedBaseBranch ?? currentBranch
    }
}
