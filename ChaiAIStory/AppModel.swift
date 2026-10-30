import SwiftUI
import UIKit
import StoryCore

struct Preferences: Codable {
    var model = "gpt-4.1-mini"
    var background = true
    var narrativeLength = 120
    var syncEvery = 20
    var syncOnRestore = false
    var syncOnConflict = false
    var budget = 5.0
    var warning = 4.0
    var pricing = Pricing(input: 0.40, cached: 0.10, output: 1.60)
    var pricingModel = "gpt-4.1-mini"
}
@MainActor final class AppModel: ObservableObject {
    @Published var session: GameSession?
    @Published var turns: [CommittedTurn] = []
    @Published var draft = CreationDraft()
    @Published var preferences: Preferences { didSet { if let data = try? JSONEncoder().encode(preferences) { UserDefaults.standard.set(data, forKey: "preferences") } } }
    @Published var usage: [ApiUsage] = []
    @Published var busy = false
    @Published var pendingAction: String?
    @Published var notice: String?
    @Published var phase = ""
    @Published var models: [String] = []
    @Published var memoryDiagnostic: String = "尚未重整"
    @Published var foreground = true
    @Published var hasKey = false
    @Published var fatalError: String?
    @Published var selectedTab = 0
    @Published var showWizard = false
    @Published var showGame = false
    private(set) var store: GameStore?
    private var task: Task<Void, Never>?
    private var currentID: UUID?
    private var backgroundToken: UIBackgroundTaskIdentifier = .invalid
    var projection: PlayerVisibleProjection? { session.map(PlayerVisibleProjection.init) }
    var totalCost: Double { usage.compactMap(\.estimatedUSD).reduce(0, +) }
    var unknownCost: Bool { usage.contains { $0.inputTokens == nil || $0.estimatedUSD == nil } }
    init() {
        preferences = (UserDefaults.standard.data(forKey: "preferences").flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) }) ?? Preferences()
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("ChaiAIStory", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
            var resource = URLResourceValues(); resource.isExcludedFromBackup = true
            var protectedDirectory = directory; try protectedDirectory.setResourceValues(resource)
            let opened = try GameStore(path: directory.appendingPathComponent("world.sqlite").path)
            store = opened
            let abandoned = try opened.abandonPending()
            session = try opened.session(); draft = try opened.draft(); usage = try opened.usage()
            if let session { turns = try opened.turns(sessionID: session.id) }
            hasKey = !Keychain.read().isEmpty
            if !abandoned.isEmpty {
                notice = "上次未提交的生成已作廢，正式存檔未變。遠端可能已計費；無法保證強制關閉時即刻停止。"
                let client = OpenAIClient(key: Keychain.read())
                Task { for item in abandoned { if let id = item.responseID { try? await client.cancel(id) } } }
            }
        } catch { store = nil; fatalError = error.localizedDescription }
    }
    func report(_ error: Error) { notice = error.localizedDescription }
    func saveDraft() { do { try store?.saveDraft(draft) } catch { report(error) } }
    func loadOlder() {
        guard let session, let number = turns.first?.number, number > 1 else { return }
        do { turns = try (store?.turns(sessionID: session.id, before: number) ?? []) + turns } catch { report(error) }
    }
    func reload() throws {
        session = try store?.session(); usage = try store?.usage() ?? []
        if let session { turns = try store?.turns(sessionID: session.id) ?? [] } else { turns = [] }
    }
    func saveKey(_ key: String) { do { try Keychain.save(key.trimmingCharacters(in: .whitespacesAndNewlines)); hasKey = !Keychain.read().isEmpty; notice = hasKey ? "API Key 已儲存於此裝置 Keychain。" : "API Key 已刪除。" } catch { report(error) } }
    func refreshModels() async {
        do { models = try await OpenAIClient(key: Keychain.read()).models(); notice = "已取得模型清單；清單不代表支援 Responses 或背景模式，請驗證所選模型。" } catch { report(error) }
    }
    func verify() {
        guard !busy, let store else { return }
        busy = true; phase = "驗證金鑰及模型能力…"
        task = Task {
            defer { busy = false; phase = "" }
            let client = OpenAIClient(key: Keychain.read())
            let owner = session ?? GameSession(settings: draft)
            let attempt = GenerationAttempt(session: owner, action: "連線驗證", model: preferences.model)
            var result: ResponseEnvelope?
            do {
                guard hasKey else { throw StoryError.noKey }
                try store.record(ApiUsage(id: attempt.id.uuidString, attempt: attempt))
                let response = try await client.create(model: preferences.model, input: [["role": "user", "content": "Return ok=true"]], background: preferences.background, probe: true)
                result = response
                var final = response
                let deadline = Date().addingTimeInterval(90)
                while ["queued", "in_progress"].contains(final.status) {
                    guard !Task.isCancelled, Date() < deadline else { throw StoryError.interrupted }
                    try await Task.sleep(for: .seconds(2)); final = try await client.retrieve(final.id)
                }
                try record(final, attempt: attempt, ledgerID: attempt.id.uuidString)
                guard final.status == "completed", final.text.contains("true") else { throw StoryError.invalid("模型未通過結構化輸出驗證；可改用較高輸出上限的模型。") }
                notice = "驗證成功：此 Key 可使用 \(preferences.model) 的 Responses、結構化輸出\(preferences.background ? "及背景模式" : "（前景模式）")。查詢工具將於遊戲請求驗證。"
            } catch {
                if let result, preferences.background { try? await client.cancel(result.id) }
                report(error)
            }
            usage = (try? store.usage()) ?? usage
        }
    }
    func record(_ response: ResponseEnvelope, attempt: GenerationAttempt, ledgerID: String) throws {
        let price = preferences.pricingModel == attempt.model ? preferences.pricing : Pricing()
        let data = response.usage
        try store?.record(ApiUsage(id: ledgerID, attempt: attempt, input: data?.input_tokens, cached: data?.input_tokens_details?.cached_tokens,
                                   output: data?.output_tokens, cost: data.flatMap { price.estimate(input: $0.input_tokens, cached: $0.input_tokens_details?.cached_tokens ?? 0, output: $0.output_tokens) }, note: data == nil ? "未知／可能計費" : "伺服器 usage；費用依本機價格估算"))
    }
    func generate(action: String, initial: Bool = false, memoryOnly: Bool = false, bypassBudget: Bool = false) {
        guard !busy, let store else { return }
        guard hasKey else { notice = StoryError.noKey.localizedDescription; return }
        if !bypassBudget && preferences.warning > 0 && totalCost >= preferences.warning { notice = "已達本機費用警戒，請在設定調整警戒值再繼續；未知用量可能另計費。"; return }
        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 4000 else { notice = "行動需為 1–4000 字。"; return }
        do {
            if initial { try draft.validate(); saveDraft() }
            guard var base = initial ? GameSession(settings: draft) : session, !base.dead || memoryOnly else { return }
            base.settings.length = preferences.narrativeLength
            let attempt = GenerationAttempt(session: base, action: trimmed, memoryOnly: memoryOnly, model: preferences.model)
            try store.start(attempt, initial: initial)
            busy = true; currentID = attempt.id; pendingAction = memoryOnly ? nil : trimmed; phase = memoryOnly ? "正在重整本局記憶…" : "AI 正在推演劇情…"
            let backgroundMode = preferences.background
            task = Task { await run(attempt: attempt, base: base, initial: initial, background: backgroundMode) }
        } catch { report(error) }
    }
    private func run(attempt: GenerationAttempt, base: GameSession, initial: Bool, background: Bool) async {
        guard let store else { return }
        let client = OpenAIClient(key: Keychain.read())
        var ledgerID = "\(attempt.id):0"
        var lastResponse: ResponseEnvelope?
        var success = false
        var needsSync = false
        do {
            let recent = try store.turns(sessionID: base.id, limit: 12)
            let context = try ContextBuilder.context(session: base, recent: recent, memory: store.memory(sessionID: base.id), action: attempt.action, memoryOnly: attempt.memoryOnly)
            var input: [[String: Any]] = [["role": "user", "content": context]]
            _ = try store.transition(attempt.id, .requesting)
            for round in 0..<5 {
                try check(attempt.id)
                ledgerID = "\(attempt.id):\(round)"
                try store.record(ApiUsage(id: ledgerID, attempt: attempt))
                var response = try await client.create(model: attempt.model, input: input, background: background, memoryOnly: attempt.memoryOnly, withTools: round < 4)
                lastResponse = response
                try record(response, attempt: attempt, ledgerID: ledgerID)
                try check(attempt.id)
                _ = try store.transition(attempt.id, response.status == "queued" ? .queued : .in_progress, responseID: response.id)
                // Persisted response ID is the sole polling target. No POST retry on network errors.
                var getFailures = 0
                while ["queued", "in_progress"].contains(response.status) {
                    try check(attempt.id)
                    guard Date() < attempt.deadline else { throw StoryError.invalid("背景回應已逾期，未儲存本輪；可能已計費。") }
                    if !foreground { try await Task.sleep(for: .seconds(1)); continue }
                    try await Task.sleep(for: .seconds(min(8, 2 + getFailures * 2)))
                    do { response = try await client.retrieve(response.id); getFailures = 0 }
                    catch { getFailures += 1; if getFailures >= 3 { throw error }; continue }
                    lastResponse = response
                    try record(response, attempt: attempt, ledgerID: ledgerID)
                }
                guard response.status == "completed", !response.refused else { throw StoryError.invalid(response.error?.message ?? "生成未完整完成或被拒絕；未寫入任何劇情。") }
                if !response.calls.isEmpty {
                    guard !attempt.memoryOnly, round < 4 else { throw StoryError.invalid("查詢次數已達上限，本輪未儲存。") }
                    input += try OpenAIClient.assistantItems(response)
                    for call in response.calls {
                        let parameters = (try? JSONSerialization.jsonObject(with: Data((call.arguments ?? "{}").utf8))) as? [String: String]
                        let history = call.name == "search_committed_history" ? try store.searchHistory(sessionID: base.id, query: parameters?["query"] ?? "") : []
                        let answer = try ContextBuilder.query(name: call.name ?? "", arguments: call.arguments ?? "{}", session: base, history: history)
                        input.append(["type": "function_call_output", "call_id": call.call_id ?? "", "output": answer])
                    }
                    continue
                }
                try check(attempt.id)
                _ = try store.transition(attempt.id, .validating); phase = "正在驗證並儲存…"
                if attempt.memoryOnly {
                    let memory = try JSONCoding.decode(NarrativeMemory.self, response.text)
                    try store.saveMemory(memory, attemptID: attempt.id)
                    // A narrator summary can contain secrets. Only fixed diagnostics counts reach the UI.
                    memoryDiagnostic = "重整完成：\(memory.conflicts.count) 個矛盾、\(memory.missingContext.count) 項缺漏；世界及回合未變。"
                    notice = memoryDiagnostic
                } else {
                    let proposal = try JSONCoding.decode(StoryTurnResponse.self, response.text)
                    _ = try store.commit(attempt.id, response: proposal, initial: initial ? base : nil)
                    if proposal.disposition == .rejected_invalid_request { notice = proposal.rejectionReason }
                    else { showWizard = false; showGame = true; selectedTab = 0; success = true }
                }
                try reload(); break
            }
        } catch {
            if let response = lastResponse { try? record(response, attempt: attempt, ledgerID: ledgerID) }
            if let current = try? store.attempt(attempt.id), !current.phase.terminal { _ = try? store.transition(attempt.id, Date() > attempt.deadline ? .expired : .failed) }
            if background, let id = lastResponse?.id { try? await client.cancel(id) }
            if !Task.isCancelled {
                report(error)
                needsSync = preferences.syncOnConflict && !attempt.memoryOnly && !initial
                    && ["不一致", "改寫", "衝突", "隱藏資訊"].contains(where: error.localizedDescription.contains)
            }
        }
        guard currentID == attempt.id else { return }
        usage = (try? store.usage()) ?? usage
        busy = false; pendingAction = nil; phase = ""; currentID = nil; endBackgroundTask()
        if let session, !session.dead, needsSync || (success && preferences.syncEvery > 0 && session.lastCommittedTurn % preferences.syncEvery == 0) {
            generate(action: "例行記憶核對", memoryOnly: true)
        }
    }
    private func check(_ id: UUID) throws {
        try Task.checkCancellation()
        guard currentID == id, let current = try store?.attempt(id), !current.phase.terminal else { throw StoryError.stale }
    }
    func stop() {
        let id = currentID
        var remote: String?
        if let id, let attempt = try? store?.attempt(id) { remote = attempt.responseID; _ = try? store?.transition(id, .cancelled) }
        task?.cancel(); currentID = nil; busy = false; pendingAction = nil; phase = ""; endBackgroundTask()
        if let remote { let client = OpenAIClient(key: Keychain.read()); Task { try? await client.cancel(remote) } }
        notice = "已停止，本輪未提交；遠端可能已計費。"
    }
    func sceneChanged(_ active: Bool) {
        foreground = active
        if active { endBackgroundTask() }
        else if busy && backgroundToken == .invalid {
            backgroundToken = UIApplication.shared.beginBackgroundTask(withName: "persist-response-id") { [weak self] in Task { @MainActor in self?.endBackgroundTask() } }
        }
    }
    private func endBackgroundTask() {
        if backgroundToken != .invalid { UIApplication.shared.endBackgroundTask(backgroundToken); backgroundToken = .invalid }
    }
    func delete() {
        stop()
        do {
            try store?.deleteGame()
            for name in ["ChaiAIStory-Story.md", "ChaiAIStory-Backup.json"] {
                try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent(name))
            }
            session = nil; turns = []; draft = CreationDraft(); usage = []; memoryDiagnostic = "尚未重整"; showGame = false; notice = "角色及本局資料已刪除，API Key 保留。" } catch { report(error) }
    }
    func exportStory() throws -> URL {
        guard let store, let session else { throw StoryError.invalid("沒有可匯出的故事。") }
        let text = "# ChaiAIStory · \(session.settings.name)\n\n" + (try store.allTurns(sessionID: session.id)).map { "## 第 \($0.number) 回\n\n> \($0.action)\n\n\($0.narrative)" }.joined(separator: "\n\n")
        return try writeExport(Data(text.utf8), name: "ChaiAIStory-Story.md")
    }
    func exportBackup() throws -> URL { guard let store else { throw StoryError.stale }; return try writeExport(store.backup(), name: "ChaiAIStory-Backup.json") }
    private func writeExport(_ data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: [.atomic, .completeFileProtection]); return url
    }
    func restore(_ url: URL) {
        guard !busy else { return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do { try store?.restore(Data(contentsOf: url)); try reload(); notice = "備份已還原為唯一遊戲；未匯入任何遠端請求或金鑰。" } catch { report(error) }
    }
}
