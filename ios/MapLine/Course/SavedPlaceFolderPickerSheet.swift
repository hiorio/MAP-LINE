import SwiftUI
import UIKit

/// 동선에서 발견한 장소를 어느 개인 보관함 폴더에 넣을지 고른다.
///
/// 장소 상세에서 바로 열리므로 폴더를 찾으러 보관함 전체 화면까지 왕복하지 않는다.
struct SavedPlaceFolderPickerSheet: View {
    let placeName: String
    let currentGroupID: String?
    /// nil이면 성공, 문자열이면 저장 실패 이유다. 실패했을 때 시트를 닫지 않아 다시 고를 수 있다.
    let onPick: (SavedPlaceGroup) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var groups: [SavedPlaceGroup] = [SavedPlaceGroup.inbox]
    @State private var storageError: String?

    private let groupStore = SavedPlaceGroupStore(storage: AppGroupSavedPlaceGroupStorage())

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(groups) { group in
                        Button {
                            if let error = onPick(group) {
                                storageError = error
                            } else {
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: group.marker.symbolName)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(color(group))
                                    .frame(width: 36, height: 36)
                                    .background(color(group).opacity(0.14), in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(group.id == currentGroupID ? "현재 저장된 폴더" : "이 폴더에 저장")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: group.id == currentGroupID
                                      ? "checkmark.circle.fill"
                                      : "chevron.right")
                                    .foregroundStyle(group.id == currentGroupID
                                                     ? Color.green
                                                     : Color.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("stop.save.folder.\(group.id)")
                    }
                } header: {
                    Text("‘\(placeName)’ 저장 위치")
                } footer: {
                    Text("새 폴더가 필요하면 보관함에서 만든 뒤 다시 선택할 수 있습니다.")
                }
            }
            .navigationTitle("보관함에 저장")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
        }
        .alert(
            "보관함 폴더를 읽지 못했습니다",
            isPresented: Binding(
                get: { storageError != nil },
                set: { if !$0 { storageError = nil } }
            )
        ) {
            Button("확인", role: .cancel) { storageError = nil }
        } message: {
            Text(storageError ?? "")
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        do {
            groups = try groupStore.all()
        } catch {
            storageError = error.localizedDescription
        }
    }

    private func color(_ group: SavedPlaceGroup) -> Color {
        Color(uiColor: UIColor(hex: group.colorHex) ?? .systemBlue)
    }
}
