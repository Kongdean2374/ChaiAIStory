import Foundation

/// Display-only transformation of committed subjective strings. Never reads vitality, fatigue or energy.
public struct HealthProjection: Equatable, Sendable {
    public let feeling: String
    public let symptoms: String
    public let isEnding: Bool
    public init(_ session: GameSession) {
        isEnding = session.dead
        let rawFeeling = session.world.condition.sensation.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawSymptoms = session.world.condition.symptoms.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = session.dead ? "最後可感知的狀態" : session.world.condition.conscious ? "暫無明確感受紀錄" : "意識不清"
        let safeFeeling = (try? RuleValidator.guardText(rawFeeling, session: session)) != nil && Self.isSubjective(rawFeeling)
        let safeSymptoms = (try? RuleValidator.guardText(rawSymptoms, session: session)) != nil && Self.isSubjective(rawSymptoms)
        feeling = !rawFeeling.isEmpty && safeFeeling ? rawFeeling : fallback
        symptoms = !rawSymptoms.isEmpty && safeSymptoms ? rawSymptoms : "尚無更多已記錄的主觀感受。"
    }
    public static func isSubjective(_ text: String) -> Bool {
        let prohibited = ["HP", "血量", "生命值", "生命力", "死亡倒數", "死亡時間", "內部傷害", "確診", "診斷為",
                          "內出血", "臟器破裂", "器官衰竭", "肝破裂", "脾破裂", "腦出血", "你不知道", "昏迷期間"]
        guard !prohibited.contains(where: { text.localizedCaseInsensitiveContains($0) }) else { return false }
        return text.range(of: #"[0-9０-９]+(?:\s*[%％]|\s*(?:秒|分鐘|小時).*死)|[「」『』“”]"#, options: .regularExpression) == nil
    }
}
