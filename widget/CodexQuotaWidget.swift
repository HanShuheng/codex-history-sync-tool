import SwiftUI
import WidgetKit

struct CodexQuotaEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetQuotaSnapshot?
}

struct CodexQuotaProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexQuotaEntry {
        CodexQuotaEntry(date: Date(), snapshot: WidgetQuotaSnapshot(
            displayName: "CODEX", plan: "PRO", primaryRemainPercent: 74,
            primaryResetsAt: Date().addingTimeInterval(3600), secondaryRemainPercent: 42,
            secondaryResetsAt: Date().addingTimeInterval(86400 * 3), capturedAt: Date(), status: "active", lastError: nil
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexQuotaEntry) -> Void) {
        completion(CodexQuotaEntry(date: Date(), snapshot: WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexQuotaEntry>) -> Void) {
        let entry = CodexQuotaEntry(date: Date(), snapshot: WidgetSnapshotStore.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct CodexQuotaWidgetView: View {
    let entry: CodexQuotaEntry

    private var isChinese: Bool {
        Locale.current.language.languageCode?.identifier == "zh"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let snapshot = entry.snapshot {
                Text(snapshot.displayName).font(.headline)
                Text(snapshot.plan ?? "Codex")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                metric(isChinese ? "5 小时" : "5 hours", snapshot.primaryRemainPercent)
                metric(isChinese ? "7 天" : "7 days", snapshot.secondaryRemainPercent)
                if let capturedAt = snapshot.capturedAt {
                    Text(capturedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let error = snapshot.lastError {
                    Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(2)
                }
            } else {
                Text(isChinese ? "暂无额度数据" : "No quota data").font(.headline)
                Text(isChinese ? "请先打开 CodexHistorySync 刷新账号额度。" : "Open CodexHistorySync to refresh quota first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .widgetBackground()
    }

    private func metric(_ title: String, _ value: Double?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value.map { String(format: "%.0f%%", max(0, min(100, $0))) } ?? "未知")
                .font(.headline.monospacedDigit())
        }
    }
}

private extension View {
    @ViewBuilder
    func widgetBackground() -> some View {
        if #available(macOS 14.0, *) {
            containerBackground(.fill.tertiary, for: .widget)
        } else {
            background(.regularMaterial)
        }
    }
}

@main
struct CodexQuotaWidgetBundle: WidgetBundle {
    var body: some Widget {
        StaticCodexQuotaWidget()
    }
}

struct StaticCodexQuotaWidget: Widget {
    let kind = "CodexQuotaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodexQuotaProvider()) { entry in
            CodexQuotaWidgetView(entry: entry)
        }
        .configurationDisplayName("Codex 额度")
        .description("在桌面组件中查看 Codex 当前额度。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
