import SwiftUI
import StoryCore

struct NarrativeRangeEditor: View {
    @Binding var range: NarrativeRange
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("每回合小說正文：\(range.label)").font(.headline).accessibilityIdentifier("effectiveNarrativeRange")
            Menu("選擇常用篇幅") {
                ForEach([NarrativeRange(minimum: 20, maximum: 50), .init(minimum: 50, maximum: 120), .init(), .init(minimum: 250, maximum: 500)], id: \.minimum) { option in
                    Button(option.label) { range = option }
                }
            }
            Stepper("最少 \(range.minimum) 字", value: $range.minimum, in: 20...range.maximum, step: 10).accessibilityIdentifier("minimumLength")
            Stepper("最多 \(range.maximum) 字", value: $range.maximum, in: range.minimum...2000, step: 10).accessibilityIdentifier("maximumLength")
            Text("優先約 \(range.preferred.lowerBound)～\(range.preferred.upperBound) 字。只計正文漢字（含擴展字）；標點、空白、英文、數字、符號與選項不計。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
