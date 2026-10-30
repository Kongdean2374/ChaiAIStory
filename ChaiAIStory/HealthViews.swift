import SwiftUI
import StoryCore

struct HealthDetails: View {
    let health: HealthProjection
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if health.isEnding { Label("人生結局 · 最後的感知紀錄", systemImage: "book.closed").font(.subheadline).foregroundStyle(.secondary) }
            Text(health.feeling).font(.title3.weight(.semibold)).accessibilityIdentifier("healthFeeling")
            VStack(alignment: .leading, spacing: 8) {
                Text("已記錄的身體感受").font(.caption).foregroundStyle(.secondary)
                Text(health.symptoms).font(.body).lineSpacing(4).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("healthSymptoms")
            }
            Text("來自已儲存的主角感知。查看不推進劇情，也不使用 API。")
                .font(.footnote).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct HealthSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                if let session = model.session { HealthDetails(health: HealthProjection(session)).padding(20) }
            }.navigationTitle("身體狀態").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("完成") { dismiss() }.accessibilityIdentifier("closeHealth") }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}
struct StatusCard: View {
    let title: String
    let value: String
    let symbol: String
    let identifier: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Label(title, systemImage: symbol).font(.caption.weight(.medium)).foregroundStyle(Color.storyGold)
                Text(value).font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(identifier)
            .accessibilityLabel(title + "，" + value).accessibilityHint("點兩下查看詳情")
    }
}
