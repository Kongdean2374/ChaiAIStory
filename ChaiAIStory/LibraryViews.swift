import SwiftUI
import StoryCore

struct InventoryView: View {
    @EnvironmentObject var model: AppModel
    @State private var search = ""
    @State private var category = "全部"
    @State private var selected: InventoryEntry?
    @State private var target = ""
    var items: [InventoryEntry] { (model.projection?.inventory ?? []).filter { (category == "全部" || $0.category == category) && (search.isEmpty || ($0.name + $0.detail).localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        List {
            Section {
                Picker("分類", selection: $category) { Text("全部").tag("全部"); ForEach(Array(Set(model.projection?.inventory.map(\.category) ?? [])).sorted(), id: \.self) { Text($0).tag($0) } }
            }
            if items.isEmpty { ContentUnavailableView("沒有已知物品", systemImage: "bag", description: Text("探索或清點後發現的物品會顯示於此。")) }
            ForEach(items) { item in
                Button { selected = item; target = "" } label: {
                    HStack { Image(systemName: item.equippedSlot.isEmpty ? "cube" : "shield").foregroundStyle(Color.storyGold); VStack(alignment: .leading) { Text(item.name); if !item.equippedSlot.isEmpty { Text("裝備於：" + item.equippedSlot).font(.caption).foregroundStyle(.secondary) } }; Spacer(); Text("×\(item.quantity)").foregroundStyle(.secondary) }
                }
            }
        }.searchable(text: $search, prompt: "搜尋已知物品").navigationTitle("背包")
        .sheet(item: $selected) { item in
            NavigationStack {
                Form {
                    Section(item.name) { Text(item.detail.isEmpty ? "尚無更多可知細節。" : item.detail); LabeledContent("數量", value: String(item.quantity)); LabeledContent("分類", value: item.category) }
                    Section("行動目標") { TextField("例如：掌櫃、自己、地面（可留空）", text: $target) }
                    Section("嘗試互動") {
                        ForEach(item.operations, id: \.self) { operation in
                            Button(operation) {
                                let suffix = target.isEmpty ? "" : "，目標：\(target)"
                                selected = nil; model.selectedTab = 0
                                model.generate(action: "嘗試\(operation)「\(item.name)」（物品識別：\(item.id)）\(suffix)")
                            }.disabled(model.busy || model.projection?.dead == true)
                        }
                    }
                    Section { Text("查看背包不呼叫 API；有敘事後果的互動由 AI 推演，成功提交後才變動物品。浪費、失敗或失去物品皆有可能。").font(.footnote).foregroundStyle(.secondary) }
                }.navigationTitle("物品詳情").toolbar { Button("完成") { selected = nil } }
            }.presentationDetents([.medium, .large])
        }
    }
}
struct CharacterView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        List {
            if let settings = model.session?.settings, let visible = model.projection {
                Section("\(settings.name) · \(settings.identity)") {
                    LabeledContent("年齡", value: String(settings.age)); LabeledContent("代稱", value: settings.pronouns)
                    Text(settings.appearance.isEmpty ? "外貌未設定" : settings.appearance)
                    Text(settings.personality)
                }
                Section("主觀身體感受") { Label(visible.sensation, systemImage: "waveform.path.ecg"); Text(visible.symptoms); Text(visible.location); Text(visible.time) }
                Section("已知背景") { Text(settings.background); Text(settings.family) }
                KnowledgeSection(title: "能力、名聲與關係", entries: visible.journal.filter { entry in
                    model.session?.world.entities.contains(where: { $0.id == entry.subjectID && [.skill, .relationship].contains($0.kind) }) == true
                })
                if visible.dead { Section { Label("人生結局 · 唯讀紀錄", systemImage: "book.closed") } }
            }
        }.navigationTitle("角色")
    }
}
struct WorldView: View {
    @EnvironmentObject var model: AppModel
    @State private var search = ""
    @State private var filter: EntityKind? = nil
    var entries: [KnowledgeEntry] {
        (model.projection?.journal ?? []).filter { entry in
            (search.isEmpty || (entry.title + entry.text).localizedCaseInsensitiveContains(search)) && (filter == nil || model.session?.world.entities.contains(where: { $0.id == entry.subjectID && $0.kind == filter }) == true)
        }
    }
    var body: some View {
        List {
            Section {
                Picker("資訊類別", selection: $filter) {
                    Text("全部已知情報").tag(Optional<EntityKind>.none)
                    Text("地點").tag(Optional(EntityKind.location)); Text("人物").tag(Optional(EntityKind.npc)); Text("勢力").tag(Optional(EntityKind.faction))
                    Text("任務").tag(Optional(EntityKind.quest)); Text("日誌").tag(Optional(EntityKind.journal)); Text("伏筆").tag(Optional(EntityKind.thread))
                }
            }
            if entries.isEmpty { ContentUnavailableView("尚無已知情報", systemImage: "map", description: Text("主角親歷、被告知或合理推測的事物將記錄於此。")) }
            KnowledgeSection(title: "你所知道的世界", entries: entries)
        }.navigationTitle("世界見聞").searchable(text: $search, prompt: "搜尋可知資訊")
    }
}
struct KnowledgeSection: View {
    let title: String
    let entries: [KnowledgeEntry]
    var body: some View {
        Section(title) {
            ForEach(entries) { entry in
                DisclosureGroup(entry.title) {
                    Text(entry.text).textSelection(.enabled)
                    Text("來源：\(entry.source) · \(entry.confidence < 0.5 ? "有待查證" : entry.confidence < 0.9 ? "可能可信" : "主角確信")").font(.caption).foregroundStyle(.secondary)
                    Text("主角的認知可能與真相不同。").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
