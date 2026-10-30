# ChaiAIStory
原生 iPhone AI 文字世界／人生模擬 RPG。SwiftUI、SQLite、Keychain；iOS 17 以上。預設繁體中文，支援九種題材、自訂角色與世界、連續小說、背包／角色／世界見聞、永久死亡及單一遊玩存檔。

## 使用
安裝自行簽署的 App →「API 設定」貼上自己的 OpenAI project key → 選模型並驗證 →「開始遊戲」。模型須支援 Responses 與 Structured Outputs；背景功能以實際驗證為準，不支援時可明確切成前景模式。未設定金鑰只可讀取本機故事，沒有假生成內容。

劇情行動與物品互動會呼叫 API 並可能計費。查看資料免費；每輪完整驗證及 SQLite 交易成功才保存。記憶重整是獨立付費請求，不推進故事。價格及預算都是本機估算，非官方餘額；取消／失敗用量無法取得時標示未知。

## 建置及下載
GitHub → Actions → **Build unsigned iPhone IPA** → Run workflow（push main 也自動執行）。先執行 swift test --parallel，再以 iPhoneOS SDK / arm64 編譯及驗證未簽署狀態。
成功後下載 artifact **ChaiAIStory-Unsigned**，解壓一次只會得到 **ChaiAIStory-Unsigned.ipa**。必須自行選擇相容方式簽署後才能安裝，沒有內嵌憑證、Team ID 或指定簽署服務。

本機 Mac：Xcode 16 以上開啟 ChaiAIStory.xcodeproj；python3 Scripts/generate_project.py 可無額外套件重建專案，swift test 測試核心。Simulator 可由 Xcode 選擇執行；個人裝置簽署設定由使用者自行處理，不納入交付流程。

## 資料與限制
- 金鑰存 Keychain WhenUnlockedThisDeviceOnly，不進備份；手機直連仍可能被擷取，請使用獨立 project key、最低權限與官方用量監控。
- 只向 OpenAI 傳送生成所需的故事資料，無自建伺服器或其他分析服務。本機資料庫排除自動備份，可手動匯出故事或完整備份（含劇透真相）；匯入前須刪除現有遊戲。
- 背景模式使用 background=true, store=false，平台仍有約十分鐘暫存；前景輪詢同一 ID，iOS 暫停時不保證接收。冷啟動作廢未提交回合；強制終止無法保證即時遠端取消或免 Token 費用。
- 結構化知識邊界、隱藏詞與引用檢查可阻止已知類型洩漏，但無法數學上保證任意 AI 自由文字完全不含語意劇透，仍需要真實模型及長期遊玩測試。
- 無可用 API Key 時無法完成線上端到端驗證；CI 使用注入式 HTTP 測試，正式 App 只使用真實 API。

架構、驗收狀況及官方參考見 [Docs/Engineering.md](Docs/Engineering.md)。
