import SwiftUI

struct RootView: View {
    @ObservedObject var monitor: SystemMonitor
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                ContentView(monitor: monitor, uploader: MacStatusAppState.shared.uploader)
                    .environmentObject(authManager)
            } else {
                LoginView()
                    .environmentObject(authManager)
            }
        }
    }
}
