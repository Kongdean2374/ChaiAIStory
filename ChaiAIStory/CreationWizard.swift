import SwiftUI
import StoryCore

struct CreationWizard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    let genres = ["武俠", "仙俠", "玄幻", "奇幻", "科幻", "末日", "歷史", "現代", "自訂"]
    let titles = ["故事類型", "世界模板", "主角設定", "世界風格", "敘事設定", "總覽確認"]
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: 6).padding()
                Text("\(step + 1) / 6 · \(titles[step])").font(.headline)
                Form {
                    switch step {
                    case 0:
                        Section("選擇世界的可能") {
                            Picker("故事類型", selection: $model.draft.genre) { ForEach(genres, id: \.self) { Text($0).tag($0) } }.pickerStyle(.inline)
                            if !genres.dropLast().contains(model.draft.genre) { TextField("自訂題材", text: $model.draft.genre) }
                        }
                    case 1:
                        Section("世界模板") {
                            ForEach(["江湖殘卷・無名之路", "亂世江湖", "門派紛爭", "平凡人生", "朝堂暗鬥", "星際流亡", "末日求生", "AI 自由生成"], id: \.self) { value in
                                Button { model.draft.template = value } label: { HStack { Text(value); Spacer(); if model.draft.template == value { Image(systemName: "checkmark") } } }
                            }
                            TextField("自由修改模板", text: $model.draft.template)
                        }
                        Section { Text("世界基礎物理與題材規則開局後固定；人物、勢力與事件隨行動演化。").foregroundStyle(.secondary) }
                    case 2:
                        Section("主角模板") {
                            Menu("套用背景模板") {
                                Button("無名旅人") { model.draft.identity = "旅人"; model.draft.aptitude = "均衡" }
                                Button("平凡居民") { model.draft.identity = "居民"; model.draft.aptitude = "觀察與交涉" }
                                Button("失去記憶的人") { model.draft.background = "未知／留待故事揭露"; model.draft.family = "未知／留待故事揭露" }
                            }
                        }
                        Section("你是誰") {
                            TextField("姓名", text: $model.draft.name); TextField("代稱", text: $model.draft.pronouns)
                            TextField("性別", text: $model.draft.gender); Stepper("年齡：\(model.draft.age)", value: $model.draft.age, in: 1...120)
                            TextField("外貌", text: $model.draft.appearance, axis: .vertical)
                            TextField("身份", text: $model.draft.identity)
                            TextField("身世（可留未知）", text: $model.draft.background, axis: .vertical)
                            TextField("家庭（可留未知）", text: $model.draft.family, axis: .vertical)
                            TextField("性格", text: $model.draft.personality); TextField("初始居所", text: $model.draft.residence)
                            TextField("能力傾向", text: $model.draft.aptitude)
                        }
                    case 3:
                        Section("世界強度") {
                            settingSlider("寫實程度", value: $model.draft.realism)
                            settingSlider("危險程度", value: $model.draft.danger)
                            settingSlider("NPC 自主程度", value: $model.draft.autonomy)
                            settingSlider("戰鬥比例", value: $model.draft.combat)
                            settingSlider("情感／社交比例", value: $model.draft.social)
                            settingSlider("世界節奏", value: $model.draft.pace)
                        }
                    case 4:
                        Section("繁體中文 · 沉浸式主角視角") {
                            Picker("目標篇幅", selection: $model.draft.length) {
                                Text("極短 · 約 20–50 字").tag(35); Text("短篇 · 約 50–120 字（推薦）").tag(120)
                                Text("標準 · 約 120–250 字").tag(200); Text("詳細 · 約 250–500 字").tag(400)
                                Text("自訂目前值 · \(model.draft.length) 字").tag(model.draft.length)
                            }
                            Stepper("自訂：\(model.draft.length) 字", value: $model.draft.length, in: 20...2000, step: 10)
                            Text("篇幅以中文可見字數約值計算，不是 Token。重要事件可能略超出。")
                        }
                    default:
                        Section("確認本次世界") {
                            LabeledContent("故事", value: model.draft.genre); LabeledContent("模板", value: model.draft.template)
                            LabeledContent("主角", value: "\(model.draft.name) · \(model.draft.age) 歲")
                            LabeledContent("身份", value: model.draft.identity)
                            LabeledContent("身世", value: model.draft.background); LabeledContent("家庭", value: model.draft.family)
                            LabeledContent("敘事目標", value: "約 \(model.draft.length) 字")
                        }
                        Section {
                            Text("AI 將一次生成世界、人物、初始狀態、第一段故事與選項。驗證成功後才建立唯一正式存檔；失敗保留草稿。")
                            if !model.hasKey { Label("請先回首頁的 API 設定儲存金鑰。", systemImage: "key") }
                            if model.busy { ProgressView(model.phase); Button("停止", role: .destructive) { model.stop() } }
                        }
                    }
                }.scrollDismissesKeyboard(.interactively)
                HStack {
                    Button("上一步") { step -= 1 }.disabled(step == 0 || model.busy)
                    Spacer()
                    if step < 5 { Button("下一步") { next() }.buttonStyle(.borderedProminent).disabled(model.busy) }
                    else { Button("生成世界") { model.preferences.narrativeLength = model.draft.length; model.generate(action: "建立全新獨立世界，開始我的人生。", initial: true) }.buttonStyle(.borderedProminent).disabled(model.busy || !model.hasKey) }
                }.padding()
            }
            .navigationTitle("建立你的故事").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("儲存草稿並離開") { model.saveDraft(); dismiss() }.disabled(model.busy) } }
        }.interactiveDismissDisabled(model.busy).onDisappear { model.saveDraft() }
    }
    private func next() {
        do { try model.draft.validate(); model.saveDraft(); step += 1 } catch { model.report(error) }
    }
    private func settingSlider(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading) { Text(title); Slider(value: value, in: 0...1, step: 0.1).accessibilityLabel(title) }
    }
}
