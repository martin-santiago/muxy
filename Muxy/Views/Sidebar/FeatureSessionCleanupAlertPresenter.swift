import AppKit

@MainActor
enum FeatureSessionCleanupAlertPresenter {
    static func present(_ cleanupReport: FeatureSessionCleanupReport) {
        guard cleanupReport.hasIssues else { return }

        let alert = NSAlert()
        alert.messageText = cleanupReport.alertTitle
        alert.informativeText = cleanupReport.alertMessage
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "OK")
        alert.buttons[0].keyEquivalent = "\r"

        if let window = NSApp.keyWindow ?? NSApp.mainWindow,
           window.attachedSheet == nil
        {
            alert.beginSheetModal(for: window)
            return
        }

        alert.runModal()
    }
}
