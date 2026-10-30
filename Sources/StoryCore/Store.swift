import Foundation
import CSQLite

/// One serialized connection; all mutation paths are transactions. JSON payloads are versioned by SQL migrations.
public final class GameStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    public init(path: String) throws {
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw StoryError.database("無法開啟") }
        sqlite3_busy_timeout(db, 5000)
        try execute("PRAGMA foreign_keys=ON")
        _ = try rows("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=FULL")
        let version = Int(try rows("PRAGMA user_version").first?.first ?? "0") ?? 0
        guard version <= 1 else { throw StoryError.database("資料版本較新，請更新 App；未重置資料。") }
        if version == 0 {
            try transaction {
                try execute("CREATE TABLE session (singleton INTEGER PRIMARY KEY CHECK(singleton=1), id TEXT UNIQUE NOT NULL, version INTEGER NOT NULL, payload TEXT NOT NULL)")
                try execute("CREATE TABLE draft (singleton INTEGER PRIMARY KEY CHECK(singleton=1), payload TEXT NOT NULL)")
                try execute("CREATE TABLE attempts (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, phase TEXT NOT NULL, payload TEXT NOT NULL)")
                try execute("CREATE INDEX attempts_session ON attempts(session_id,phase)")
                try execute("CREATE TABLE turns (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, number INTEGER NOT NULL, payload TEXT NOT NULL, UNIQUE(session_id,number))")
                try execute("CREATE INDEX turns_page ON turns(session_id,number DESC)")
                try execute("CREATE TABLE memory (session_id TEXT PRIMARY KEY, version INTEGER NOT NULL, payload TEXT NOT NULL)")
                try execute("CREATE TABLE usage (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, payload TEXT NOT NULL)")
                try execute("CREATE INDEX usage_session ON usage(session_id)")
                try execute("CREATE TABLE tombstones (session_id TEXT PRIMARY KEY)")
                try execute("PRAGMA user_version=1")
            }
        }
    }
    deinit { sqlite3_close(db) }
    private func synchronized<T>(_ body: () throws -> T) rethrows -> T { lock.lock(); defer { lock.unlock() }; return try body() }
    private func statement(_ sql: String, _ args: [String]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw StoryError.database(String(cString: sqlite3_errmsg(db))) }
        for (index, value) in args.enumerated() {
            let status = value.withCString { sqlite3_bind_text(stmt, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            if status != SQLITE_OK { sqlite3_finalize(stmt); throw StoryError.database("綁定失敗") }
        }
        return stmt
    }
    private func execute(_ sql: String, _ args: [String] = []) throws {
        let stmt = try statement(sql, args); defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoryError.database(String(cString: sqlite3_errmsg(db))) }
    }
    private func rows(_ sql: String, _ args: [String] = []) throws -> [[String]] {
        let stmt = try statement(sql, args); defer { sqlite3_finalize(stmt) }
        var result: [[String]] = []
        while true {
            let code = sqlite3_step(stmt)
            if code == SQLITE_DONE { return result }
            guard code == SQLITE_ROW else { throw StoryError.database(String(cString: sqlite3_errmsg(db))) }
            result.append((0..<sqlite3_column_count(stmt)).map { column in sqlite3_column_text(stmt, column).map { String(cString: $0) } ?? "" })
        }
    }
    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do { let result = try body(); try execute("COMMIT"); return result }
        catch { try? execute("ROLLBACK"); throw error }
    }
    public func session() throws -> GameSession? { try synchronized {
        try rows("SELECT payload FROM session WHERE singleton=1").first.map { try JSONCoding.decode(GameSession.self, $0[0]) }
    } }
    public func saveDraft(_ draft: CreationDraft) throws { try synchronized { try execute("INSERT OR REPLACE INTO draft VALUES(1,?)", [try JSONCoding.encode(draft)]) } }
    public func draft() throws -> CreationDraft { try synchronized { try rows("SELECT payload FROM draft").first.map { try JSONCoding.decode(CreationDraft.self, $0[0]) } ?? CreationDraft() } }
    public func start(_ attempt: GenerationAttempt, initial: Bool = false) throws { try synchronized { try transaction {
        guard try rows("SELECT 1 FROM tombstones WHERE session_id=?", [attempt.sessionID.uuidString]).isEmpty,
              try attempts().allSatisfy({ $0.phase.terminal }) else { throw StoryError.stale }
        if initial { guard try session() == nil else { throw StoryError.invalid("只能有一個有效遊玩存檔。") } }
        else { guard let current = try session(), current.id == attempt.sessionID, current.version == attempt.baseVersion, !current.dead else { throw StoryError.stale } }
        try execute("INSERT INTO attempts VALUES(?,?,?,?)", [attempt.id.uuidString, attempt.sessionID.uuidString, attempt.phase.rawValue, try JSONCoding.encode(attempt)])
    } } }
    public func attempts() throws -> [GenerationAttempt] { try synchronized { try rows("SELECT payload FROM attempts").map { try JSONCoding.decode(GenerationAttempt.self, $0[0]) } } }
    public func attempt(_ id: UUID) throws -> GenerationAttempt? { try synchronized { try rows("SELECT payload FROM attempts WHERE id=?", [id.uuidString]).first.map { try JSONCoding.decode(GenerationAttempt.self, $0[0]) } } }
    @discardableResult public func transition(_ id: UUID, _ phase: GenerationPhase, responseID: String? = nil) throws -> GenerationAttempt { try synchronized { try transaction {
        guard var attempt = try attempt(id), attempt.phase.allows(phase) else { throw StoryError.stale }
        attempt.phase = phase
        if let responseID { attempt.responseID = responseID }
        try execute("UPDATE attempts SET phase=?,payload=? WHERE id=?", [phase.rawValue, try JSONCoding.encode(attempt), id.uuidString])
        return attempt
    } } }
    public func record(_ usage: ApiUsage) throws { try synchronized {
        // Deleted sessions never resurrect metadata, even on late network callbacks.
        guard try rows("SELECT 1 FROM tombstones WHERE session_id=?", [usage.sessionID.uuidString]).isEmpty else { return }
        try execute("INSERT OR REPLACE INTO usage VALUES(?,?,?)", [usage.id, usage.sessionID.uuidString, try JSONCoding.encode(usage)])
    } }
    public func usage() throws -> [ApiUsage] { try synchronized { try rows("SELECT payload FROM usage ORDER BY rowid DESC").map { try JSONCoding.decode(ApiUsage.self, $0[0]) } } }
    public func commit(_ id: UUID, response: StoryTurnResponse, initial: GameSession? = nil) throws -> GameSession { try synchronized { try transaction {
        guard let attempt = try attempt(id), !attempt.memoryOnly, attempt.phase == .validating,
              attempt.deadline > Date(), try rows("SELECT 1 FROM tombstones WHERE session_id=?", [attempt.sessionID.uuidString]).isEmpty else { throw StoryError.stale }
        let persisted = try session()
        guard let original = persisted ?? initial, original.id == attempt.sessionID, original.version == attempt.baseVersion, original.lastCommittedTurn == attempt.baseTurn,
              (persisted != nil || original.version == 0), try rows("SELECT 1 FROM turns WHERE id=?", [id.uuidString]).isEmpty else { throw StoryError.stale }
        var next = try RuleValidator.apply(response, to: original)
        if response.disposition == .rejected_invalid_request {
            var cancelled = attempt; cancelled.phase = .cancelled
            try execute("UPDATE attempts SET phase=?,payload=? WHERE id=?", [cancelled.phase.rawValue, try JSONCoding.encode(cancelled), id.uuidString]); return original
        }
        // validating → committing → committed occurs entirely inside this transaction.
        if persisted == nil {
            guard [EntityKind.rule, .location, .npc].allSatisfy({ kind in next.world.entities.contains { $0.kind == kind } }), !next.knowledge.isEmpty else {
                throw StoryError.invalid("開局缺少世界規則、地點、人物或可知情報，草稿已保留。")
            }
        }
        next.version += 1; next.lastCommittedTurn += 1
        let turn = CommittedTurn(id: id, sessionID: next.id, number: next.lastCommittedTurn, action: attempt.action, narrative: response.narrative.map(\.text).joined(separator: "\n\n"), choices: response.choices.map(\.text), summary: response.continuityNotes, changes: response.proposedChanges, date: Date())
        try execute("INSERT INTO turns VALUES(?,?,?,?)", [id.uuidString, next.id.uuidString, String(turn.number), try JSONCoding.encode(turn)])
        try execute("INSERT OR REPLACE INTO session VALUES(1,?,?,?)", [next.id.uuidString, String(next.version), try JSONCoding.encode(next)])
        try execute("DELETE FROM draft")
        // transition() cannot nest a transaction. State update remains in this very transaction.
        var done = attempt; done.phase = .committed
        try execute("UPDATE attempts SET phase=?,payload=? WHERE id=?", [done.phase.rawValue, try JSONCoding.encode(done), id.uuidString])
        return next
    } } }
    public func turns(sessionID: UUID, before: Int = Int.max, limit: Int = 40) throws -> [CommittedTurn] { try synchronized {
        try rows("SELECT payload FROM turns WHERE session_id=? AND number<? ORDER BY number DESC LIMIT ?", [sessionID.uuidString, String(before), String(max(1, min(limit, 100)))]).map { try JSONCoding.decode(CommittedTurn.self, $0[0]) }.reversed()
    } }
    public func searchHistory(sessionID: UUID, query: String) throws -> [CommittedTurn] { try synchronized {
        guard query.count <= 200 else { throw StoryError.invalid("搜尋字數過長。") }
        let escaped = query.replacingOccurrences(of: "!", with: "!!").replacingOccurrences(of: "%", with: "!%").replacingOccurrences(of: "_", with: "!_")
        return try rows("SELECT payload FROM turns WHERE session_id=? AND payload LIKE ? ESCAPE '!' ORDER BY number DESC LIMIT 8", [sessionID.uuidString, "%" + escaped + "%"]).map { try JSONCoding.decode(CommittedTurn.self, $0[0]) }.reversed()
    } }
    public func allTurns(sessionID: UUID) throws -> [CommittedTurn] { try synchronized { try rows("SELECT payload FROM turns WHERE session_id=? ORDER BY number", [sessionID.uuidString]).map { try JSONCoding.decode(CommittedTurn.self, $0[0]) } } }
    public func saveMemory(_ memory: NarrativeMemory, attemptID: UUID) throws { try synchronized { try transaction {
        guard let attempt = try attempt(attemptID), attempt.memoryOnly, attempt.phase == .validating,
              let session = try session(), session.id == attempt.sessionID, session.version == attempt.baseVersion,
              attempt.deadline > Date(), !memory.canonicalSummary.isEmpty, memory.canonicalSummary.count <= 16000 else { throw StoryError.stale }
        try execute("INSERT OR REPLACE INTO memory VALUES(?,?,?)", [session.id.uuidString, String(session.version), try JSONCoding.encode(memory)])
        var done = attempt; done.phase = .committed
        try execute("UPDATE attempts SET phase=?,payload=? WHERE id=?", [done.phase.rawValue, try JSONCoding.encode(done), done.id.uuidString])
    } } }
    public func memory(sessionID: UUID) throws -> NarrativeMemory? { try synchronized {
        try rows("SELECT payload FROM memory WHERE session_id=?", [sessionID.uuidString]).first.map { try JSONCoding.decode(NarrativeMemory.self, $0[0]) }
    } }
    public func deleteGame() throws { try synchronized { try transaction {
        if let session = try session() { try execute("INSERT OR IGNORE INTO tombstones VALUES(?)", [session.id.uuidString]) }
        for attempt in try attempts() { try execute("INSERT OR IGNORE INTO tombstones VALUES(?)", [attempt.sessionID.uuidString]) }
        for table in ["session", "draft", "turns", "memory", "attempts", "usage"] { try execute("DELETE FROM \(table)") }
    } } }
    public func abandonPending() throws -> [GenerationAttempt] { try synchronized {
        let pending = try attempts().filter { !$0.phase.terminal }
        for item in pending { _ = try transition(item.id, .cancelled) }
        return pending
    } }
    public struct Backup: Codable { public var schema: Int; public var session: GameSession; public var turns: [CommittedTurn]; public var memory: NarrativeMemory? }
    public func backup() throws -> Data { try synchronized {
        guard let session = try session() else { throw StoryError.invalid("沒有可匯出的存檔。") }
        return try JSONEncoder().encode(Backup(schema: 1, session: session, turns: allTurns(sessionID: session.id), memory: memory(sessionID: session.id)))
    } }
    public func restore(_ data: Data) throws { try synchronized { try transaction {
        guard try session() == nil, try attempts().allSatisfy({ $0.phase.terminal }), data.count <= 100_000_000 else { throw StoryError.invalid("匯入前須先刪除現有遊戲。") }
        var backup = try JSONDecoder().decode(Backup.self, from: data)
        guard backup.schema == 1, backup.session.version > 0, backup.session.version == backup.turns.count,
              backup.session.lastCommittedTurn == backup.turns.count, !backup.turns.isEmpty,
              backup.turns.enumerated().allSatisfy({ $0.element.sessionID == backup.session.id && $0.element.number == $0.offset + 1 }),
              Set(backup.turns.map(\.id)).count == backup.turns.count else { throw StoryError.invalid("備份結構或回合順序不完整。") }
        try backup.session.settings.validate()
        try RuleValidator.validateSnapshot(backup.session)
        // Import is a fresh local lineage; no remote IDs/attempts/caches are imported.
        backup.session.id = UUID()
        try execute("INSERT INTO session VALUES(1,?,?,?)", [backup.session.id.uuidString, String(backup.session.version), try JSONCoding.encode(backup.session)])
        for var turn in backup.turns {
            turn.id = UUID(); turn.sessionID = backup.session.id
            try execute("INSERT INTO turns VALUES(?,?,?,?)", [turn.id.uuidString, turn.sessionID.uuidString, String(turn.number), try JSONCoding.encode(turn)])
        }
        if let memory = backup.memory { try execute("INSERT INTO memory VALUES(?,?,?)", [backup.session.id.uuidString, String(backup.session.version), try JSONCoding.encode(memory)]) }
    } } }
}
