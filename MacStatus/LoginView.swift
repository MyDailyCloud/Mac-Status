import SwiftUI
import AppKit

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("登录后解锁监控")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("使用 GitHub 账号通过 Supabase 登录，登录成功后开始刷新并上传监控数据。")
                .font(.callout)
                .foregroundColor(.secondary)
            
            if let message = authManager.errorMessage {
                Text(message)
                    .foregroundColor(.red)
                    .font(.footnote)
            }
            
            Button(action: {
                authManager.signInWithGitHub()
            }) {
                HStack {
                    if authManager.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Image(systemName: "person.crop.circle")
                    Text("使用 GitHub 登录")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(authManager.isLoading)
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
            
            Spacer()
            
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Text("退出")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
