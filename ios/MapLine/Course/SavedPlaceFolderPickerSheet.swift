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
    @State private var groups: [SavedPlaceGroup] = []
    @State private var creatingFolder = false
    @State private var storageError: String?

    private let groupStore = SavedPlaceGroupStore(storage: AppGroupSavedPlaceGroupStorage())

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if groups.isEmpty {
                        Text("저장할 폴더를 먼저 만들어 주세요.")
                            .foregroundStyle(.secondary)
                    }
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
                    Text("장소는 선택한 폴더의 마크와 색으로 지도에 표시됩니다.")
                }
            }
            .navigationTitle("보관함에 저장")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { creatingFolder = true } label: {
                        Label("새 폴더", systemImage: "folder.badge.plus")
                    }
                    .accessibilityIdentifier("stop.save.addFolder")
                }
            }
        }
        .sheet(isPresented: $creatingFolder) {
            SavedPlaceGroupEditor(group: nil) { group in
                do {
                    guard try groupStore.add(group) else {
                        storageError = "같은 이름의 폴더가 이미 있습니다."
                        return
                    }
                    reload()
                } catch {
                    storageError = error.localizedDescription
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
            // `inbox`는 예전 데이터 복구용이다. 새 장소는 사용자가 만든 폴더에만 담는다.
            groups = try groupStore.all().filter { $0.id != SavedPlaceGroup.inboxID }
        } catch {
            storageError = error.localizedDescription
        }
    }

    private func color(_ group: SavedPlaceGroup) -> Color {
        Color(uiColor: UIColor(hex: group.colorHex) ?? .systemBlue)
    }
}
