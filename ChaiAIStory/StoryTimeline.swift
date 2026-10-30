import SwiftUI
import StoryCore

struct StoryTimeline: View {
    @EnvironmentObject var model: AppModel
    @State private var action = ""
    @State private var nearBottom = true
    @State private var detail: String?
    @State private var expandedUsage = false
    var body: some View {
        VStack(spacing: 0) {
            if let visible = model.projection {
                HStack {
                    Button { detail = visible.location + "\n" + visible.time } label: { Label(visible.location, systemImage: "location").lineLimit(1) }
                    Spacer()
                    Button { detail = visible.symptoms } label: { Label(visible.sensation, systemImage: "waveform.path.ecg").lineLimit(1) }
                }.font(.subheadline).padding(12).background(.ultraThinMaterial)
            }
            GeometryReader { viewport in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            if (model.turns.first?.number ?? 1) > 1 { Button("載入較早的故事") { model.loadOlder() }.frame(maxWidth: .infinity) }
                            ForEach(model.turns) { turn in
                                VStack(alignment: .leading, spacing: 16) {
                                    Text("第 \(turn.number) 回").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                                    HStack { Spacer(minLength: 45); Text(turn.action).padding(13).background(Color.storyGold.opacity(0.18), in: RoundedRectangle(cornerRadius: 16)) }
                                    HStack { Text(turn.narrative).lineSpacing(7).textSelection(.enabled).padding(15).background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16)); Spacer(minLength: 18) }
                                        .contextMenu { Button("複製段落", systemImage: "doc.on.doc") { UIPasteboard.general.string = turn.narrative } }
                                }.id(turn.id)
                            }
                            if let pending = model.pendingAction {
                                HStack { Spacer(minLength: 45); Text(pending).padding(13).background(Color.storyGold.opacity(0.10), in: RoundedRectangle(cornerRadius: 16)).opacity(0.65) }
                                Text("待提交，停止後將移除").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            if model.busy { HStack { ProgressView(); Text(model.phase).font(.subheadline).foregroundStyle(.secondary); Spacer(); Button("停止") { model.stop() } } }
                            Color.clear.frame(height: 1).id("bottom").background(GeometryReader { geometry in Color.clear.preference(key: BottomPosition.self, value: geometry.frame(in: .named("timeline")).maxY) })
                        }.padding(16)
                    }.coordinateSpace(name: "timeline")
                    .scrollDismissesKeyboard(.interactively)
                    .onPreferenceChange(BottomPosition.self) { nearBottom = $0 < viewport.size.height + 100 }
                    .onChange(of: model.turns.last?.id) { _, _ in if nearBottom { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } } }
                    .onChange(of: model.busy) { _, _ in if nearBottom { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } } }
                    .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                    .overlay(alignment: .bottomTrailing) {
                        if !nearBottom { Button { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } } label: { Label("跳到最新", systemImage: "arrow.down") }.buttonStyle(.borderedProminent).padding() }
                    }
                }
            }
            VStack(spacing: 9) {
                if model.projection?.dead == true { Label("人生已結束 · 可在設定匯出紀念故事", systemImage: "book.closed").font(.subheadline).padding(8) }
                else {
                    if !model.busy, let choices = model.turns.last?.choices {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) { ForEach(choices, id: \.self) { choice in Button(choice) { action = ""; model.generate(action: choice) }.buttonStyle(.bordered).fixedSize(horizontal: true, vertical: false) } }
                        }
                    }
                    HStack(alignment: .bottom) {
                        TextField("自由輸入你的行動…", text: $action, axis: .vertical).lineLimit(1...4).padding(11).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12)).disabled(model.busy)
                        Button { let value = action; action = ""; model.generate(action: value) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }.disabled(model.busy || action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("送出行動")
                    }
                }
                DisclosureGroup(isExpanded: $expandedUsage) {
                    ProgressView(value: min(model.totalCost, max(0.01, model.preferences.budget)), total: max(0.01, model.preferences.budget))
                    Text("手動預算估算剩餘 $\(max(0, model.preferences.budget - model.totalCost), specifier: "%.4f")\(model.unknownCost ? "；另有未知費用" : "")，非官方額度。").font(.caption2).foregroundStyle(.secondary)
                } label: { Text("本機估計用量 $\(model.totalCost, specifier: "%.4f")").font(.caption2).foregroundStyle(.secondary) }
            }.padding(.horizontal, 14).padding(.vertical, 10).background(.ultraThinMaterial)
        }
        .background(Color.storyInk)
        .navigationTitle("\(model.session?.settings.name ?? "")的故事").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("首頁", systemImage: "house") { model.showGame = false } } }
        .sheet(isPresented: Binding(get: { detail != nil }, set: { if !$0 { detail = nil } })) { NavigationStack { ScrollView { Text(detail ?? "").frame(maxWidth: .infinity, alignment: .leading).padding(24) }.navigationTitle("主角感知").toolbar { Button("完成") { detail = nil } } }.presentationDetents([.medium, .large]) }
    }
}
private struct BottomPosition: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
