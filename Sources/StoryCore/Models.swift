import Foundation

public enum StoryError: Error, LocalizedError {
    case invalid(String), stale, noKey, database(String), api(Int, String), interrupted
    public var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .stale: return "這個請求已作廢，存檔維持原狀。"
        case .noKey: return "請先在設定儲存自己的 OpenAI API Key。"
        case .database(let message): return "資料庫錯誤：\(message)"
        case .api(let code, let message): return "\(code == 401 ? "金鑰無效" : code == 403 ? "沒有模型或功能權限" : code == 429 ? "限流或額度不足" : "API 錯誤")（\(code)）：\(message)"
        case .interrupted: return "請求未完成；可能已計費，沒有自動重送。"
        }
    }
}
public struct CreationDraft: Codable, Equatable, Sendable {
    public var genre = "武俠"
    public var template = "江湖殘卷・無名之路"
    public var name = "無名"
    public var pronouns = "你"
    public var gender = "自行定義"
    public var age = 20
    public var appearance = ""
    public var identity = "旅人"
    public var background = "未知／留待故事揭露"
    public var family = "未知／留待故事揭露"
    public var personality = "謹慎而好奇"
    public var residence = "留待世界生成"
    public var aptitude = "均衡"
    public var realism = 0.6
    public var danger = 0.5
    public var autonomy = 0.7
    public var combat = 0.4
    public var social = 0.6
    public var pace = 0.5
    public var length = 120
    public init() {}
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !genre.isEmpty,
              (1...120).contains(age), (20...2000).contains(length) else { throw StoryError.invalid("請填寫姓名、題材，年齡 1–120，目標字數 20–2000。") }
        guard [name, template, background, family, appearance, identity, personality, residence, aptitude].allSatisfy({ $0.count <= 2000 }) else { throw StoryError.invalid("每個設定欄位最多 2000 字。") }
    }
}
public enum EntityKind: String, Codable, CaseIterable, Sendable {
    case location, faction, npc, goal, relationship, rule, quest, event, skill, journal, thread
}
/// Truth is never bound directly to a view. Display text lives exclusively in KnowledgeEntry.
public struct WorldEntity: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var kind: EntityKind
    public var truth: String
    public var motivation: String
    public var nextMinute: Int
    public init(id: String, kind: EntityKind, truth: String, motivation: String = "", nextMinute: Int = 0) {
        self.id = id; self.kind = kind; self.truth = truth; self.motivation = motivation; self.nextMinute = nextMinute
    }
}
public struct HiddenFact: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var truth: String
    public var forbiddenTerms: [String]
    public init(id: String, truth: String, forbiddenTerms: [String]) { self.id = id; self.truth = truth; self.forbiddenTerms = forbiddenTerms }
}
public struct KnowledgeEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var subjectID: String
    public var title: String
    public var text: String
    public var source: String
    public var confidence: Double
    public var discoverability: String
    public init(id: String, subjectID: String, title: String, text: String, source: String, confidence: Double = 1, discoverability: String = "已感知") {
        self.id = id; self.subjectID = subjectID; self.title = title; self.text = text; self.source = source; self.confidence = confidence; self.discoverability = discoverability
    }
}
public struct InventoryEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var detail: String
    public var category: String
    public var quantity: Int
    public var exists: Bool
    public var knownToProtagonist: Bool
    public var visibleInInventory: Bool
    public var hiddenContainer: String
    public var equippedSlot: String
    public var operations: [String]
    public var provenance: String
    public init(id: String, name: String, quantity: Int = 1, known: Bool = false) {
        self.id = id; self.name = name; detail = ""; category = "其他"; self.quantity = quantity
        exists = true; knownToProtagonist = known; visibleInInventory = known; hiddenContainer = ""; equippedSlot = ""
        operations = ["使用", "裝備", "檢查", "給予", "丟棄"]; provenance = "initial"
    }
}
public struct PhysicalCondition: Codable, Equatable, Sendable {
    public var vitality = 100
    public var fatigue = 0
    public var energy = 100
    public var conscious = true
    public var sensation = "正常"
    public var symptoms = "呼吸平穩，身體暫無明顯不適。"
    public var knownLocation = "不明之處"
    public var knownTime = "時間不明"
    public init() {}
}
public struct WorldTruth: Codable, Equatable, Sendable {
    public var entities: [WorldEntity] = []
    public var inventory: [InventoryEntry] = []
    public var hiddenFacts: [HiddenFact] = []
    public var minute = 0
    public var condition = PhysicalCondition()
    public init() {}
}
public struct GameSession: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var seed: UUID
    public var createdAt: Date
    public var settings: CreationDraft
    public var dead = false
    public var version = 0
    public var lastCommittedTurn = 0
    public var world = WorldTruth()
    public var knowledge: [KnowledgeEntry] = []
    public init(settings: CreationDraft) { id = UUID(); seed = UUID(); createdAt = Date(); self.settings = settings }
}
public enum Disposition: String, Codable, Sendable { case accepted, attempt_with_uncertain_outcome, rejected_invalid_request }
public enum ChangeOperation: String, Codable, CaseIterable, Sendable {
    case add_entity, update_entity, add_item, adjust_item, equip_item, discover_item, add_hidden_fact, condition, advance_time, death
}
/// Flat typed command envelope, NOT SQL or arbitrary key paths. Unused fields must be empty/zero/null.
public struct ProposedChange: Codable, Sendable {
    public var operation: ChangeOperation
    public var targetID: String
    public var amount: Int
    public var text: String
    public var entity: WorldEntity?
    public var item: InventoryEntry?
    public var hiddenFact: HiddenFact?
    public var physicalCondition: PhysicalCondition?
    public init(operation: ChangeOperation, targetID: String = "", amount: Int = 0, text: String = "", entity: WorldEntity? = nil, item: InventoryEntry? = nil, hiddenFact: HiddenFact? = nil, physicalCondition: PhysicalCondition? = nil) {
        self.operation = operation; self.targetID = targetID; self.amount = amount; self.text = text
        self.entity = entity; self.item = item; self.hiddenFact = hiddenFact; self.physicalCondition = physicalCondition
    }
}
public struct VisibleText: Codable, Sendable {
    public var text: String
    public var knowledgeIDs: [String]
    public init(_ text: String, knowledgeIDs: [String] = []) { self.text = text; self.knowledgeIDs = knowledgeIDs }
}
public struct StoryTurnResponse: Codable, Sendable {
    public var disposition: Disposition
    public var rejectionReason: String
    public var narrative: [VisibleText]
    public var choices: [VisibleText]
    public var proposedChanges: [ProposedChange]
    public var knowledgeReveals: [KnowledgeEntry]
    public var continuityNotes: [String]
    public var narratorVisibility: String
    public init(disposition: Disposition = .accepted, narrative: String, choices: [String], proposedChanges: [ProposedChange] = [], knowledgeReveals: [KnowledgeEntry] = []) {
        self.disposition = disposition; rejectionReason = ""; self.narrative = [VisibleText(narrative)]; self.choices = choices.map { VisibleText($0) }
        self.proposedChanges = proposedChanges; self.knowledgeReveals = knowledgeReveals; continuityNotes = []; narratorVisibility = "protagonist_only"
    }
}
public struct CommittedTurn: Codable, Identifiable, Sendable {
    public var id: UUID
    public var sessionID: UUID
    public var number: Int
    public var action: String
    public var narrative: String
    public var choices: [String]
    public var summary: [String]
    public var changes: [ProposedChange]
    public var date: Date
}
public enum GenerationPhase: String, Codable, Sendable {
    case idle, preparing, requesting, queued, in_progress, validating, committing, committed, cancelled, failed, expired
    public var terminal: Bool { [.committed, .cancelled, .failed, .expired].contains(self) }
    public func allows(_ next: Self) -> Bool {
        if terminal { return false }
        if [.cancelled, .failed, .expired].contains(next) { return true }
        let table: [Self: Set<Self>] = [.idle: [.preparing], .preparing: [.requesting], .requesting: [.queued, .in_progress, .validating], .queued: [.in_progress, .queued, .validating], .in_progress: [.in_progress, .queued, .validating], .validating: [.committing], .committing: [.committed]]
        return table[self]?.contains(next) == true
    }
}
public struct GenerationAttempt: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var sessionID: UUID
    public var baseVersion: Int
    public var baseTurn: Int
    public var responseID: String?
    public var phase: GenerationPhase = .preparing
    public var deadline = Date().addingTimeInterval(540)
    public var action: String
    public var memoryOnly: Bool
    public var model: String
    public init(session: GameSession, action: String, memoryOnly: Bool = false, model: String) {
        sessionID = session.id; baseVersion = session.version; baseTurn = session.lastCommittedTurn
        self.action = action; self.memoryOnly = memoryOnly; self.model = model
    }
}
public struct NarrativeMemory: Codable, Equatable, Sendable {
    public var canonicalSummary: String
    public var openThreads: [String]
    public var conflicts: [String]
    public var missingContext: [String]
    public var knowledgeBoundaryChecks: [String]
    public init(canonicalSummary: String, openThreads: [String] = [], conflicts: [String] = [], missingContext: [String] = [], knowledgeBoundaryChecks: [String] = []) {
        self.canonicalSummary = canonicalSummary; self.openThreads = openThreads; self.conflicts = conflicts; self.missingContext = missingContext; self.knowledgeBoundaryChecks = knowledgeBoundaryChecks
    }
}
public struct ApiUsage: Codable, Identifiable, Sendable {
    public var id: String
    public var attemptID: UUID
    public var sessionID: UUID
    public var model: String
    public var date: Date
    public var inputTokens: Int?
    public var cachedTokens: Int?
    public var outputTokens: Int?
    public var estimatedUSD: Double?
    public var note: String
    public init(id: String, attempt: GenerationAttempt, input: Int? = nil, cached: Int? = nil, output: Int? = nil, cost: Double? = nil, note: String = "未知／可能計費") {
        self.id = id; attemptID = attempt.id; sessionID = attempt.sessionID; model = attempt.model; date = Date()
        inputTokens = input; cachedTokens = cached; outputTokens = output; estimatedUSD = cost; self.note = note
    }
}
public enum JSONCoding {
    public static func encode<T: Encodable>(_ value: T) throws -> String { String(decoding: try JSONEncoder().encode(value), as: UTF8.self) }
    public static func decode<T: Decodable>(_ type: T.Type, _ string: String) throws -> T { try JSONDecoder().decode(type, from: Data(string.utf8)) }
}
