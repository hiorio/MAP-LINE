import SwiftUI
import UIKit

/// 개인 장소 보관함. 공유로 받은 곳뿐 아니라 직접 찾은 장소도 폴더별로 모아 둔다.
struct SavedPlacesView: View {
    let stops: [Stop]
    let onOpenRoutes: () -> Void
    let onAdd: (_ stopID: String?, _ places: [MapPlace]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var groups: [SavedPlaceGroup] = []
    @State private var places: [SavedPlace] = []
    @State private var editor: GroupEditorTarget?
    @State private var deletingGroup: SavedPlaceGroup?
    @State private var query = ""
    @State private var editMode: EditMode = .inactive
    @State private var storageError: String?

    private let placeStore = SavedPlaceStore(storage: AppGroupPlaceStorage())
    private let groupStore = SavedPlaceGroupStore(storage: AppGroupSavedPlaceGroupStorage())

    var body: some View {
        NavigationStack {
            List {
                if normalizedQuery.isEmpty {
                    Section("동선") {
                        Button(action: onOpenRoutes) {
                            HStack(spacing: 12) {
                                Image(systemName: "map.fill")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.tint)
                                    .frame(width: 38, height: 38)
                                    .background(Color.accentColor.opacity(0.14), in: Circle())
                                Text("내 동선")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("saved.myRoutes")
                    }

                    Section("내 폴더") {
                        ForEach(customGroups) { group in
                            groupLink(group)
                        }
                        .onMove(perform: moveGroups)

                        // 예전 버전에서 폴더를 고르지 않고 담은 장소가 실제로 남아 있을
                        // 때만 복구용 폴더를 보여 준다. 빈 `받은 장소` 항목은 만들지 않는다.
                        if let uncategorizedGroup {
                            groupLink(uncategorizedGroup)
                        }

                        if customGroups.isEmpty && uncategorizedGroup == nil {
                            Text("폴더가 없습니다")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section("전체 검색 결과 \(searchResults.count)곳") {
                        if searchResults.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text("찾은 장소가 없습니다").font(.headline)
                                Text("장소명·주소·폴더 이름으로 다시 찾아보세요.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        } else {
                            ForEach(searchResults) { place in
                                if let group = group(for: place) {
                                    NavigationLink {
                                        SavedPlaceGroupView(
                                            group: group,
                                            groups: groups,
                                            stops: stops,
                                            onAdd: onAdd,
                                            onChanged: reload
                                        )
                                    } label: {
                                        searchResultRow(place, group: group)
                                    }
                                    .accessibilityIdentifier("saved.searchResult")
                                }
                            }
                        }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .searchable(text: $query, prompt: "장소·주소·폴더 검색")
            .navigationTitle("보관함")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if normalizedQuery.isEmpty {
                        Button(editMode.isEditing ? "완료" : "정렬") {
                            withAnimation {
                                editMode = editMode.isEditing ? .inactive : .active
                            }
                        }
                        .disabled(customGroups.count < 2)
                        .accessibilityIdentifier("saved.sortGroups")
                    }
                    Button { editor = GroupEditorTarget(group: nil) } label: {
                        Label("새 폴더", systemImage: "folder.badge.plus")
                    }
                    .accessibilityIdentifier("saved.addGroup")
                }
            }
        }
        .sheet(item: $editor) { target in
            SavedPlaceGroupEditor(group: target.group) { group in
                do {
                    if target.group == nil {
                        _ = try groupStore.add(group)
                    } else {
                        try groupStore.update(group)
                    }
                    reload()
                } catch {
                    storageError = error.localizedDescription
                }
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
            Text("‘\(group.name)’의 장소는 삭제되지 않고 ‘미분류’로 이동합니다.")
        }
        .alert(
            "보관함을 저장하지 못했습니다",
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

    private func groupRow(_ group: SavedPlaceGroup) -> some View {
        HStack(spacing: 12) {
            groupMark(group, size: 38)
            Text(group.name).font(.body.weight(.medium))
            Spacer()
            Text("\(places.filter { $0.groupID == group.id }.count)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var customGroups: [SavedPlaceGroup] {
        groups.filter { $0.id != SavedPlaceGroup.inboxID }
    }

    private var uncategorizedGroup: SavedPlaceGroup? {
        guard places.contains(where: { $0.groupID == SavedPlaceGroup.inboxID }) else { return nil }
        return groups.first { $0.id == SavedPlaceGroup.inboxID }
    }

    private var searchResults: [SavedPlace] {
        let text = normalizedQuery
        guard !text.isEmpty else { return [] }
        return places.filter { place in
            place.name.localizedCaseInsensitiveContains(text)
                || (place.address?.localizedCaseInsensitiveContains(text) ?? false)
                || (group(for: place)?.name.localizedCaseInsensitiveContains(text) ?? false)
        }
    }

    private func group(for place: SavedPlace) -> SavedPlaceGroup? {
        groups.first { $0.id == place.groupID }
            ?? groups.first { $0.id == SavedPlaceGroup.inboxID }
    }

    private func groupLink(_ group: SavedPlaceGroup) -> some View {
        NavigationLink {
            SavedPlaceGroupView(
                group: group,
                groups: groups,
                stops: stops,
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

    private func searchResultRow(_ place: SavedPlace, group: SavedPlaceGroup) -> some View {
        HStack(spacing: 11) {
            groupMark(group, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                Text([place.address, Optional(group.name)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private func moveGroups(from source: IndexSet, to destination: Int) {
        var reordered = customGroups
        reordered.move(fromOffsets: source, toOffset: destination)
        do {
            try groupStore.reorder(customGroupIDs: reordered.map(\.id))
            reload()
        } catch {
            storageError = error.localizedDescription
        }
    }

    private func reload() {
        do {
            groups = try groupStore.all()
            places = try placeStore.all()
        } catch {
            storageError = error.localizedDescription
        }
    }

    private func delete(_ group: SavedPlaceGroup) {
        do {
            try placeStore.moveAll(from: group.id, to: SavedPlaceGroup.inboxID)
            try groupStore.remove(id: group.id)
            deletingGroup = nil
            reload()
        } catch {
            storageError = error.localizedDescription
        }
    }
}

/// 폴더 하나의 장소 목록. 여기서 직접 장소를 검색해 담고 다른 폴더로 옮긴다.
private struct SavedPlaceGroupView: View {
    let group: SavedPlaceGroup
    let groups: [SavedPlaceGroup]
    let stops: [Stop]
    let onAdd: (_ stopID: String?, _ places: [MapPlace]) -> Void
    let onChanged: () -> Void

    @State private var places: [SavedPlace] = []
    @State private var added: Set<String> = []
    @State private var searching = false
    @State private var moveRequest: MoveRequest?
    @State private var selectingForCourse = false
    @State private var courseSelection: Set<String> = []
    @State private var pendingCoursePlaces: CoursePlaces?
    @State private var storageError: String?

    private struct CoursePlaces: Identifiable {
        let id = UUID()
        let places: [SavedPlace]
    }

    private struct MoveRequest: Identifiable {
        let id = UUID()
        let places: [SavedPlace]
    }

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
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard selectingForCourse else { return }
                                toggleCourseSelection(place)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button { moveRequest = MoveRequest(places: [place]) } label: {
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
                                Button { moveRequest = MoveRequest(places: [place]) } label: {
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
            ToolbarItem(placement: .secondaryAction) {
                Button(selectingForCourse ? "완료" : "선택") {
                    withAnimation {
                        selectingForCourse.toggle()
                        if !selectingForCourse { courseSelection = [] }
                    }
                }
                .disabled(places.isEmpty)
                .accessibilityIdentifier("saved.group.select")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { searching = true } label: {
                    Label("장소 추가", systemImage: "plus")
                }
                .accessibilityIdentifier("saved.group.addPlace")
            }
        }
        .sheet(isPresented: $searching) {
            PlaceSearchSheet(title: "\(group.name)에 장소 추가", near: nil) { candidate in
                do {
                    _ = try store.addOrMove(
                        candidate.asSavedPlace(groupID: group.id),
                        to: group.id
                    )
                    reload()
                } catch {
                    storageError = error.localizedDescription
                }
            }
        }
        .sheet(item: $moveRequest) { request in
            SavedPlaceMoveSheet(
                placeCount: request.places.count,
                sourceGroupID: group.id,
                groups: groups.filter { $0.id != SavedPlaceGroup.inboxID }
            ) { targetID in
                do {
                    try store.move(ids: Set(request.places.map(\.id)), to: targetID)
                    courseSelection = []
                    selectingForCourse = false
                    reload()
                } catch {
                    storageError = error.localizedDescription
                }
            }
        }
        .sheet(item: $pendingCoursePlaces) { picked in
            CourseTargetSheet(
                places: picked.places.map(mapPlace),
                stops: stops
            ) { stopID in
                let mapped = picked.places.map(mapPlace)
                onAdd(stopID, mapped)
                added.formUnion(picked.places.map(\.id))
                courseSelection = []
                selectingForCourse = false
            }
            .presentationDetents([.medium, .large])
        }
        .safeAreaInset(edge: .bottom) {
            if selectingForCourse {
                HStack(spacing: 10) {
                    Button {
                        let picked = places.filter { courseSelection.contains($0.id) }
                        guard !picked.isEmpty else { return }
                        moveRequest = MoveRequest(places: picked)
                    } label: {
                        Label("이동", systemImage: "folder")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.bordered)
                    .disabled(courseSelection.isEmpty)
                    .accessibilityIdentifier("saved.group.moveSelected")

                    Button {
                        let picked = places.filter { courseSelection.contains($0.id) }
                        guard !picked.isEmpty else { return }
                        pendingCoursePlaces = CoursePlaces(places: picked)
                    } label: {
                        Text("\(courseSelection.count)곳 동선에 담기")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(courseSelection.isEmpty)
                    .accessibilityIdentifier("saved.group.addSelected")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
        }
        .alert(
            "보관함을 저장하지 못했습니다",
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
            if selectingForCourse {
                Image(systemName: courseSelection.contains(place.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(courseSelection.contains(place.id) ? Color.accentColor : Color.secondary)
                    .accessibilityLabel("\(place.name) 선택")
            } else {
                Button {
                    pendingCoursePlaces = CoursePlaces(places: [place])
                } label: {
                    Image(systemName: added.contains(place.id) ? "checkmark.circle.fill" : "plus.circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(added.contains(place.id) ? Color.secondary : groupColor(group))
                .disabled(added.contains(place.id))
                .accessibilityLabel("\(place.name) 동선에 담기")
            }
        }
        .padding(.vertical, 2)
    }

    private func reload() {
        do {
            places = try store.all(in: group.id)
            onChanged()
        } catch {
            storageError = error.localizedDescription
        }
    }

    private func remove(_ place: SavedPlace) {
        do {
            try store.remove(id: place.id)
            reload()
        } catch {
            storageError = error.localizedDescription
        }
    }

    private func toggleCourseSelection(_ place: SavedPlace) {
        if courseSelection.contains(place.id) {
            courseSelection.remove(place.id)
        } else {
            courseSelection.insert(place.id)
        }
    }

    private func mapPlace(_ place: SavedPlace) -> MapPlace {
        place.mapPlace(pinColor: group.colorHex)
    }
}

private struct SavedPlaceMoveSheet: View {
    let placeCount: Int
    let sourceGroupID: String
    let groups: [SavedPlaceGroup]
    let onMove: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(groups.filter { $0.id != sourceGroupID }) { group in
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
            .navigationTitle(placeCount == 1 ? "다른 폴더로 이동" : "\(placeCount)곳 이동")
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

struct SavedPlaceGroupEditor: View {
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
