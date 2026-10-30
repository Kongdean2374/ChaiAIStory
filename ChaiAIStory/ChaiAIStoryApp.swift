import SwiftUI

@main struct ChaiAIStoryApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).preferredColorScheme(.dark).tint(.storyGold)
                .onChange(of: scenePhase) { _, phase in model.sceneChanged(phase == .active) }
                .alert("ChaiAIStory", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
                    Button("知道了") { model.notice = nil }
                } message: { Text(model.notice ?? "") }
        }
    }
}
extension Color {
    static let storyGold = Color(red: 0.80, green: 0.68, blue: 0.43)
    static let storyInk = Color(red: 0.065, green: 0.075, blue: 0.085)
}
struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var settings = false
    @State private var confirmDelete = false
    @State private var finalDelete = false
    var body: some View {
        Group {
            if let error = model.fatalError {
                ContentUnavailableView("無法安全開啟存檔", systemImage: "externaldrive.badge.exclamationmark", description: Text(error + "\n資料未重置，請保留 App 並回報問題。"))
            } else if model.showGame, model.session != nil {
                GameTabs()
            } else {
                NavigationStack {
                    ZStack {
                        Color.storyInk.ignoresSafeArea()
                        VStack(spacing: 24) {
                            Spacer()
                            Image(systemName: "book.closed.fill").font(.system(size: 64)).foregroundStyle(Color.storyGold).accessibilityHidden(true)
                            Text("ChaiAIStory").font(.largeTitle.bold())
                            Text("萬千世界，由你的選擇展開。").foregroundStyle(.secondary)
                            Spacer()
                            if let session = model.session {
                                Text("\(session.settings.name) · \(session.settings.genre)").font(.title3)
                                Button(session.dead ? "人生結局 · 唯讀回顧" : "繼續遊戲") {
                                    model.showGame = true
                                    if model.preferences.syncOnRestore && !session.dead { model.generate(action: "恢復存檔時記憶核對", memoryOnly: true) }
                                }.buttonStyle(PrimaryButton())
                                Button("設定") { settings = true }
                                Button("刪除角色，重新開始", role: .destructive) { confirmDelete = true }.padding(.top, 8)
                            } else {
                                Button("開始遊戲") { model.showWizard = true }.buttonStyle(PrimaryButton())
                                Button("API 設定／說明") { settings = true }
                            }
                            Spacer().frame(height: 30)
                            Text("AI 主導的沉浸式文字世界\n生成需要網路與自備 OpenAI API Key").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.padding(28)
                    }
                }
            }
        }
        .sheet(isPresented: $settings) { NavigationStack { SettingsView() } }
        .fullScreenCover(isPresented: $model.showWizard) { CreationWizard() }
        .confirmationDialog("刪除本局角色？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("繼續確認刪除", role: .destructive) { finalDelete = true }
        } message: { Text("將永久刪除本局劇情、世界、秘密、AI 上下文與附件。API Key 會保留。") }
        .alert("最後確認", isPresented: $finalDelete) {
            Button("永久刪除", role: .destructive) { model.delete() }; Button("取消", role: .cancel) {}
        } message: { Text("此操作無法復原。請先匯出要保留的故事或備份。") }
    }
}
struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(16).background(Color.storyGold.opacity(configuration.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(Color.black)
    }
}
struct GameTabs: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        TabView(selection: $model.selectedTab) {
            NavigationStack { StoryTimeline() }.tabItem { Label("劇情", systemImage: "text.bubble") }.tag(0)
            NavigationStack { InventoryView() }.tabItem { Label("背包", systemImage: "bag") }.tag(1)
            NavigationStack { CharacterView() }.tabItem { Label("角色", systemImage: "person.crop.circle") }.tag(2)
            NavigationStack { WorldView() }.tabItem { Label("世界", systemImage: "globe.asia.australia") }.tag(3)
            NavigationStack { SettingsView() }.tabItem { Label("設定", systemImage: "gearshape") }.tag(4)
        }
    }
}
