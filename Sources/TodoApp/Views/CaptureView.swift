import SwiftUI

struct CaptureView: View {
    @Bindable var model: AppModel
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Capture")
                .font(.headline)

            TextEditor(text: $model.captureText)
                .font(.body)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary)
                )

            HStack {
                Text(model.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button("Cancel") {
                    onClose()
                }
                Button {
                    Task {
                        await model.planCapture()
                        if model.captureText.isEmpty {
                            onClose()
                        }
                    }
                } label: {
                    if model.isPlanning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Plan", systemImage: "sparkles")
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(model.isPlanning || model.captureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
    }
}
