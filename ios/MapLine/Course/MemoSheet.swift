import SwiftUI

/// 지도 위 메모를 고치는 자리.
///
/// KakaoMapsSDK는 POI를 코드로 옮길 수는 있지만 사용자가 끄는 이벤트를 주지 않는다.
/// 그래서 이동을 고른 뒤 지도에서 새 자리를 꾹 누르게 한다. 팬 제스처와도 섞이지 않고,
/// 메모의 id는 그대로라 저장된 문서에서도 같은 메모로 남는다.
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
