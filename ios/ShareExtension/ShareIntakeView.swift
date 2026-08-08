import SwiftUI

/// 공유로 들어온 장소를 고르는 화면.
///
/// 후보를 자동으로 확정하지 않는다. 프랜차이즈는 같은 이름의 지점이 여럿이라, 한 곳을
/// 말없이 담으면 엉뚱한 지점이 들어간다. 웹의 붙여넣기 흐름도 같은 이유로 항상 고르게 한다.
struct ShareIntakeView: View {
    let rawText: String
    /// 공유 앱이 익스텐션에 실제로 넘긴 텍스트·URL 조각 수. 사용자가 보낸 개수와
    /// 다르면 파싱 전 단계에서 이미 누락됐다는 사실을 숨기지 않는다.
    let sourcePieceCount: Int
    let onDone: () -> Void
    let onCancel: () -> Void

    @State private var phase: Phase = .loading
    @State private var savedMessage: String?
    @State private var selected: [String: String] = [:]
    @State private var showRaw = false
    @State private var destinationGroups: [SavedPlaceGroup] = []
    @State private var destinationGroupID: String?
    @State private var showingFolderCreator = false
    @State private var storageError: String?

    /// `State`라고 이름 짓지 않는다. SwiftUI의 `@State`를 가려서 프로퍼티 래퍼가
    /// 통째로 망가진다. 오류 메시지("enum 'State' cannot be used as an attribute")가
    /// 원인을 바로 알려 주지 않아 헤매기 쉽다.
    private enum Phase {
        case loading
        case ready([ShareIntake.Group])
        case failed(String)
    }

    private let store = SavedPlaceStore(storage: AppGroupPlaceStorage())
    private let groupStore = SavedPlaceGroupStore(storage: AppGroupSavedPlaceGroupStorage())

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    ProgressView("장소를 찾는 중…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .ready(let groups):
                    List {
                        intakeSummary(groups)
                        if let savedMessage {
                            Section {
                                Label(savedMessage, systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        Section("담을 폴더") {
                            if destinationGroups.isEmpty {
                                Label("폴더를 먼저 만들어 주세요", systemImage: "folder.badge.plus")
                                    .foregroundStyle(.secondary)
                            } else {
                                Picker("폴더 선택", selection: $destinationGroupID) {
                                    Text("선택하세요").tag(nil as String?)
                                    ForEach(destinationGroups) { group in
                                        Label(group.name, systemImage: group.marker.symbolName)
                                            .tag(Optional(group.id))
                                    }
                                }
                                .pickerStyle(.menu)
                                .accessibilityIdentifier("share.destinationFolder")
                            }

                            Button { showingFolderCreator = true } label: {
                                Label("새 폴더 만들기", systemImage: "folder.badge.plus")
                            }
                            .accessibilityIdentifier("share.addFolder")
                        }
                        ForEach(groups) { group in
                            candidateSection(group)
                        }
                        rawSection
                    }

                case .failed(let message):
                    List {
                        Section("받은 내용") {
                            Text("공유 앱에서 원문 조각 \(sourcePieceCount)개를 받았습니다.")
                        }
                        Section {
                            Text(message).foregroundStyle(.secondary)
                        }
                        rawSection
                    }
                }
            }
            .navigationTitle("보관함에 담기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기", action: savedMessage == nil ? onCancel : onDone)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if case .ready(let groups) = phase, savedMessage == nil {
                    Button {
                        save(groups)
                    } label: {
                        Text("선택한 \(selected.count)곳 보관함에 담기")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty || destinationGroupID == nil)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                    .accessibilityIdentifier("share.saveSelected")
                }
            }
        }
        .sheet(isPresented: $showingFolderCreator) {
            ShareFolderCreator { group in
                do {
                    guard try groupStore.add(group) else {
                        storageError = "같은 이름의 폴더가 이미 있습니다."
                        return
                    }
                    try reloadDestinationGroups(selecting: group.id)
                } catch {
                    storageError = error.localizedDescription
                }
            }
        }
        .alert(
            "보관함에 담지 못했습니다",
            isPresented: Binding(
                get: { storageError != nil },
                set: { if !$0 { storageError = nil } }
            )
        ) {
            Button("확인", role: .cancel) { storageError = nil }
        } message: {
            Text(storageError ?? "")
        }
        .task {
            do {
                try reloadDestinationGroups()
            } catch {
                storageError = error.localizedDescription
            }
            await lookUp()
        }
    }

    private func intakeSummary(_ groups: [ShareIntake.Group]) -> some View {
        let found = groups.filter { !$0.places.isEmpty }.count
        let missing = groups.count - found
        return Section("받은 내용") {
            Text("원문 조각 \(sourcePieceCount)개 · 장소로 구분 \(groups.count)건")
            Label(
                missing == 0 ? "후보 확인 \(found)건" : "후보 확인 \(found)건 · 찾지 못함 \(missing)건",
                systemImage: missing == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(missing == 0 ? Color.green : Color.orange)
        }
    }

    private func candidateSection(_ group: ShareIntake.Group) -> some View {
        Section {
            if group.places.isEmpty {
                Text("이 주소의 장소를 찾지 못했습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(group.places) { candidate in
                    Button {
                        if selected[group.id] == candidate.id {
                            selected.removeValue(forKey: group.id)
                        } else {
                            selected[group.id] = candidate.id
                        }
                    } label: {
                        HStack {
                            row(candidate)
                            Image(systemName: selected[group.id] == candidate.id
                                  ? "checkmark.circle.fill"
                                  : "circle")
                                .foregroundStyle(selected[group.id] == candidate.id ? Color.accentColor : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text(group.parsed.name)
        } footer: {
            if let address = group.parsed.address { Text(address) }
        }
    }

    private func row(_ candidate: ShareIntake.Candidate) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(candidate.name).font(.body)
            if let address = candidate.roadAddress ?? candidate.address {
                Text(address).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// 받은 원문을 접어 둔다.
    ///
    /// 어느 앱이 무엇을 넘기는지는 실기기에서만 알 수 있다. 실패했을 때 무엇이 왔는지
    /// 볼 수 없으면 고칠 수가 없다. 평소에는 접혀 있어 방해되지 않는다.
    private var rawSection: some View {
        Section {
            DisclosureGroup("공유된 원문 보기", isExpanded: $showRaw) {
                Text(rawText.isEmpty ? "(빈 값)" : rawText)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
    }

    private func lookUp() async {
        guard !rawText.isEmpty else {
            phase = .failed("공유된 내용이 비어 있습니다.")
            return
        }
        do {
            let groups = try await ShareIntake.lookUp(text: rawText, baseURL: AppConfig.apiBaseURL)
            selected = Dictionary(uniqueKeysWithValues: groups.compactMap { group in
                group.places.first.map { (group.id, $0.id) }
            })
            phase = .ready(groups)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func save(_ groups: [ShareIntake.Group]) {
        guard let destinationGroupID else {
            storageError = "장소를 담을 폴더를 선택해 주세요."
            return
        }
        let candidates: [ShareIntake.Candidate] = groups.compactMap { group -> ShareIntake.Candidate? in
            guard let selectedID = selected[group.id] else { return nil }
            return group.places.first { $0.id == selectedID }
        }
        do {
            let addedCount = try store.add(
                candidates.map { $0.asSavedPlace(groupID: destinationGroupID) }
            )
            let folderName = destinationGroups.first { $0.id == destinationGroupID }?.name ?? "보관함"
            savedMessage = addedCount > 0
                ? "\(addedCount)곳을 ‘\(folderName)’에 담았습니다"
                : "선택한 장소가 이미 보관함에 있습니다"
            // 담자마자 닫으면 담긴 게 맞는지 확인할 틈이 없다. 잠깐 보여 주고 닫는다.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: onDone)
        } catch {
            // 실패를 성공으로 표시하거나 자동으로 닫지 않는다. 원문과 선택을 유지한 채
            // 저장 공간을 확인하고 다시 누를 수 있어야 한다.
            storageError = error.localizedDescription
        }
    }

    private func reloadDestinationGroups(selecting preferredID: String? = nil) throws {
        // 예전 버전의 고정 수신함은 새 공유 목적지로 쓰지 않는다. 사용자가 만든 폴더를
        // 직접 고르게 해 공유 순간부터 분류가 끝나도록 한다.
        let loaded = try groupStore.all().filter { $0.id != SavedPlaceGroup.inboxID }
        destinationGroups = loaded
        if let preferredID, loaded.contains(where: { $0.id == preferredID }) {
            destinationGroupID = preferredID
        } else if let currentID = destinationGroupID,
                  loaded.contains(where: { $0.id == currentID }) {
            destinationGroupID = currentID
        } else {
            destinationGroupID = nil
        }
    }
}

/// 앱을 열지 않고도 공유 화면에서 목적 폴더를 바로 만들 수 있게 하는 간단한 편집기.
private struct ShareFolderCreator: View {
    let onSave: (SavedPlaceGroup) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var marker: SavedPlaceMarker = .star
    @State private var colorHex = "#E24B4A"

    private let colors: [(hex: String, color: Color)] = [
        ("#E24B4A", Color(red: 0.89, green: 0.29, blue: 0.29)),
        ("#E58A2B", Color(red: 0.90, green: 0.54, blue: 0.17)),
        ("#2FA35B", Color(red: 0.18, green: 0.64, blue: 0.36)),
        ("#2D6BE4", Color(red: 0.18, green: 0.42, blue: 0.89)),
        ("#7A55C7", Color(red: 0.48, green: 0.33, blue: 0.78)),
        ("#D34F8B", Color(red: 0.83, green: 0.31, blue: 0.55)),
        ("#5D6470", Color(red: 0.36, green: 0.39, blue: 0.44)),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("폴더 이름") {
                    TextField("예: 가고 싶은 카페", text: $name)
                        .accessibilityIdentifier("share.folder.name")
                }

                Section("마크") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
                        ForEach(SavedPlaceMarker.allCases) { choice in
                            Button { marker = choice } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: choice.symbolName)
                                        .font(.title3)
                                        .frame(width: 36, height: 36)
                                        .background(
                                            marker == choice ? selectedColor.opacity(0.18) : Color.clear,
                                            in: Circle()
                                        )
                                    Text(choice.title).font(.caption2)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(marker == choice ? selectedColor : Color.secondary)
                        }
                    }
                    .padding(.vertical, 5)
                }

                Section("색상") {
                    HStack(spacing: 13) {
                        ForEach(colors.indices, id: \.self) { index in
                            let option = colors[index]
                            Button { colorHex = option.hex } label: {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if colorHex == option.hex {
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
            }
            .navigationTitle("새 폴더")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        onSave(
                            SavedPlaceGroup(
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                marker: marker,
                                colorHex: colorHex
                            )
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("share.folder.save")
                }
            }
        }
    }

    private var selectedColor: Color {
        colors.first { $0.hex == colorHex }?.color ?? .accentColor
    }
}
