import SwiftUI

struct RootView: View {
    @ObservedObject var monitor: SystemMonitor
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var uploader = MetricsUploader()
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                ContentView(monitor: monitor, uploader: uploader)
                    .environmentObject(authManager)
            } else {
                LoginView()
                    .environmentObject(authManager)
            }
        }
        .onAppear(perform: syncMonitoring)
        .onChange(of: authManager.isAuthenticated) { _ in
            syncMonitoring()
        }
    }
    
    private func syncMonitoring() {
        if authManager.isAuthenticated {
            monitor.startMonitoring()
            monitor.onMetricsUpdate = { snapshot in
                uploader.handle(snapshot: snapshot, authManager: authManager)
            }
        } else {
            monitor.stopMonitoring()
            monitor.onMetricsUpdate = nil
        }
    }
}
