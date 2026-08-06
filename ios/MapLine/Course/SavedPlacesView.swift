import SwiftUI
import UIKit

/// 개인 장소 보관함. 공유로 받은 곳뿐 아니라 직접 찾은 장소도 폴더별로 모아 둔다.
struct SavedPlacesView: View {
    let onAdd: (MapPlace) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var groups: [SavedPlaceGroup] = []
    @State private var places: [SavedPlace] = []
    @State private var editor: GroupEditorTarget?
    @State private var deletingGroup: SavedPlaceGroup?

    private let placeStore = SavedPlaceStore(storage: AppGroupPlaceStorage())
    private let groupStore = SavedPlaceGroupStore(storage: AppGroupSavedPlaceGroupStorage())

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("장소를 직접 모으거나 다른 앱에서 공유해 폴더별로 정리할 수 있습니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("내 폴더") {
                    ForEach(groups) { group in
                        NavigationLink {
                            SavedPlaceGroupView(
                                group: group,
                                groups: groups,
                                onAdd: onAdd,
                                onChanged: reload
                            )
                        } label: {
                            groupRow(group)
                        }
                        .accessibilityIdentifier("saved.group.\(group.id)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if group.id != SavedPlaceGroup.inboxID {
                                Button(role: .destructive) { deletingGroup = group } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                                Button { editor = GroupEditorTarget(group: group) } label: {
                                    Label("편집", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                        .contextMenu {
                            if group.id != SavedPlaceGroup.inboxID {
                                Button { editor = GroupEditorTarget(group: group) } label: {
                                    Label("폴더 편집", systemImage: "pencil")
                                }
                                Button(role: .destructive) { deletingGroup = group } label: {
                                    Label("폴더 삭제", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("보관함")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { editor = GroupEditorTarget(group: nil) } label: {
                        Label("새 폴더", systemImage: "folder.badge.plus")
                    }
                    .accessibilityIdentifier("saved.addGroup")
                }
            }
        }
        .sheet(item: $editor) { target in
            SavedPlaceGroupEditor(group: target.group) { group in
                if target.group == nil {
                    _ = groupStore.add(group)
                } else {
                    groupStore.update(group)
                }
                reload()
            }
        }
        .alert(
            "폴더를 삭제할까요?",
            isPresented: Binding(
                get: { deletingGroup != nil },
                set: { if !$0 { deletingGroup = nil } }
            ),
            presenting: deletingGroup
        ) { group in
            Button("삭제", role: .destructive) { delete(group) }
            Button("취소", role: .cancel) { deletingGroup = nil }
        } message: { group in
            Text("‘\(group.name)’의 장소는 삭제되지 않고 ‘받은 장소’로 이동합니다.")
        }
        .onAppear(perform: reload)
    }

    private func groupRow(_ group: SavedPlaceGroup) -> some View {
        HStack(spacing: 12) {
            groupMark(group, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).font(.body.weight(.medium))
                Text(group.id == SavedPlaceGroup.inboxID
                     ? "다른 앱 공유와 미분류 장소"
                     : "직접 모아 둔 장소")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(places.filter { $0.groupID == group.id }.count)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private func reload() {
        groups = groupStore.all()
        places = placeStore.all()
    }

    private func delete(_ group: SavedPlaceGroup) {
        placeStore.moveAll(from: group.id, to: SavedPlaceGroup.inboxID)
        groupStore.remove(id: group.id)
        deletingGroup = nil
        reload()
    }
}

/// 폴더 하나의 장소 목록. 여기서 직접 장소를 검색해 담고 다른 폴더로 옮긴다.
private struct SavedPlaceGroupView: View {
    let group: SavedPlaceGroup
    let groups: [SavedPlaceGroup]
    let onAdd: (MapPlace) -> Void
    let onChanged: () -> Void

    @State private var places: [SavedPlace] = []
    @State private var added: Set<String> = []
    @State private var searching = false
    @State private var movingPlace: SavedPlace?

    private let store = SavedPlaceStore(storage: AppGroupPlaceStorage())

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    groupMark(group, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name).font(.headline)
                        Text("이 폴더의 장소는 같은 마크와 색으로 구분됩니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if places.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: group.marker.symbolName)
                            .font(.largeTitle)
                            .foregroundStyle(groupColor(group))
                        Text("아직 장소가 없습니다").font(.headline)
                        Text("오른쪽 위 + 버튼으로 원하는 장소를 직접 넣어 보세요.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                Section("장소 \(places.count)곳") {
                    ForEach(places) { place in
                        placeRow(place)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button { movingPlace = place } label: {
                                    Label("이동", systemImage: "folder")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { remove(place) } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button { movingPlace = place } label: {
                                    Label("다른 폴더로 이동", systemImage: "folder")
                                }
                                Button(role: .destructive) { remove(place) } label: {
                                    Label("보관함에서 삭제", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { searching = true } label: {
                    Label("장소 추가", systemImage: "plus")
                }
                .accessibilityIdentifier("saved.group.addPlace")
            }
        }
        .sheet(isPresented: $searching) {
            PlaceSearchSheet(title: "\(group.name)에 장소 추가", near: nil) { candidate in
                _ = store.addOrMove(candidate.asSavedPlace(groupID: group.id), to: group.id)
                reload()
            }
        }
        .sheet(item: $movingPlace) { place in
            SavedPlaceMoveSheet(place: place, groups: groups) { targetID in
                store.move(id: place.id, to: targetID)
                reload()
            }
        }
        .onAppear(perform: reload)
    }

    private func placeRow(_ place: SavedPlace) -> some View {
        HStack(spacing: 11) {
            Image(systemName: group.marker.symbolName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(groupColor(group))
                .frame(width: 28, height: 28)
                .background(groupColor(group).opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.body)
                if let address = place.address {
                    Text(address).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                onAdd(
                    MapPlace(
                        name: place.name,
                        address: place.address,
                        kakaoPlaceId: place.kakaoPlaceId,
                        location: GeoPoint(lat: place.lat, lng: place.lng),
                        pinColor: group.colorHex
                    )
                )
                added.insert(place.id)
            } label: {
                Image(systemName: added.contains(place.id) ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(added.contains(place.id) ? Color.secondary : groupColor(group))
            .disabled(added.contains(place.id))
            .accessibilityLabel("\(place.name) 단계로 올리기")
        }
        .padding(.vertical, 2)
    }

    private func reload() {
        places = store.all(in: group.id)
        onChanged()
    }

    private func remove(_ place: SavedPlace) {
        store.remove(id: place.id)
        reload()
    }
}

private struct SavedPlaceMoveSheet: View {
    let place: SavedPlace
    let groups: [SavedPlaceGroup]
    let onMove: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(groups.filter { $0.id != place.groupID }) { group in
                Button {
                    onMove(group.id)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        groupMark(group, size: 34)
                        Text(group.name).foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("다른 폴더로 이동")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct GroupEditorTarget: Identifiable {
    let id = UUID()
    let group: SavedPlaceGroup?
}

private struct SavedPlaceGroupEditor: View {
    let group: SavedPlaceGroup?
    let onSave: (SavedPlaceGroup) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var marker: SavedPlaceMarker
    @State private var colorHex: String

    private let colors = ["#E24B4A", "#E58A2B", "#2FA35B", "#2D6BE4", "#7A55C7", "#D34F8B", "#5D6470"]

    init(group: SavedPlaceGroup?, onSave: @escaping (SavedPlaceGroup) -> Void) {
        self.group = group
        self.onSave = onSave
        _name = State(initialValue: group?.name ?? "")
        _marker = State(initialValue: group?.marker ?? .star)
        _colorHex = State(initialValue: group?.colorHex ?? "#E24B4A")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("폴더 이름") {
                    TextField("예: 가고 싶은 카페", text: $name)
                        .accessibilityIdentifier("saved.groupEditor.name")
                }

                Section("마크") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
                        ForEach(SavedPlaceMarker.allCases) { choice in
                            Button { marker = choice } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: choice.symbolName)
                                        .font(.title3)
                                        .frame(width: 38, height: 38)
                                        .background(
                                            marker == choice ? groupColor(colorHex).opacity(0.18) : Color.clear,
                                            in: Circle()
                                        )
                                    Text(choice.title).font(.caption2)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(marker == choice ? groupColor(colorHex) : Color.secondary)
                            .accessibilityIdentifier("saved.marker.\(choice.rawValue)")
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("색상") {
                    HStack(spacing: 13) {
                        ForEach(colors, id: \.self) { color in
                            Button { colorHex = color } label: {
                                Circle()
                                    .fill(groupColor(color))
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if colorHex == color {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("폴더 색상")
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("미리보기") {
                    HStack(spacing: 12) {
                        groupMark(preview, size: 42)
                        Text(preview.name.isEmpty ? "폴더 이름" : preview.name)
                    }
                }
            }
            .navigationTitle(group == nil ? "새 폴더" : "폴더 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("saved.groupEditor.save")
                }
            }
        }
    }

    private var preview: SavedPlaceGroup {
        SavedPlaceGroup(
            id: group?.id ?? "preview",
            name: name,
            marker: marker,
            colorHex: colorHex,
            createdAt: group?.createdAt ?? ""
        )
    }

    private func save() {
        onSave(
            SavedPlaceGroup(
                id: group?.id ?? UUID().uuidString,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                marker: marker,
                colorHex: colorHex,
                createdAt: group?.createdAt ?? ISO8601DateFormatter().string(from: Date())
            )
        )
        dismiss()
    }
}

private func groupMark(_ group: SavedPlaceGroup, size: CGFloat) -> some View {
    Image(systemName: group.marker.symbolName)
        .font(.system(size: size * 0.42, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(groupColor(group), in: RoundedRectangle(cornerRadius: size * 0.28))
}

private func groupColor(_ group: SavedPlaceGroup) -> Color {
    groupColor(group.colorHex)
}

private func groupColor(_ hex: String) -> Color {
    Color(uiColor: UIColor(hex: hex) ?? .systemBlue)
}
