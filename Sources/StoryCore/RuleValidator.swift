import Foundation

public struct PlayerVisibleProjection: Sendable {
    public let name: String
    public let sensation: String
    public let symptoms: String
    public let location: String
    public let time: String
    public let inventory: [InventoryEntry]
    public let journal: [KnowledgeEntry]
    public let dead: Bool
    public init(_ session: GameSession) {
        name = session.settings.name; dead = session.dead
        let health = HealthProjection(session)
        sensation = health.feeling; symptoms = health.symptoms
        location = session.world.condition.knownLocation; time = session.world.condition.knownTime
        let known = Set(session.knowledge.map(\.subjectID))
        inventory = session.world.inventory.filter { $0.exists && $0.quantity > 0 && $0.knownToProtagonist && $0.visibleInInventory && known.contains($0.id) }
        journal = session.knowledge
    }
}
public enum RuleValidator {
    public static func apply(_ response: StoryTurnResponse, to original: GameSession) throws -> GameSession {
        guard !original.dead else { throw StoryError.invalid("人生已結束，這份紀錄僅供回顧。") }
        guard response.narratorVisibility == "protagonist_only", response.proposedChanges.count <= 80,
              response.knowledgeReveals.count <= 60 else { throw StoryError.invalid("回應超出安全範圍。") }
        if response.disposition == .rejected_invalid_request {
            guard response.proposedChanges.isEmpty, response.knowledgeReveals.isEmpty, response.continuityNotes.isEmpty,
                  !response.rejectionReason.isEmpty else { throw StoryError.invalid("拒絕行動不能改變世界。") }
            try guardText(response.rejectionReason, session: original)
            return original
        }
        guard response.narrative.count > 0, response.narrative.count <= 40,
              response.narrative.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              response.narrative.map(\.text).joined().count <= 12000 else { throw StoryError.invalid("故事正文不完整。") }
        var result = original
        var IDs = Set(result.world.entities.map(\.id) + result.world.inventory.map(\.id) + result.world.hiddenFacts.map(\.id))
        for change in response.proposedChanges {
            switch change.operation {
            case .add_entity:
                guard let entity = change.entity, !entity.id.isEmpty, !IDs.contains(entity.id), !entity.truth.isEmpty else { throw StoryError.invalid("新增世界資料的識別碼不合法。") }
                IDs.insert(entity.id); result.world.entities.append(entity)
            case .update_entity:
                guard let entity = change.entity, let index = result.world.entities.firstIndex(where: { $0.id == change.targetID }), entity.id == change.targetID,
                      entity.kind == result.world.entities[index].kind, ![EntityKind.rule, .event].contains(entity.kind) else { throw StoryError.invalid("不可改寫世界規則或已發生事件。") }
                result.world.entities[index] = entity
            case .add_item:
                guard let item = change.item, !item.id.isEmpty, !IDs.contains(item.id), (1...100000).contains(item.quantity), item.exists,
                      ["initial", "found", "trade", "reward", "crafted", "given"].contains(item.provenance),
                      original.version == 0 || item.provenance != "initial", !item.name.isEmpty,
                      item.equippedSlot.isEmpty else { throw StoryError.invalid("新物品缺少有效取得來源或數量。") }
                IDs.insert(item.id); result.world.inventory.append(item)
            case .adjust_item:
                guard let index = result.world.inventory.firstIndex(where: { $0.id == change.targetID && $0.exists }), change.amount != 0, change.amount >= -100000, change.amount <= 100000 else { throw StoryError.invalid("無法變更不存在的物品。") }
                let count = result.world.inventory[index].quantity + change.amount
                guard (0...100000).contains(count) else { throw StoryError.invalid("物品數量不足或超出上限。") }
                result.world.inventory[index].quantity = count
                if count == 0 { result.world.inventory[index].exists = false; result.world.inventory[index].equippedSlot = "" }
            case .equip_item:
                guard let index = result.world.inventory.firstIndex(where: { $0.id == change.targetID && $0.exists && $0.knownToProtagonist }),
                      result.world.inventory[index].operations.contains("裝備"), change.text.count < 40,
                      change.text.isEmpty || !result.world.inventory.contains(where: { $0.id != change.targetID && $0.exists && $0.equippedSlot == change.text }) else { throw StoryError.invalid("裝備部位衝突或物品不可裝備。") }
                result.world.inventory[index].equippedSlot = change.text
            case .discover_item:
                guard let index = result.world.inventory.firstIndex(where: { $0.id == change.targetID && $0.exists }) else { throw StoryError.invalid("找不到可發現的物品。") }
                result.world.inventory[index].knownToProtagonist = true; result.world.inventory[index].visibleInInventory = true
            case .add_hidden_fact:
                guard let fact = change.hiddenFact, !fact.id.isEmpty, !IDs.contains(fact.id), !fact.truth.isEmpty,
                      !fact.forbiddenTerms.isEmpty, fact.forbiddenTerms.allSatisfy({ $0.count >= 2 }) else { throw StoryError.invalid("秘密必須有獨立識別及保密詞。") }
                IDs.insert(fact.id); result.world.hiddenFacts.append(fact)
            case .condition:
                guard let condition = change.physicalCondition, (0...100).contains(condition.vitality), (0...100).contains(condition.fatigue), (0...100).contains(condition.energy),
                      !condition.sensation.isEmpty, !condition.symptoms.isEmpty else { throw StoryError.invalid("身體狀態不合法。") }
                result.world.condition = condition
            case .advance_time:
                guard (0...525600).contains(change.amount), result.world.minute <= Int.max - change.amount else { throw StoryError.invalid("時間不能倒流或無限制跳躍。") }
                result.world.minute += change.amount
            case .death: result.dead = true
            }
        }
        for knowledge in response.knowledgeReveals {
            guard !knowledge.id.isEmpty, IDs.contains(knowledge.subjectID), !knowledge.source.isEmpty,
                  !knowledge.title.isEmpty, !knowledge.text.isEmpty, (0...1).contains(knowledge.confidence) else { throw StoryError.invalid("認知揭露缺少來源或有效對象。") }
            if let index = result.knowledge.firstIndex(where: { $0.id == knowledge.id }) {
                guard result.knowledge[index].subjectID == knowledge.subjectID else { throw StoryError.invalid("認知識別不能改指別的對象。") }
                result.knowledge[index] = knowledge
            } else { result.knowledge.append(knowledge) }
        }
        if result.world.condition.vitality == 0 && !result.dead { throw StoryError.invalid("生命狀態與結局不一致。") }
        if result.dead {
            guard response.choices.isEmpty else { throw StoryError.invalid("人生結局不能有後續行動。") }
        } else {
            let choices = response.choices.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard (3...5).contains(choices.count), Set(choices).count == choices.count, choices.allSatisfy({ !$0.isEmpty && $0.count <= 200 }) else { throw StoryError.invalid("需要 3–5 個不同且完整的下一步選項。") }
        }
        let knownIDs = Set(result.knowledge.map(\.id))
        for segment in response.narrative + response.choices {
            guard segment.knowledgeIDs.allSatisfy(knownIDs.contains) else { throw StoryError.invalid("敘事引用了主角未知的情報。") }
            try guardText(segment.text, session: result)
        }
        let projection = PlayerVisibleProjection(result)
        try guardText([projection.sensation, projection.symptoms, projection.location, projection.time].joined(separator: "\n"), session: result)
        for item in projection.inventory { try guardText(item.name + item.detail, session: result) }
        for entry in result.knowledge { try guardText(entry.title + entry.text + entry.source + entry.discoverability, session: result) }
        guard HealthProjection.isSubjective(result.world.condition.sensation), HealthProjection.isSubjective(result.world.condition.symptoms), !result.world.condition.sensation.contains(where: \.isNumber), !result.world.condition.symptoms.localizedCaseInsensitiveContains("HP"),
              !result.world.condition.symptoms.contains("死亡時間") else { throw StoryError.invalid("健康資訊必須是主觀感受。") }
        // While unconscious, no externally sourced revelations or observations may be committed.
        if !original.world.condition.conscious && !result.world.condition.conscious {
            guard response.knowledgeReveals.isEmpty, response.narrative.allSatisfy({ $0.knowledgeIDs.isEmpty }),
                  response.narrative.map(\.text).joined().count <= 80 else { throw StoryError.invalid("昏迷中不得取得外界情報。") }
        }
        guard result.world.entities.count <= 20000, result.world.inventory.count <= 10000, result.knowledge.count <= 30000 else { throw StoryError.invalid("世界資料已達安全上限，請匯出紀錄。") }
        return result
    }
    public static func validateSnapshot(_ session: GameSession) throws {
        let world = session.world
        let ids = world.entities.map(\.id) + world.inventory.map(\.id) + world.hiddenFacts.map(\.id)
        guard ids.allSatisfy({ !$0.isEmpty }), Set(ids).count == ids.count,
              Set(session.knowledge.map(\.id)).count == session.knowledge.count,
              session.knowledge.allSatisfy({ ids.contains($0.subjectID) && (0...1).contains($0.confidence) }),
              world.minute >= 0, world.minute <= Int.max - 525600,
              (0...100).contains(world.condition.vitality), (0...100).contains(world.condition.fatigue),
              (0...100).contains(world.condition.energy),
              world.inventory.allSatisfy({ (0...100000).contains($0.quantity) && (!$0.visibleInInventory || $0.knownToProtagonist) }),
              world.entities.count <= 20000, world.inventory.count <= 10000, session.knowledge.count <= 30000 else {
            throw StoryError.invalid("備份世界資料不完整或超出安全範圍。")
        }
        let projection = PlayerVisibleProjection(session)
        try guardText([projection.sensation, projection.symptoms, projection.location, projection.time].joined(separator: "\n"), session: session)
        for item in projection.inventory { try guardText(item.name + item.detail, session: session) }
        for entry in projection.journal { try guardText(entry.title + entry.text + entry.source, session: session) }
    }
    public static func guardText(_ text: String, session: GameSession) throws {
        let revealed = Set(session.knowledge.map(\.subjectID))
        let forbidden = session.world.hiddenFacts.filter { !revealed.contains($0.id) }.flatMap(\.forbiddenTerms)
            + session.world.inventory.filter { !$0.knownToProtagonist }.map(\.name)
        guard !forbidden.contains(where: { !$0.isEmpty && text.localizedCaseInsensitiveContains($0) }) else { throw StoryError.invalid("回應包含尚未得知的隱藏資訊，已阻止提交。") }
        guard !text.contains("全知視角"), !text.contains("此時你不知道的是"), !text.contains("在你昏迷期間，") else { throw StoryError.invalid("回應超出主角感知範圍。") }
    }
}
