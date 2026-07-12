import Foundation

extension WidgetSnapshotStore {
    static func save(accounts: [AccountRecord]) {
        guard let account = accounts.first(where: \.isCurrent) ?? accounts.first else { return }
        save(WidgetQuotaSnapshot(
            displayName: account.displayName,
            plan: account.plan,
            primaryRemainPercent: account.usage?.primaryRemainPercent,
            primaryResetsAt: account.usage?.primaryResetsAt,
            secondaryRemainPercent: account.usage?.secondaryRemainPercent,
            secondaryResetsAt: account.usage?.secondaryResetsAt,
            capturedAt: account.usage?.capturedAt,
            status: account.status,
            lastError: account.lastError
        ))
    }
}
