import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("DeepSeek") {
                SecureField("API Key", text: $model.apiKeyDraft)
                HStack {
                    Button("Save Key") {
                        model.saveAPIKey()
                    }
                    Button("Clear") {
                        model.apiKeyDraft = ""
                        model.saveAPIKey()
                    }
                    Spacer()
                }
                Text("Model: deepseek-v4-flash. The key is stored in macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
