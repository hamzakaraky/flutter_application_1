import AppIntents
import Foundation

@available(iOS 16.0, *)
struct ActivateSilentIntent: AppIntent {
    static var title: LocalizedStringResource = "Activate Smart Silent Mode"
    static var description = IntentDescription(
        "Activates silent Focus Mode when SmartSilent detects the smart room beacon.",
        categoryName: "Smart Room"
    )
    static var isDiscoverable: Bool = true
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: "Silent mode activated.")
    }
}

@available(iOS 16.0, *)
struct DeactivateSilentIntent: AppIntent {
    static var title: LocalizedStringResource = "Deactivate Smart Silent Mode"
    static var description = IntentDescription(
        "Deactivates silent Focus Mode when you leave the room.",
        categoryName: "Smart Room"
    )
    static var isDiscoverable: Bool = true
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: "Sound restored to normal.")
    }
}

@available(iOS 16.4, *)
struct SmartSilentShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ActivateSilentIntent(),
            phrases: [
                "Activate \(.applicationName)",
                "Enable \(.applicationName) silent mode"
            ],
            shortTitle: "Activate Silent",
            systemImageName: "bell.slash.fill"
        )
        AppShortcut(
            intent: DeactivateSilentIntent(),
            phrases: [
                "Deactivate \(.applicationName)",
                "Disable \(.applicationName) silent mode"
            ],
            shortTitle: "Deactivate Silent",
            systemImageName: "bell.fill"
        )
    }
}