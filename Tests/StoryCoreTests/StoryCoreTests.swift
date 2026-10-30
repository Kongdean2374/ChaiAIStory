import XCTest
import CSQLite
@testable import StoryCore

final class StoryCoreTests: XCTestCase {
    func store() throws -> GameStore { try GameStore(path: ":memory:") }
    func valid(_ text: String = "你推開門，晨光落在手背上。") -> StoryTurnResponse {
        StoryTurnResponse(narrative: text, choices: ["走向街道", "觀察四周", "停下休息"])
    }
    func ready(_ store: GameStore, _ base: GameSession, initial: Bool = false, memory: Bool = false) throws -> GenerationAttempt {
        let attempt = GenerationAttempt(session: base, action: "觀察", memoryOnly: memory, model: "test")
        try store.start(attempt, initial: initial)
        _ = try store.transition(attempt.id, .requesting)
        _ = try store.transition(attempt.id, .validating, responseID: "resp_test")
        return attempt
    }
    func opened(_ store: GameStore) throws -> GameSession {
        let base = GameSession(settings: CreationDraft())
        let attempt = try ready(store, base, initial: true)
        var opening = valid()
        opening.proposedChanges = [
            .init(operation: .add_entity, entity: .init(id: "rule", kind: .rule, truth: "寫實世界")),
            .init(operation: .add_entity, entity: .init(id: "home", kind: .location, truth: "客棧")),
            .init(operation: .add_entity, entity: .init(id: "npc", kind: .npc, truth: "掌櫃", motivation: "經營客棧"))
        ]
        opening.knowledgeReveals = [.init(id: "k-home", subjectID: "home", title: "客棧", text: "你在客棧裡。", source: "親眼所見")]
        return try store.commit(attempt.id, response: opening, initial: base)
    }
    func testDraftIsNotSession() throws {
        let db = try store(); var draft = CreationDraft(); draft.genre = "科幻"; draft.name = "星塵"
        try db.saveDraft(draft)
        XCTAssertNil(try db.session()); XCTAssertEqual(try db.draft(), draft)
    }
    func testDraftValidation() throws {
        var draft = CreationDraft(); draft.name = ""; XCTAssertThrowsError(try draft.validate())
        draft.name = "旅人"; draft.length = 10; XCTAssertThrowsError(try draft.validate())
    }
    func testOpeningCommitsWholeTurn() throws {
        let db = try store(); let session = try opened(db)
        XCTAssertEqual(session.version, 1); XCTAssertEqual(session.lastCommittedTurn, 1)
        XCTAssertEqual(try db.turns(sessionID: session.id).count, 1)
    }
    func testSecondSessionRejected() throws {
        let db = try store(); _ = try opened(db)
        let other = GameSession(settings: CreationDraft())
        XCTAssertThrowsError(try db.start(GenerationAttempt(session: other, action: "開局", model: "test"), initial: true))
    }
    func testPartialJSONNeverCommits() throws {
        let db = try store(); let session = try opened(db)
        XCTAssertThrowsError(try JSONCoding.decode(StoryTurnResponse.self, "{\"narrative\":\"你"))
        XCTAssertEqual(try db.session(), session)
    }
    func testValidationRollsBackInventoryAndTimeline() throws {
        let db = try store(); let base = try opened(db); let attempt = try ready(db, base)
        var item = InventoryEntry(id: "potion", name: "藥", known: true); item.provenance = "found"
        var response = valid(); response.proposedChanges = [.init(operation: .add_item, item: item), .init(operation: .adjust_item, targetID: "missing", amount: -1)]
        XCTAssertThrowsError(try db.commit(attempt.id, response: response))
        XCTAssertEqual(try db.session(), base); XCTAssertEqual(try db.allTurns(sessionID: base.id).count, 1)
    }
    func testHalfNarrativeOrMissingChoicesRejected() throws {
        var response = valid(); response.choices = []
        XCTAssertThrowsError(try RuleValidator.apply(response, to: GameSession(settings: CreationDraft())))
        response = valid(""); XCTAssertThrowsError(try RuleValidator.apply(response, to: GameSession(settings: CreationDraft())))
    }
    func testDuplicateChoicesRejected() throws {
        var response = valid(); response.choices = [VisibleText("等待"), VisibleText("等待"), VisibleText("離開")]
        XCTAssertThrowsError(try RuleValidator.apply(response, to: GameSession(settings: CreationDraft())))
    }
    func testTurnIDCannotCommitTwice() throws {
        let db = try store(); let base = try opened(db); let attempt = try ready(db, base)
        _ = try db.commit(attempt.id, response: valid())
        XCTAssertThrowsError(try db.commit(attempt.id, response: valid()))
        XCTAssertEqual(try db.allTurns(sessionID: base.id).count, 2)
    }
    func testCancelledResponseCannotCommit() throws {
        let db = try store(); let base = try opened(db); let attempt = try ready(db, base)
        _ = try db.transition(attempt.id, .cancelled)
        XCTAssertThrowsError(try db.commit(attempt.id, response: valid())); XCTAssertEqual(try db.session(), base)
    }
    func testColdLaunchAbandonsPending() throws {
        let db = try store(); let base = try opened(db); let attempt = try ready(db, base)
        XCTAssertEqual(try db.abandonPending().count, 1)
        XCTAssertEqual(try db.attempt(attempt.id)?.phase, .cancelled)
        XCTAssertEqual(try db.session(), base)
    }
    func testLateOldSessionCannotPolluteNewSession() throws {
        let db = try store(); let old = try opened(db); let attempt = try ready(db, old)
        try db.deleteGame()
        let new = try opened(db)
        XCTAssertNotEqual(old.id, new.id); XCTAssertNotEqual(old.seed, new.seed)
        XCTAssertThrowsError(try db.commit(attempt.id, response: valid()))
        try db.record(ApiUsage(id: "late", attempt: attempt))
        XCTAssertTrue(try db.usage().isEmpty); XCTAssertNil(try db.memory(sessionID: old.id))
        XCTAssertEqual(try db.session(), new)
    }
    func testHiddenItemProjectionDoesNotLeakCountOrName() {
        var session = GameSession(settings: CreationDraft())
        session.world.inventory = [InventoryEntry(id: "hidden", name: "夾層密函")]
        XCTAssertTrue(PlayerVisibleProjection(session).inventory.isEmpty)
    }
    func testHiddenFactBlockedInNarrativeAndChoice() throws {
        var session = GameSession(settings: CreationDraft())
        session.world.hiddenFacts = [HiddenFact(id: "traitor", truth: "師父是叛徒", forbiddenTerms: ["叛徒"])]
        XCTAssertThrowsError(try RuleValidator.apply(valid("你知道師父是叛徒。"), to: session))
        var response = valid(); response.choices[0] = VisibleText("揭穿叛徒")
        XCTAssertThrowsError(try RuleValidator.apply(response, to: session))
    }
    func testDiscoverItemRequiresKnowledgeForProjection() throws {
        var session = GameSession(settings: CreationDraft())
        session.world.inventory = [InventoryEntry(id: "note", name: "密函")]
        var response = valid("你摸到衣袋裡的密函。")
        response.proposedChanges = [.init(operation: .discover_item, targetID: "note")]
        response.knowledgeReveals = [.init(id: "k-note", subjectID: "note", title: "密函", text: "衣袋中摸到的紙張", source: "親手摸到")]
        let next = try RuleValidator.apply(response, to: session)
        XCTAssertEqual(PlayerVisibleProjection(next).inventory.count, 1)
    }
    func testUnknownKnowledgeReferenceRejected() throws {
        var response = valid(); response.choices[0].knowledgeIDs = ["not-known"]
        XCTAssertThrowsError(try RuleValidator.apply(response, to: GameSession(settings: CreationDraft())))
    }
    func testSubjectiveHealthGuard() throws {
        var condition = PhysicalCondition(); condition.sensation = "HP 55"
        var response = valid(); response.proposedChanges = [.init(operation: .condition, physicalCondition: condition)]
        XCTAssertThrowsError(try RuleValidator.apply(response, to: GameSession(settings: CreationDraft())))
    }
    func testUnconsciousCannotHearExternalEvents() throws {
        var session = GameSession(settings: CreationDraft()); session.world.condition.conscious = false
        var response = valid(String(repeating: "旁人交談", count: 25))
        XCTAssertThrowsError(try RuleValidator.apply(response, to: session))
        response = valid("意識沉入無聲的黑暗。")
        XCTAssertNoThrow(try RuleValidator.apply(response, to: session))
    }
    func testRejectedActionHasNoChangesOrTime() throws {
        let db = try store(); let base = try opened(db); let attempt = try ready(db, base)
        var response = valid(); response.disposition = .rejected_invalid_request; response.rejectionReason = "無法直接指定自己獲得神力。"; response.continuityNotes = []
        XCTAssertEqual(try db.commit(attempt.id, response: response), base)
        XCTAssertEqual(try db.allTurns(sessionID: base.id).count, 1)
        response.proposedChanges = [.init(operation: .advance_time, amount: 5)]
        XCTAssertThrowsError(try RuleValidator.apply(response, to: base))
    }
    func testNoNegativeInventory() throws {
        var session = GameSession(settings: CreationDraft())
        session.world.inventory = [InventoryEntry(id: "medicine", name: "藥")]
        let response = StoryTurnResponse(narrative: "你試著取藥。", choices: ["等待", "觀察", "休息"], proposedChanges: [.init(operation: .adjust_item, targetID: "medicine", amount: -2)])
        XCTAssertThrowsError(try RuleValidator.apply(response, to: session))
    }
    func testCannotRewriteRuleOrPastEvent() throws {
        for kind in [EntityKind.rule, .event] {
            var session = GameSession(settings: CreationDraft()); session.world.entities = [.init(id: "canon", kind: kind, truth: "正史")]
            var response = valid(); response.proposedChanges = [.init(operation: .update_entity, targetID: "canon", entity: .init(id: "canon", kind: kind, truth: "改寫"))]
            XCTAssertThrowsError(try RuleValidator.apply(response, to: session))
        }
    }
    func testMemorySyncDoesNotModifyWorldOrTurn() throws {
        let db = try store(); let base = try opened(db); let attempt = try ready(db, base, memory: true)
        try db.saveMemory(.init(canonicalSummary: "盤點已完成"), attemptID: attempt.id)
        XCTAssertEqual(try db.session(), base); XCTAssertEqual(try db.allTurns(sessionID: base.id).count, 1)
        XCTAssertEqual(try db.memory(sessionID: base.id)?.canonicalSummary, "盤點已完成")
    }
    func testCancelledMemoryPreservesOldSnapshot() throws {
        let db = try store(); let base = try opened(db); let first = try ready(db, base, memory: true)
        try db.saveMemory(.init(canonicalSummary: "原摘要"), attemptID: first.id)
        let second = try ready(db, base, memory: true); _ = try db.transition(second.id, .cancelled)
        XCTAssertThrowsError(try db.saveMemory(.init(canonicalSummary: "不應保存"), attemptID: second.id))
        XCTAssertEqual(try db.memory(sessionID: base.id)?.canonicalSummary, "原摘要")
    }
    func testDeathReadOnly() throws {
        let db = try store(); let base = try opened(db); let attempt = try ready(db, base)
        var response = valid("你的呼吸逐漸消失，世界歸於寂靜。")
        response.choices = []; response.proposedChanges = [.init(operation: .death)]
        let ended = try db.commit(attempt.id, response: response)
        XCTAssertTrue(ended.dead)
        XCTAssertThrowsError(try db.start(GenerationAttempt(session: ended, action: "復活", model: "test")))
        XCTAssertThrowsError(try RuleValidator.apply(valid(), to: ended))
        XCTAssertFalse(try db.backup().isEmpty)
    }
    func testPagination() throws {
        let db = try store(); var base = try opened(db)
        for _ in 0..<6 { let attempt = try ready(db, base); base = try db.commit(attempt.id, response: valid()) }
        XCTAssertEqual(try db.turns(sessionID: base.id, limit: 3).map(\.number), [5,6,7])
        XCTAssertEqual(try db.turns(sessionID: base.id, before: 5, limit: 3).map(\.number), [2,3,4])
    }
    func testBackupRestoreOnlyOneSessionAndNoRemoteContext() throws {
        let db = try store(); let base = try opened(db); let data = try db.backup()
        XCTAssertThrowsError(try db.restore(data))
        try db.deleteGame(); try db.restore(data)
        let restored = try XCTUnwrap(db.session())
        XCTAssertNotEqual(restored.id, base.id); XCTAssertEqual(restored.world, base.world)
        XCTAssertTrue(try db.attempts().isEmpty)
        XCTAssertEqual(try db.allTurns(sessionID: restored.id).count, 1)
    }
    func testInvalidBackupDoesNotCreateHalfSession() throws {
        let db = try store()
        XCTAssertThrowsError(try db.restore(Data("{\"schema\":1}".utf8)))
        XCTAssertNil(try db.session())
    }
    func testDurableCommitSurvivesReopen() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path+suffix) } }
        var db: GameStore? = try GameStore(path: path)
        let base = try opened(db!); db = nil
        db = try GameStore(path: path)
        XCTAssertEqual(try db?.session(), base); XCTAssertEqual(try db?.allTurns(sessionID: base.id).count, 1)
        db = nil
    }
    func testPhaseTable() {
        XCTAssertFalse(GenerationPhase.committed.allows(.requesting))
        XCTAssertFalse(GenerationPhase.cancelled.allows(.validating))
        XCTAssertFalse(GenerationPhase.requesting.allows(.committed))
        XCTAssertTrue(GenerationPhase.in_progress.allows(.queued))
        XCTAssertTrue(GenerationPhase.validating.allows(.committing))
    }
    func testToolWhitelistAndSessionIsolation() throws {
        let session = GameSession(settings: CreationDraft())
        XCTAssertThrowsError(try ContextBuilder.query(name: "execute_sql", arguments: "{\"query\":\"DELETE\"}", session: session, history: []))
        XCTAssertThrowsError(try ContextBuilder.query(name: "get_npc_state", arguments: "{\"sessionID\":\"other\",\"query\":\"\"}", session: session, history: []))
        XCTAssertEqual(try ContextBuilder.query(name: "get_visible_inventory", arguments: "{\"query\":\"\"}", session: session, history: []), "[]")
    }
    func testUnknownPricingIsNotZero() {
        XCTAssertNil(Pricing().estimate(input: 10, cached: 0, output: 10))
        XCTAssertEqual(Pricing(input: 1, cached: 0.5, output: 2).estimate(input: 1000, cached: 200, output: 500)!, 0.0019, accuracy: 0.000001)
    }
    func testStrictSchemasHaveNoArbitraryObjects() throws {
        func inspect(_ value: Any) {
            if let object = value as? [String: Any] {
                if object["type"] as? String == "object" {
                    XCTAssertEqual(object["additionalProperties"] as? Bool, false)
                    let properties = object["properties"] as? [String: Any] ?? [:]
                    XCTAssertEqual(Set(object["required"] as? [String] ?? []), Set(properties.keys))
                }
                object.values.forEach(inspect)
            } else if let array = value as? [Any] { array.forEach(inspect) }
        }
        inspect(ResponseSchemas.story); inspect(ResponseSchemas.memory); inspect(ResponseSchemas.tools)
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: ResponseSchemas.story))
    }
    func testSQLFailureAfterTurnInsertRollsBackEverything() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path+suffix) } }
        let db = try GameStore(path: path); let base = try opened(db)
        let attempt = try ready(db, base)
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &connection), SQLITE_OK)
        defer { sqlite3_close(connection) }
        XCTAssertEqual(sqlite3_exec(connection, "CREATE TRIGGER simulated_disk_failure BEFORE INSERT ON session BEGIN SELECT RAISE(ABORT, 'injected failure'); END", nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try db.commit(attempt.id, response: valid()))
        XCTAssertEqual(try db.session(), base)
        XCTAssertEqual(try db.allTurns(sessionID: base.id).count, 1)
        XCTAssertEqual(try db.attempt(attempt.id)?.phase, .validating)
    }
    func testExtremeUntrustedAmountDoesNotCrash() {
        var base = GameSession(settings: CreationDraft())
        base.world.inventory = [InventoryEntry(id: "item", name: "物品")]
        var response = valid()
        response.proposedChanges = [.init(operation: .adjust_item, targetID: "item", amount: Int.min)]
        XCTAssertThrowsError(try RuleValidator.apply(response, to: base))
    }
    func testIncompleteOpeningKeepsDraft() throws {
        let db = try store(); var draft = CreationDraft(); draft.name = "草稿人物"; try db.saveDraft(draft)
        let base = GameSession(settings: draft); let attempt = try ready(db, base, initial: true)
        XCTAssertThrowsError(try db.commit(attempt.id, response: valid(), initial: base))
        XCTAssertNil(try db.session()); XCTAssertEqual(try db.draft(), draft)
    }

    func testImportRejectsInvalidWorldWithoutPartialSave() throws {
        let db = try store(); _ = try opened(db)
        let data = try db.backup()
        var backup = try JSONDecoder().decode(GameStore.Backup.self, from: data)
        backup.session.world.condition.vitality = -1
        try db.deleteGame()
        XCTAssertThrowsError(try db.restore(JSONEncoder().encode(backup)))
        XCTAssertNil(try db.session())
    }
    func testBoundedHistorySearchEscapesWildcardsAndIsolatesSession() throws {
        let db = try store(); let base = try opened(db)
        XCTAssertEqual(try db.searchHistory(sessionID: base.id, query: "晨光").count, 1)
        XCTAssertTrue(try db.searchHistory(sessionID: base.id, query: "%").isEmpty)
        XCTAssertTrue(try db.searchHistory(sessionID: UUID(), query: "晨光").isEmpty)
    }

}
