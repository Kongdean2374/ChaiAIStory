import XCTest
import CSQLite
@testable import StoryCore

final class UpdateTests: XCTestCase {
    func candidate(_ count: Int) -> StoryTurnResponse {
        StoryTurnResponse(narrative: String(repeating: "文", count: count), choices: ["觀察", "詢問", "休息"])
    }
    func testHanCountingIgnoresPunctuationLatinNumbersAndSymbols() {
        XCTAssertEqual(NarrativePolicy.count("「你，好！」\nAI 123％🙂𠀀〇"), 4)
        var text = candidate(100)
        text.narrative.append(VisibleText(String(repeating: "字，", count: 100)))
        text.choices = [VisibleText(String(repeating: "選", count: 999))]
        XCTAssertEqual(text.narrative.reduce(0) { $0 + NarrativePolicy.count($1.text) }, 200)
    }
    func testReportedRiverSceneCountsOnlyBodyHan() throws {
        let sample = """
        你沒掏錢，只在棚邊站定：「船家幾時回來？過河要多少？」
        婦人把碗疊進木盆，朝泥路望了一眼：「平日一人兩文。方才他說去村裡買米，沒說幾時回。你若急，我可不敢替他應承。」
        她甩去手上水珠，又道：「沿這條路往西便是村子，莫往河邊岔路走。我再收拾一會兒，也要關棚了。」
        河水拍著船舷，繫繩時鬆時緊。西邊泥路留著幾道積水的車轍，眼下不見有人走來；你可以等，也可以趁尚有天光去找。
        """
        XCTAssertEqual(NarrativePolicy.count(sample), 152)
        let body = StoryTurnResponse(narrative: sample, choices: ["等待", "離開", "詢問"])
        let report = try NarrativePolicy.validate(body, base: GameSession(settings: CreationDraft()))
        XCTAssertEqual(report.actual, 152)
        XCTAssertLessThan(report.actual, report.expected.preferred.lowerBound)
    }
    func testRangeAndPreferredMiddle() throws {
        let base = GameSession(settings: CreationDraft())
        XCTAssertEqual(base.settings.effectiveNarrativeRange.preferred, 190...220)
        XCTAssertThrowsError(try NarrativePolicy.validate(candidate(149), base: base))
        XCTAssertNoThrow(try NarrativePolicy.validate(candidate(200), base: base))
        XCTAssertThrowsError(try NarrativePolicy.validate(candidate(251), base: base))
        XCTAssertEqual(try NarrativePolicy.report(candidate(200), base: base).actual, 200)
    }
    func testRevisionFreezesCommandsChoicesAndReveals() throws {
        let base = GameSession(settings: CreationDraft())
        var original = candidate(50)
        original.proposedChanges = [.init(operation: .advance_time, amount: 15)]
        let revised = try NarrativePolicy.revise(original, with: .init(narrative: candidate(200).narrative), base: base)
        XCTAssertEqual(revised.proposedChanges, original.proposedChanges)
        XCTAssertEqual(revised.choices.map(\.text), original.choices.map(\.text))
        XCTAssertEqual(revised.knowledgeReveals, original.knowledgeReveals)
        XCTAssertThrowsError(try NarrativePolicy.revise(original, with: .init(narrative: candidate(50).narrative), base: base))
        XCTAssertThrowsError(try NarrativePolicy.validate(revised, base: base, repairCount: 2))
    }
    func testShortExceptionsAreGroundedInWorldState() throws {
        var base = GameSession(settings: CreationDraft())
        var rejected = candidate(0); rejected.disposition = .rejected_invalid_request; rejected.rejectionReason = "無法直接改寫世界。"
        XCTAssertEqual(try NarrativePolicy.validate(rejected, base: base).exception, "拒絕行動")
        var death = candidate(15); death.proposedChanges = [.init(operation: .death)]; death.choices = []
        XCTAssertEqual(try NarrativePolicy.validate(death, base: base).exception, "人生結局")
        base.world.condition.conscious = false
        XCTAssertNotNil(try NarrativePolicy.validate(candidate(20), base: base).exception)
        var waking = candidate(20); waking.proposedChanges = [.init(operation: .condition, physicalCondition: PhysicalCondition())]
        XCTAssertThrowsError(try NarrativePolicy.validate(waking, base: base))
    }
    func testLegacySingleLengthDecodesWithoutResettingCharacter() throws {
        var original = CreationDraft(); original.length = 200; original.name = "保留的角色"; original.family = "未知"
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "narrativeRange")
        let migrated = try JSONDecoder().decode(CreationDraft.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.effectiveNarrativeRange, NarrativeRange())
        XCTAssertEqual(migrated.name, original.name); XCTAssertEqual(migrated.family, original.family)
        XCTAssertNil(migrated.narrativeRange)
    }
    func testSessionRangePersistsAcrossTurnsReopenAndContext() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path+suffix) } }
        let helpers = StoryCoreTests()
        var db: GameStore? = try GameStore(path: path)
        let initial = try helpers.opened(db!)
        XCTAssertEqual(initial.settings.effectiveNarrativeRange, NarrativeRange())
        let before = initial.world
        var saved = try db!.setNarrativeRange(.init(minimum: 180, maximum: 300), sessionID: initial.id)
        XCTAssertEqual(saved.world, before); XCTAssertEqual(saved.lastCommittedTurn, 1)
        let attempt = try helpers.ready(db!, saved)
        XCTAssertThrowsError(try db!.setNarrativeRange(.init(), sessionID: initial.id))
        saved = try db!.commit(attempt.id, response: candidate(220))
        db = nil
        db = try GameStore(path: path)
        let restored = try XCTUnwrap(db!.session())
        XCTAssertEqual(restored.settings.effectiveNarrativeRange, .init(minimum: 180, maximum: 300))
        let context = try ContextBuilder.context(session: restored, recent: [], memory: nil, action: "觀察")
        XCTAssertTrue(context.contains("180～300")); XCTAssertFalse(context.contains("目標約 120"))
        let report = try XCTUnwrap(db!.turns(sessionID: restored.id).last?.lengthReport)
        XCTAssertEqual(report.expected, .init(minimum: 180, maximum: 300)); XCTAssertEqual(report.actual, 220)
        db = nil
    }
    func testOldDatabasePayloadAndHistorySurviveOpening() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path+suffix) } }
        var db: GameStore? = try GameStore(path: path)
        var existing = try StoryCoreTests().opened(db!)
        existing.settings.length = 200; existing.settings.narrativeRange = nil
        let payload = try JSONCoding.encode(existing)
        db = nil
        var sql: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &sql), SQLITE_OK)
        let update = "UPDATE session SET payload='" + payload.replacingOccurrences(of: "'", with: "''") + "'"
        XCTAssertEqual(sqlite3_exec(sql, update, nil, nil, nil), SQLITE_OK)
        sqlite3_close(sql)
        db = try GameStore(path: path)
        let result = try XCTUnwrap(db!.session())
        XCTAssertEqual(result.id, existing.id); XCTAssertEqual(result.world, existing.world); XCTAssertEqual(result.knowledge, existing.knowledge)
        XCTAssertEqual(result.settings.effectiveNarrativeRange, NarrativeRange())
        XCTAssertEqual(try db!.allTurns(sessionID: result.id).count, 1)
        db = nil
    }
    func testShortOrCancelledRepairCannotCommitOrAdvanceWorld() throws {
        let db = try GameStore(path: ":memory:"); let helper = StoryCoreTests(); let base = try helper.opened(db)
        let attempt = try helper.ready(db, base)
        var short = candidate(30); short.proposedChanges = [.init(operation: .advance_time, amount: 15)]
        XCTAssertThrowsError(try db.commit(attempt.id, response: short))
        XCTAssertEqual(try db.session(), base)
        let repaired = try NarrativePolicy.revise(short, with: .init(narrative: candidate(200).narrative), base: base)
        _ = try db.transition(attempt.id, .cancelled)
        XCTAssertThrowsError(try db.commit(attempt.id, response: repaired, repairCount: 1))
        XCTAssertEqual(try db.session(), base)
    }
    func testMemoryStillWorksWithoutNovelLength() throws {
        let db = try GameStore(path: ":memory:"); let helper = StoryCoreTests(); let base = try helper.opened(db)
        let attempt = try helper.ready(db, base, memory: true)
        try db.saveMemory(.init(canonicalSummary: "核對完成"), attemptID: attempt.id)
        XCTAssertEqual(try db.session(), base)
    }
    func testHealthProjectionStatesFallbackAndNoInternalNumbers() throws {
        var base = GameSession(settings: CreationDraft())
        for symptoms in ["左腳踝腫痛，起身時頭暈。", "冷得發抖，手腳冰冷。", "烈日曝曬後感到暈眩。", "醒來後四肢沉重。"] {
            base.world.condition.sensation = "不太舒服"; base.world.condition.symptoms = symptoms
            XCTAssertEqual(HealthProjection(base).symptoms, symptoms)
            base.world.condition.vitality = 12
            XCTAssertFalse(HealthProjection(base).symptoms.contains("12"))
        }
        for forbidden in ["HP 35", "生命值 45%", "確診肝破裂", "在你昏迷期間，師父說了秘密", "三分鐘死亡倒數"] {
            base.world.condition.symptoms = forbidden
            XCTAssertEqual(HealthProjection(base).symptoms, "尚無更多已記錄的主觀感受。")
        }
        base.world.condition.sensation = ""; base.world.condition.symptoms = ""
        XCTAssertFalse(HealthProjection(base).feeling.isEmpty)
        base.dead = true
        XCTAssertTrue(HealthProjection(base).isEnding)
        XCTAssertEqual(HealthProjection(base).feeling, "最後可感知的狀態")
    }
    func testHealthReadsDoNotTouchStoreOrUsage() throws {
        let db = try GameStore(path: ":memory:"); let helper = StoryCoreTests(); let base = try helper.opened(db)
        for _ in 0..<10 { _ = HealthProjection(base); _ = PlayerVisibleProjection(base) }
        XCTAssertEqual(try db.session(), base); XCTAssertTrue(try db.usage().isEmpty)
        var response = candidate(200); var condition = base.world.condition
        condition.sensation = "頭暈不適"; condition.symptoms = "起身時頭暈。"
        response.proposedChanges = [.init(operation: .condition, physicalCondition: condition)]
        let attempt = try helper.ready(db, base)
        let changed = try db.commit(attempt.id, response: response)
        XCTAssertEqual(PlayerVisibleProjection(changed).sensation, HealthProjection(changed).feeling)
        XCTAssertEqual(HealthProjection(changed).symptoms, "起身時頭暈。")
    }
    func testBudgetsAreBoundedAndAccountForJSONAndOpening() {
        let range = NarrativeRange()
        XCTAssertGreaterThan(NarrativePolicy.outputBudget(range: range, model: "gpt-4.1-mini", opening: true), NarrativePolicy.outputBudget(range: range, model: "gpt-4.1-mini"))
        XCTAssertLessThanOrEqual(NarrativePolicy.outputBudget(range: .init(minimum: 20, maximum: 2000), model: "gpt-6"), 18000)
        XCTAssertLessThan(NarrativePolicy.outputBudget(range: range, model: "gpt-4.1-mini", revision: true), 8000)
    }
}
