#if DEBUG
import Foundation
import StoryCore

/// Only compiled into Debug. Dedicated in-memory store; never touches player data or Keychain.
enum UITestFixture {
    static func populate(_ store: GameStore, health: String) throws -> GameSession {
        var settings = CreationDraft()
        settings.name = "測試旅人"
        var base = GameSession(settings: settings)
        switch health {
        case "injured": base.world.condition.sensation = "頭暈不適"; base.world.condition.symptoms = "左腳踝腫痛，起身時頭暈。"
        case "cold": base.world.condition.sensation = "冷得發抖"; base.world.condition.symptoms = "手指冰冷，身體不停發抖。"
        case "hot": base.world.condition.sensation = "頭暈不適"; base.world.condition.symptoms = "烈日下感到暈眩，喉嚨乾燥。"
        case "waking": base.world.condition.sensation = "略感疲倦"; base.world.condition.symptoms = "醒來時四肢沉重，尚不清楚過了多久。"
        default: break
        }
        base.world.condition.knownLocation = "大梁國 · 臨安城 · 永安鐵鋪後院通往河岸的長廊"
        let attempt = GenerationAttempt(session: base, action: "沿著街道觀察", model: "ui-test-no-network")
        try store.start(attempt, initial: true)
        _ = try store.transition(attempt.id, .requesting)
        _ = try store.transition(attempt.id, .validating)
        let paragraph = "你沿著石板路走近鋪前，停下腳步聽著門內傳來的敲打聲。掌櫃放下手中的工具，抬頭望向你，示意你先到屋簷下避雨。你看見櫃旁放著幾件尚未修整的器物，便詢問他近日街上的情況。他想了想，轉身取來一張凳子，請你坐下慢慢說。"
        var response = StoryTurnResponse(narrative: paragraph + paragraph, choices: [
            "詢問掌櫃這條街最近發生的事情，並仔細留意他回答時的神情與語氣",
            "檢查自己腳踝的不適，先找一個安全的位置坐下休息，再決定接下來的路線",
            "沿著後院通往河岸的長廊慢慢前進，觀察沿途的招牌和路上行人的反應",
            "留在屋簷下，和正在修整器物的學徒聊聊他的日常工作",
            "向掌櫃道謝，離開鐵鋪並沿原路返回剛才經過的街口"
        ])
        response.proposedChanges = [
            .init(operation: .add_entity, entity: .init(id: "rule", kind: .rule, truth: "寫實世界")),
            .init(operation: .add_entity, entity: .init(id: "home", kind: .location, truth: "鐵鋪")),
            .init(operation: .add_entity, entity: .init(id: "npc", kind: .npc, truth: "掌櫃"))
        ]
        response.knowledgeReveals = [.init(id: "known-home", subjectID: "home", title: "鐵鋪", text: "親眼看到鐵鋪。", source: "觀察")]
        return try store.commit(attempt.id, response: response, initial: base)
    }
}
#endif
