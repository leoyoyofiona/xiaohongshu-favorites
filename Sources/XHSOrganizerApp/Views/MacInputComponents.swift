import SwiftUI

struct MacInputField: View {
    let placeholder: String
    @Binding var text: String
    var systemImage: String? = nil
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(.tertiary))
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .onSubmit {
                    onSubmit?()
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
    }
}

struct MacEditorCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
    }
}

extension View {
    func macEditorCard() -> some View {
        modifier(MacEditorCardModifier())
    }
}
