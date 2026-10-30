import SwiftUI
import UniformTypeIdentifiers
import StoryCore

struct SharedFile: Identifiable { let id = UUID(); let url: URL }
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var visibleKey = false
    @State private var deleteFirst = false
    @State private var deleteFinal = false
    @State private var share: SharedFile?
    @State private var importFile = false
    @State private var deleteKey = false
    @State private var editedRange = NarrativeRange()
    var body: some View {
        Form {
            Section {
                Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")（Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")）")
                    .font(.headline).accessibilityIdentifier("appVersion")
            }
            Section("閱讀") {
                Stepper("閱讀字級：\(Int(model.readingSize))", value: Binding(get: { model.readingSize }, set: { model.preferences.readingSize = $0 }), in: 14...22)
                Text("同時遵循 iPhone 的動態字級設定。").font(.footnote).foregroundStyle(.secondary)
            }
            Section(model.session == nil ? "開局草稿的正文篇幅" : "目前存檔的正文篇幅") {
                Text("目前有效：\(model.effectiveNarrativeRange.label)").accessibilityIdentifier("savedNarrativeRange")
                NarrativeRangeEditor(range: $editedRange)
                Button("儲存篇幅設定") { model.applyNarrativeRange(editedRange) }.disabled(model.busy || model.session?.dead == true)
                Text("正常回合提交前會檢查漢字數；不足或超出時最多修正一次，可能增加 API 費用。修正失敗整輪作廢。拒絕、持續昏迷與人生結局可採較短篇幅；記憶重整不受正文長度限制。").font(.footnote).foregroundStyle(.secondary)
                NavigationLink("已提交篇幅診斷") {
                    List(model.turns.reversed()) { turn in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("第 \(turn.number) 回").font(.headline)
                            Text("預期：\(turn.lengthReport?.expected.label ?? "舊版未記錄")；實際：\(NarrativePolicy.count(turn.narrative)) 字")
                            if let report = turn.lengthReport {
                                Text("修正請求：\(report.repairCount) 次\(report.exception.map { " · " + $0 } ?? "")").font(.caption)
                            }
                        }
                    }.navigationTitle("正文篇幅").onAppear { model.loadOlder() }
                }
            }.disabled(model.busy)
            Section {
                HStack {
                    Group { if visibleKey { TextField("貼上自己的 API Key", text: $key) } else { SecureField("貼上自己的 API Key", text: $key) } }
                        .textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    Button { visibleKey.toggle() } label: { Image(systemName: visibleKey ? "eye.slash" : "eye") }.accessibilityLabel(visibleKey ? "隱藏金鑰" : "顯示金鑰")
                }
                HStack {
                    Button("貼上") { key = UIPasteboard.general.string ?? "" }
                    Spacer(); Button("儲存") { model.saveKey(key); key = "" }.disabled(key.isEmpty || model.busy)
                }
                Label(model.hasKey ? "此裝置已儲存金鑰" : "尚未儲存金鑰", systemImage: model.hasKey ? "key.fill" : "key")
                Button("驗證連線與所選模型（可能計費）") { model.verify() }.disabled(model.busy || !model.hasKey)
                Button("刪除 API Key", role: .destructive) { deleteKey = true }.disabled(model.busy || !model.hasKey)
            } header: { Text("OpenAI · 自備 API Key") } footer: { Text("金鑰僅存於此裝置 Keychain，不進入備份或 GitHub。手機直連仍可能遭擷取；建議使用獨立 project key、最低權限及官方費用監控／上限。") }
            Section("模型與能力") {
                TextField("模型 ID（支援手動輸入）", text: $model.preferences.model).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(model.busy)
                Button("取得可用模型清單") { Task { await model.refreshModels() } }.disabled(model.busy || !model.hasKey)
                if !model.models.isEmpty {
                    Picker("從清單選擇", selection: $model.preferences.model) {
                        Text(model.preferences.model).tag(model.preferences.model)
                        ForEach(model.models.filter { $0 != model.preferences.model }, id: \.self) { Text($0 + " · 能力待驗證").tag($0) }
                    }.disabled(model.busy)
                }
                Toggle("使用伺服端背景生成", isOn: $model.preferences.background).disabled(model.busy)
                Text("模型清單不提供完整能力欄位。請用實際小型 Responses 請求驗證結構化輸出及所選背景模式；不支援背景時可手動關閉，僅限前景生成，切背景可能中斷且無法追蹤。程式不會自動更換模型或重送。").font(.footnote).foregroundStyle(.secondary)
                if model.busy { ProgressView(model.phase); Button("停止本次請求", role: .destructive) { model.stop() } }
            }
            Section("敘事與江湖記憶同步") {
                Stepper(model.preferences.syncEvery == 0 ? "自動重整：關閉" : "每 \(model.preferences.syncEvery) 回合重整", value: $model.preferences.syncEvery, in: 0...200, step: 5)
                Toggle("恢復存檔時重整", isOn: $model.preferences.syncOnRestore)
                Toggle("驗證發現矛盾時重整", isOn: $model.preferences.syncOnConflict)
                Button("重整 AI 記憶（不推進劇情）") { model.generate(action: "手動盤點本局已提交世界與記憶", memoryOnly: true) }.disabled(model.busy || model.session == nil || !model.hasKey)
                Text(model.memoryDiagnostic).font(.footnote).foregroundStyle(.secondary)
                Text("重整會傳送本局完整已提交狀態並產生 Token 成本。診斷保留於派生記憶，不修改世界，也不公開可能劇透的摘要內容。").font(.caption).foregroundStyle(.secondary)
            }
            Section("用量與本機估算 · USD") {
                LabeledContent("累計估計費用", value: String(format: "$%.6f", model.totalCost))
                if model.unknownCost { Label("另有未知用量／價格，可能計費。", systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
                HStack { Text("手動預算起始值"); TextField("USD", value: $model.preferences.budget, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                HStack { Text("費用警戒（0 關閉）"); TextField("USD", value: $model.preferences.warning, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("估算剩餘（非官方餘額）", value: String(format: "$%.4f", max(0, model.preferences.budget - model.totalCost)))
                DisclosureGroup("價格表（每百萬 Token；請依官方價格更新）") {
                    TextField("此價格適用模型 ID", text: $model.preferences.pricingModel).textInputAutocapitalization(.never)
                    HStack { Text("輸入"); TextField("USD", value: $model.preferences.pricing.inputPerMillion, format: .number).keyboardType(.decimalPad) }
                    HStack { Text("快取輸入"); TextField("USD", value: $model.preferences.pricing.cachedPerMillion, format: .number).keyboardType(.decimalPad) }
                    HStack { Text("輸出"); TextField("USD", value: $model.preferences.pricing.outputPerMillion, format: .number).keyboardType(.decimalPad) }
                    Text("預置 gpt-4.1-mini 價格僅供估算，其他模型價格未知時不顯示 $0；歷史請求保留當時估價。").font(.caption)
                    Link("官方價格", destination: URL(string: "https://developers.openai.com/api/docs/pricing")!)
                }
                NavigationLink("請求明細（含失敗及取消）") {
                    List(model.usage) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.model).font(.headline)
                            Text(item.date, style: .date).font(.caption)
                            Text("輸入 \(item.inputTokens.map(String.init) ?? "未知") · 輸出 \(item.outputTokens.map(String.init) ?? "未知")")
                            Text(item.estimatedUSD.map { String(format: "$%.6f（估計）", $0) } ?? "費用未知／可能計費")
                            Text(item.note).font(.caption).foregroundStyle(.secondary)
                        }
                    }.navigationTitle("API 用量")
                }
            }
            Section("資料管理") {
                Button("匯出已完成小說／結局（Markdown）") { export(false) }.disabled(model.session == nil)
                Button("匯出完整存檔備份（含隱藏真相）") { export(true) }.disabled(model.session == nil || model.busy)
                Button("匯入備份（需先刪除現有遊戲）") { importFile = true }.disabled(model.session != nil || model.busy)
                if model.session != nil { Button("刪除角色，重新開始", role: .destructive) { deleteFirst = true } }
                Text("備份包含劇透及本局私人故事，請自行保管。匯入只建立一個本機遊戲，不能合併不同世界；API Key 不包含在內。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("網路、隱私與平台限制") {
                Text("生成只直連 api.openai.com，會將本局故事及必要世界資料送交 OpenAI。既有故事與角色可離線讀取，新劇情不能離線生成。")
                Text("切背景／鎖屏時讓伺服端繼續生成；iOS 不保證背景收取資料。回前景優先查詢同一 responseId，約九分鐘內嘗試恢復（平台暫存約十分鐘，可能變更）。store=false 的背景請求仍可能有暫時伺服端留存。")
                Text("強制關閉或系統終止無法可靠區分，冷啟動一律作廢未提交生成；無法保證即時取消遠端運算或免計費。送出後尚未取得回應 ID 的請求不能追蹤，不會自動重送。")
                Text("未簽署 IPA 必須自行使用相容方式簽署才能安裝；本專案不內含憑證或綁定簽署服務。")
                Link("公開原始碼", destination: URL(string: "https://github.com/Kongdean2374/ChaiAIStory")!)
            }.font(.footnote)
        }.navigationTitle("設定").toolbar { if !model.showGame { Button("完成") { dismiss() } } }
        .sheet(item: $share) { ActivitySheet(url: $0.url) }
        .fileImporter(isPresented: $importFile, allowedContentTypes: [.json]) { result in switch result { case .success(let url): model.restore(url); case .failure(let error): model.report(error) } }
        .confirmationDialog("刪除本局角色？", isPresented: $deleteFirst, titleVisibility: .visible) { Button("繼續確認刪除", role: .destructive) { deleteFinal = true } } message: { Text("將刪除故事、世界、隱藏事件、AI 上下文與附件，保留 API Key。") }
        .alert("永久刪除，無法復原", isPresented: $deleteFinal) { Button("永久刪除", role: .destructive) { model.delete() }; Button("取消", role: .cancel) {} } message: { Text("請確認已匯出想保留的故事。") }
        .alert("刪除金鑰？", isPresented: $deleteKey) { Button("刪除", role: .destructive) { model.saveKey("") }; Button("取消", role: .cancel) {} }
        .onAppear { editedRange = model.effectiveNarrativeRange }
        .onDisappear { key = "" }
    }
    private func export(_ backup: Bool) {
        do { share = SharedFile(url: try (backup ? model.exportBackup() : model.exportStory())) } catch { model.report(error) }
    }
}
struct ActivitySheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
