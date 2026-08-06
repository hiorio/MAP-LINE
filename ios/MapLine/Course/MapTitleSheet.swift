import SwiftUI

/// 현재 지도의 이름을 붙인다. 목록과 공유 링크에서 같은 이름을 쓴다.
struct MapTitleSheet: View {
    let currentTitle: String
    let onSave: (String) -> Void
    let onCreateNew: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String

    init(
        currentTitle: String,
        onSave: @escaping (String) -> Void,
        onCreateNew: @escaping () -> Void
    ) {
        self.currentTitle = currentTitle
        self.onSave = onSave
        self.onCreateNew = onCreateNew
        _title = State(initialValue: currentTitle)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("지도 이름") {
                    TextField("예: 강남 데이트 코스", text: $title)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("mapTitle.text")
                }

                Section {
                    Button {
                        onCreateNew()
                        dismiss()
                    } label: {
                        Label("새 지도 만들기", systemImage: "doc.badge.plus")
                    }
                    .accessibilityIdentifier("mapTitle.newMap")
                } footer: {
                    Text("현재 지도는 저장한 뒤 새 지도를 시작합니다.")
                }
            }
            .navigationTitle("지도 이름 변경")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        onSave(title.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("mapTitle.save")
                }
            }
        }
    }
}
