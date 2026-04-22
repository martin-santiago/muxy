import Foundation

struct FeatureSessionCleanupIssue: Hashable {
    let scope: String
    let action: String
    let message: String

    var formattedDescription: String {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(scope): \(action): \(trimmedMessage)"
    }
}

struct FeatureSessionCleanupReport: Hashable {
    let sessionName: String
    let issues: [FeatureSessionCleanupIssue]

    var hasIssues: Bool {
        !issues.isEmpty
    }

    var alertTitle: String {
        "Feature Session Cleanup Incomplete"
    }

    var alertMessage: String {
        issues.map(\.formattedDescription).joined(separator: "\n")
    }
}
