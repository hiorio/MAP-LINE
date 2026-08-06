import SwiftUI

/// 지도 위 메모를 고치는 자리.
///
/// 지도에서는 메모를 길게 누른 채 바로 끌어 옮길 수 있다. 여기의 이동 버튼은 드래그가
/// 어려운 사용자를 위한 보조 경로다. 어느 방식이든 id는 그대로라 같은 메모로 남는다.
struct MemoSheet: View {
    let label: MapLabel
    let onSave: (String) -> Void
    let onMove: () -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(
        label: MapLabel,
        onSave: @escaping (String) -> Void,
        onMove: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.label = label
        self.onSave = onSave
        self.onMove = onMove
        self.onRemove = onRemove
        _text = State(initialValue: label.text)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("내용") {
                    TextField("메모", text: $text, axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityIdentifier("memo.text")
                }

                Section {
                    Button {
                        onMove()
                        dismiss()
                    } label: {
                        Label("위치 옮기기", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                    }
                    .accessibilityIdentifier("memo.move")

                    Button(role: .destructive) {
                        onRemove()
                        dismiss()
                    } label: {
                        Label("메모 삭제", systemImage: "trash")
                    }
                    .accessibilityIdentifier("memo.remove")
                }
            }
            .navigationTitle("메모")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
