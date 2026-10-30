# 工程及驗收記錄

## 分層
- StoryCore / Models：世界真相、主角知識、可見投影、回合、請求與用量分離。
- Store：SQLite migration v1、唯一 session constraint、session/version/turn 檢查、回合 idempotency、WAL/FULL 交易、刪除 tombstone。世界實體作為型別化 session aggregate 存 JSON；turn / attempts / memory / usage 分表與索引，避免數萬行時間線整批載入。未來 migration 必須增版本並在交易中轉換，禁止重置資料庫。
- RuleValidator：型別命令白名單，選項、物品來源／數量／裝備、秘密、認知引用、主觀健康、死亡及歷史不可改寫檢查。拒絕行動不保存回合。
- ContextBuilder：固定世界規則、近期回合、本局派生記憶、受限只讀工具；工具最多四輪，不可寫入。NPC 排程只在玩家動作觸發推演，不做背景付費模擬。
- OpenAIClient / AppModel：原生 HTTPS Responses API；POST 不自動重試，GET 最多三次退避；同一 ID 輪詢；過期／停止／冷啟動作廢；完整回應才交易提交。
- SwiftUI：六步草稿精靈、五分頁、按頁載入與 LazyVStack、接近底部才自動捲動、待提交泡泡、物品 AI 行動、資料分享及匯入。

## 安全與限制
純文字的語意資訊洩漏不能只靠規則完全證明。本機阻擋未揭露秘密關鍵詞、未知 knowledge ID、隱藏背包資訊與若干全知敘事型態，配合主觀視角提示及結構分離；真實模型紅隊／長局測試仍必要。醫學暗示、語意改寫秘密等仍可能漏判，不能宣稱百分之百防劇透。
自訂世界規則以正史固定並提供 AI，數值、時間方向、物品與裝備等由確定性驗證；任意自然語言物理規則無法由通用 validator 全面證明。

API 失敗不會自動重送 POST；玩家可檢查錯誤後自行重試。完整候選的正文篇幅不符時，允許一次明確標示費用的正文修正，規則見 1.1.0 更新。已有 response ID 的短暫 GET 錯誤最多重試三次，長時間斷線安全失敗。本機匯出完整備份包含秘密，普通小說匯出只含已完成的玩家可見文字。

## 測試
原版 42 項核心自動測試涵蓋草稿、不同題材資料、原子提交／失敗不污染、半 JSON、缺選項、重複回合、取消／冷啟動、跨局晚到回覆、隱藏物品與秘密、主角認知、昏迷限制、主觀健康、永久死亡、記憶唯讀盤點、分頁、備份恢復、SQLite 重開、SQL 寫入中途失敗的完整回滾、備份數值驗證、帶萬用字元的歷史查詢、狀態轉移、工具白名單、未知費用及 HTTP 金鑰／權限／限流／離線。原生 XCUITest 另外驗證新安裝首頁、未設定 Key 的驗證按鈕、精靈上下步及草稿離開流程（全程無 API 呼叫）。GitHub Actions 在測試成功後才建立真正 iphoneos arm64 IPA，驗證 ZIP、Info.plist、Mach-O 及簽章不存在。

尚需持有有效 BYOK 金鑰的實測：各模型能力／工具連續呼叫、真實故事品質、多題材長局、iPhone 背景切換／鎖屏／殺程序、Dynamic Type／VoiceOver／鍵盤及長歷史效能。沒有實測證據不得視為通過。

## 官方文件（2026-10-30 查閱）
- https://developers.openai.com/api/docs/guides/background
- https://developers.openai.com/api/docs/guides/structured-outputs
- https://developers.openai.com/api/docs/guides/conversation-state
- https://developer.apple.com/documentation/uikit/preparing-your-ui-to-run-in-the-background
- https://docs.github.com/en/actions/tutorials/store-and-share-data

## 1.1.0（Build 2）更新
劇情頁改用頂部安全區資訊卡與底部安全區輸入，所有選項置於主捲動區垂直完整換行。最大輔助字級時資訊卡移入捲動內容，保留導覽列健康捷徑及前往最新選項按鈕，避免固定卡片壓縮閱讀區。健康卡、健康詳情與角色頁共用 HealthProjection；只讀已提交感知字串，不以 HP/內部數值推斷症狀，舊資料含禁用字樣時提供安全 fallback。閱讀字級 14–22，並繼續遵循 Dynamic Type、VoiceOver 與減少動態效果。

CreationDraft 新增可選 narrativeRange，舊 JSON 欄位缺少時由原 length 推導 75%～125% 範圍（200→150～250、120→90～150）。SQLite schema 保持 v1，舊回合不改寫；新 range 只在玩家明確儲存時寫入當前 session。全域舊 narrativeLength 不再覆蓋存檔。新增可選 lengthReport 亦兼容舊回合；Keychain service、bundle ID、資料庫路徑不變。

所有 narrative.text 合計只計 Unicode Han（包含擴展字與〇），標點、英文、數字、空白、符號及選項皆不計。正常回合必須落於上下限，提示優先範圍為區間的 40%～70%（150～250→190～220）。拒絕、結局、前後均昏迷可短篇，甦醒不豁免；memoryOnly 完全獨立。
完整候選先檢查世界及正文；篇幅超出區間最多發一次 narrative-only 修正。程式保留原始命令／選項／認知揭露，只替換正文並重新驗證，不能把兩份世界變更合併。修正請求有獨立 usage ledger 項目與畫面提示；修正失敗／取消不提交。存檔交易再次驗證篇幅並保存實際漢字數、當時範圍、修正次數與例外原因。輸出預算依最大篇幅、開局／一般／修正、模型系列計算並設上限；incomplete 不會被當成完成。

新增舊 JSON／舊 SQLite 重開、設定持久化與請求上下文、正文計數／範圍／例外、修正保留命令、取消回滾、健康 fallback／同步／零用量測試。原生 UI 驗收在一般 iPhone 與 SE 模擬器執行，包含健康 sheet、角色一致性、五個長選項、鍵盤、切 Tab／前背景、最大輔助字級及版本資訊。測試專用故事只存在 Debug 及獨立記憶體 DB，Release 不包含測試入口。
有效 Key 的實際生成品質與修正費用、實體 iPhone 17 Pro 及現有側載簽署身份下的升級保留行為，仍需使用者裝置實測；不宣稱未執行的線上／實機驗收通過。
