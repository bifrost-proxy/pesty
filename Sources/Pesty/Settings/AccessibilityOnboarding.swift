import Observation

enum AccessibilityOnboardingReason: Equatable {
    case firstInstall
    case update
}

enum AccessibilityOnboardingPolicy {
    static func reason(
        hasPreviouslyOnboarded: Bool,
        completedBuild: String?,
        currentBuild: String,
        isUpdateRelaunch: Bool
    ) -> AccessibilityOnboardingReason? {
        guard completedBuild != currentBuild else {
            return nil
        }
        if isUpdateRelaunch {
            return .update
        }
        return hasPreviouslyOnboarded ? .update : .firstInstall
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case about

    var id: String { rawValue }
}

@Observable
@MainActor
final class SettingsWindowState {
    var selectedPane: SettingsPane = .general
    private(set) var accessibilityOnboardingReason:
        AccessibilityOnboardingReason?

    func presentAccessibilityOnboarding(
        reason: AccessibilityOnboardingReason
    ) {
        accessibilityOnboardingReason = reason
        selectedPane = .general
    }
}
