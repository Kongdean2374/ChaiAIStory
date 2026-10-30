import SwiftUI
import StoryCore

struct StoryTimeline: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var action = ""
    @State private var nearBottom = true
    @State private var showHealth = false
    @State private var showLocation = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if (model.turns.first?.number ?? 1) > 1 {
                            Button("載入較早的故事") { model.loadOlder() }.frame(maxWidth: .infinity, minHeight: 44)
                        }
                        ForEach(model.turns) { turn in
                            VStack(spacing: 10) {
                                Text("第 \(turn.number) 回").font(.caption2).foregroundStyle(.secondary)
                                StoryBubble(text: turn.action, isPlayer: true, size: model.readingSize, availableWidth: viewport.size.width - 24)
                                StoryBubble(text: turn.narrative, isPlayer: false, size: model.readingSize, availableWidth: viewport.size.width - 24)
                                    .contextMenu { Button("複製段落", systemImage: "doc.on.doc") { UIPasteboard.general.string = turn.narrative } }
                            }.id(turn.id)
                        }
                        if let pending = model.pendingAction {
                            StoryBubble(text: pending, isPlayer: true, size: model.readingSize, availableWidth: viewport.size.width - 24).opacity(0.65)
                            Text("待提交").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        if model.busy {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { ProgressView(); Text("AI 正在思考…").font(.subheadline).foregroundStyle(.secondary); Spacer(); Button("停止") { model.stop() }.frame(minWidth: 44, minHeight: 44) }
                                if model.phase.contains("篇幅") { Text(model.phase).font(.caption).foregroundStyle(.secondary) }
                            }
                        } else if model.projection?.dead != true, let choices = model.turns.last?.choices {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("接下來，你想…").font(.caption).foregroundStyle(.secondary)
                                ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                                    Button {
                                        inputFocused = false; action = ""; model.generate(action: choice)
                                    } label: {
                                        Text(choice).font(.subheadline).multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                            .padding(.horizontal, 12).padding(.vertical, 7)
                                            .background(Color.storyGold.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.storyGold.opacity(0.20)))
                                    }.buttonStyle(.plain).foregroundStyle(.primary).disabled(model.busy)
                                        .accessibilityIdentifier("storyChoice\(index)")
                                }
                            }.id("choices")
                        }
                        Color.clear.frame(height: 1).id("bottom")
                            .background(GeometryReader { geometry in Color.clear.preference(key: BottomPosition.self, value: geometry.frame(in: .named("timeline")).maxY) })
                    }.padding(.horizontal, 12).padding(.vertical, 10)
                }.coordinateSpace(name: "timeline").accessibilityIdentifier("storyScroll")
                    .scrollDismissesKeyboard(.interactively)
                    .onPreferenceChange(BottomPosition.self) { nearBottom = $0 < viewport.size.height + 70 }
                    .onChange(of: model.turns.last?.id) { _, _ in if nearBottom { scrollToLatest(proxy) } }
                    .onChange(of: model.busy) { _, _ in if nearBottom { scrollToLatest(proxy) } }
                    .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                    .overlay(alignment: .bottomTrailing) {
                        if !nearBottom {
                            Button { scrollToLatest(proxy) } label: { Label("跳到最新", systemImage: "arrow.down").font(.caption) }
                                .buttonStyle(.borderedProminent).padding(10).accessibilityIdentifier("jumpLatest")
                        }
                    }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { statusCards }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .background(Color.storyInk)
        .navigationTitle("故事").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("首頁", systemImage: "house") { model.showGame = false } }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("收起鍵盤") { inputFocused = false } }
        }
        .sheet(isPresented: $showHealth) { HealthSheet() }
        .sheet(isPresented: $showLocation) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(model.projection?.location ?? "不明之處").font(.headline)
                        Text(model.projection?.time ?? "時間不明").font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                }.navigationTitle("所在地").navigationBarTitleDisplayMode(.inline).toolbar { Button("完成") { showLocation = false } }
            }.presentationDetents([.medium, .large])
        }
    }
    @ViewBuilder private var statusCards: some View {
        if let visible = model.projection {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
            layout {
                StatusCard(title: "所在地", value: visible.location, symbol: "location", identifier: "locationCard") { showLocation = true }
                StatusCard(title: "健康", value: visible.sensation, symbol: "waveform.path.ecg", identifier: "healthCard") { showHealth = true }
            }.padding(.horizontal, 12).padding(.vertical, 8).background(.ultraThinMaterial)
        }
    }
    private var composer: some View {
        VStack(spacing: 0) {
            Divider()
            if model.projection?.dead == true {
                Label("人生已結束 · 可於設定匯出紀念故事", systemImage: "book.closed").font(.footnote).padding(12)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("自由輸入你的行動…", text: $action, axis: .vertical)
                        .font(.body).lineLimit(1...3).focused($inputFocused)
                        .padding(10).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        .disabled(model.busy).accessibilityIdentifier("storyInput")
                    Button {
                        let text = action; action = ""; inputFocused = false; model.generate(action: text)
                    } label: {
                        Image(systemName: "arrow.up").font(.headline).frame(width: 44, height: 44)
                            .background(Color.storyGold.opacity(0.2), in: Circle())
                    }.disabled(model.busy || action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("送出行動").accessibilityIdentifier("sendAction")
                }.padding(.horizontal, 12).padding(.vertical, 8)
            }
        }.background(.ultraThinMaterial)
    }
    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        if reduceMotion { proxy.scrollTo("bottom", anchor: .bottom) }
        else { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) } }
    }
}
private struct StoryBubble: View {
    let text: String
    let isPlayer: Bool
    let availableWidth: CGFloat
    @ScaledMetric(relativeTo: .body) private var fontSize: CGFloat
    init(text: String, isPlayer: Bool, size: Double, availableWidth: CGFloat) {
        self.text = text; self.isPlayer = isPlayer; self.availableWidth = availableWidth
        _fontSize = ScaledMetric(wrappedValue: CGFloat(size), relativeTo: .body)
    }
    var body: some View {
        Text(text).font(.system(size: fontSize)).lineSpacing(3)
            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled).padding(.horizontal, 12).padding(.vertical, 10)
            .background(isPlayer ? Color.storyGold.opacity(0.12) : Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            .frame(maxWidth: max(100, availableWidth * 0.92), alignment: isPlayer ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: isPlayer ? .trailing : .leading)
    }
}
private struct BottomPosition: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
