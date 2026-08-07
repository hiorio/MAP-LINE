import SwiftUI

/// 여러 곳에서 오는 사람들이 모이기 좋은 자리를 찾는다.
///
/// 두 화면으로 나누지 않고 한 화면에서 아래로 이어 붙인다. 사람을 넣고 → 찾고 →
/// 결과를 보는 흐름이 짧아서, 화면을 옮기면 방금 넣은 사람이 안 보여 확인하러
/// 되돌아가게 된다.
struct MidpointView: View {
    @State private var participants: [Midpoint.Participant] = []
    @State private var result: Midpoint.Result?
    @State private var phase: Phase = .idle
    @State private var addingNew = false
    @State private var selectedCandidateIDs: Set<String> = []
    @State private var histories: [MidpointHistoryEntry] = []
    @State private var showingHistory = false
    @State private var storageError: String?

    private let historyStore: MidpointHistoryStore

    /// 고른 후보를 지도로 넘긴다.
    ///
    /// 후보만 넘기지 않고 그릴 판을 여기서 만들어 준다. 참가자 이름과 후보 순위는
    /// 이 화면만 알고 있어서, 후보만 넘기면 지도가 "친구 2"도 "2순위"도 알 수 없다.
    let onShowOnMap: ((MidpointPlot) -> Void)?

    init(
        historyStore: MidpointHistoryStore = .live,
        onShowOnMap: ((MidpointPlot) -> Void)? = nil
    ) {
        self.historyStore = historyStore
        self.onShowOnMap = onShowOnMap
    }

    private enum Phase: Equatable {
        case idle, working, failed(String)
    }

    private var canSearch: Bool { participants.count >= 2 && phase != .working }

    var body: some View {
        List {
            peopleSection
            actionSection
            if let result { resultSection(result) }
        }
        .navigationTitle("중간지점 찾기")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    reloadHistory()
                    showingHistory = true
                } label: {
                    Label("검색 기록", systemImage: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("midpoint.history")
            }
        }
        .onAppear(perform: reloadHistory)
        .sheet(isPresented: $addingNew) {
            PlaceSearchSheet(title: "어디서 오나요?") { place in
                participants.append(
                    .init(
                        id: UUID().uuidString,
                        name: defaultName(),
                        place: .init(
                            name: place.name,
                            address: place.displayAddress,
                            lat: place.location.lat,
                            lng: place.location.lng
                        ),
                        mode: .transit
                    )
                )
                // 사람이 바뀌면 이전 결과는 그 사람들의 답이 아니다.
                result = nil
                selectedCandidateIDs = []
            }
        }
        .sheet(isPresented: $showingHistory) {
            MidpointHistoryView(
                entries: histories,
                onOpen: restore,
                onDelete: removeHistory
            )
        }
        .alert(
            "검색 기록을 저장하지 못했습니다",
            isPresented: Binding(
                get: { storageError != nil },
                set: { if !$0 { storageError = nil } }
            )
        ) {
            Button("확인", role: .cancel) { storageError = nil }
        } message: {
            Text(storageError ?? "")
        }
        .safeAreaInset(edge: .bottom) {
            if let result, let onShowOnMap {
                Button {
                    showSelected(result, on: onShowOnMap)
                } label: {
                    Label("선택한 \(selectedCandidateIDs.count)곳 지도에서 보기", systemImage: "map")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCandidateIDs.isEmpty)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.regularMaterial)
                .accessibilityIdentifier("midpoint.showOnMap")
            }
        }
    }

    // MARK: - 참가자

    private var peopleSection: some View {
        Section {
            ForEach($participants) { $person in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("이름", text: $person.name)
                            .font(.body.weight(.medium))
                        Spacer()
                        Button {
                            participants.removeAll { $0.id == person.id }
                            result = nil
                            selectedCandidateIDs = []
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }

                    Text(person.place.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("오는 방법", selection: $person.mode) {
                        ForEach(Midpoint.Participant.Mode.allCases) { mode in
                            Label(mode.label, systemImage: mode.symbol).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: person.mode) { _ in
                        result = nil
                        selectedCandidateIDs = []
                    }
                }
                .padding(.vertical, 4)
            }

            Button {
                addingNew = true
            } label: {
                Label("사람 추가", systemImage: "person.badge.plus")
            }
            .accessibilityIdentifier("midpoint.addPerson")
        } header: {
            Text("모이는 사람 \(participants.count)명")
        } footer: {
            if participants.count < 2 {
                Text("두 명 이상이어야 중간을 찾을 수 있습니다.")
            }
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                Task { await find() }
            } label: {
                HStack {
                    if phase == .working { ProgressView().padding(.trailing, 4) }
                    Text(phase == .working ? "찾는 중…" : "중간지점 찾기")
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("midpoint.find")
            .disabled(!canSearch)

            if case .failed(let message) = phase {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: - 결과

    @ViewBuilder
    private func resultSection(_ result: Midpoint.Result) -> some View {
        Section {
            ForEach(Array(result.candidates.enumerated()), id: \.element.id) { index, candidate in
                candidateRow(index: index, candidate: candidate)
            }

        } header: {
            Text("모이기 좋은 곳")
        } footer: {
            // 무엇을 기준으로 줄 세웠는지 밝힌다. 1등이 왜 1등인지 모르면 못 믿는다.
            Text("가장 오래 걸리는 사람의 시간이 짧은 순입니다.")
        }
    }

    private func candidateRow(index: Int, candidate: Midpoint.Candidate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(index + 1)").font(.caption.weight(.bold))
                    .frame(width: 20, height: 20)
                    .background(index == 0 ? Color.accentColor : Color.secondary.opacity(0.3))
                    .foregroundStyle(index == 0 ? .white : .primary)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.place.name).font(.body.weight(.medium))
                    if let address = candidate.place.address {
                        Text(address).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("최대 \(formatDuration(candidate.maxDurationS))")
                        .font(.caption.weight(.medium))
                    if let spread = candidate.spreadS {
                        Text("편차 \(formatDuration(spread))")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        // 편차를 0으로 보여 주면 완벽하게 공평한 것처럼 읽힌다.
                        Text("일부 경로 없음").font(.caption2).foregroundStyle(.orange)
                    }
                }

                Button {
                    toggle(candidate)
                } label: {
                    Image(systemName: selectedCandidateIDs.contains(candidate.id)
                          ? "checkmark.circle.fill"
                          : "circle")
                        .font(.title3)
                        .foregroundStyle(selectedCandidateIDs.contains(candidate.id) ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("midpoint.candidate.\(index)")
                .accessibilityLabel(
                    selectedCandidateIDs.contains(candidate.id)
                        ? "\(candidate.place.name) 지도 표시에서 제외"
                        : "\(candidate.place.name) 지도 표시에 추가"
                )
            }

            ForEach(candidate.legs) { leg in
                HStack(spacing: 6) {
                    Text(nameFor(leg.participantId)).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    if let seconds = leg.durationS {
                        Text(formatDuration(seconds)).font(.caption2).monospacedDigit()
                    } else {
                        Text("경로 없음").font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 동작

    private func find() async {
        phase = .working
        do {
            let found = try await Midpoint.find(participants)
            result = found
            // 기존처럼 바로 1순위를 볼 수 있게 하되, 사용자가 2·3순위도 더 고를 수 있다.
            selectedCandidateIDs = Set(found.candidates.prefix(1).map(\.id))
            phase = .idle
            do {
                try historyStore.add(participants: participants, result: found)
                reloadHistory()
            } catch {
                // 중간지점 계산 자체는 성공했다. 기록 저장 실패 때문에 결과까지 지우지 않는다.
                storageError = error.localizedDescription
            }
        } catch {
            result = nil
            selectedCandidateIDs = []
            phase = .failed(error.localizedDescription)
        }
    }

    private func toggle(_ candidate: Midpoint.Candidate) {
        if selectedCandidateIDs.contains(candidate.id) {
            selectedCandidateIDs.remove(candidate.id)
        } else {
            selectedCandidateIDs.insert(candidate.id)
        }
    }

    private func showSelected(
        _ result: Midpoint.Result,
        on onShowOnMap: (MidpointPlot) -> Void
    ) {
        let selections = result.candidates.enumerated().compactMap { index, candidate in
            selectedCandidateIDs.contains(candidate.id)
                ? (rank: index + 1, candidate: candidate)
                : nil
        }
        onShowOnMap(MidpointPlot(participants: participants, selections: selections))
    }

    private func nameFor(_ id: String) -> String {
        participants.first { $0.id == id }?.name ?? "?"
    }

    private func restore(_ entry: MidpointHistoryEntry) {
        participants = entry.participants
        result = entry.result
        selectedCandidateIDs = Set(entry.result.candidates.prefix(1).map(\.id))
        phase = .idle
        showingHistory = false
    }

    private func removeHistory(_ entry: MidpointHistoryEntry) {
        do {
            try historyStore.remove(id: entry.id)
            reloadHistory()
        } catch {
            storageError = error.localizedDescription
        }
    }

    private func reloadHistory() {
        do {
            histories = try historyStore.all()
        } catch {
            storageError = error.localizedDescription
        }
    }

    private func defaultName() -> String {
        "친구 \(participants.count + 1)"
    }
}

/// 이전 검색을 다시 여는 목록. 기록을 누르면 입력과 결과를 모두 복원한다.
private struct MidpointHistoryView: View {
    let entries: [MidpointHistoryEntry]
    let onOpen: (MidpointHistoryEntry) -> Void
    let onDelete: (MidpointHistoryEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("아직 검색 기록이 없습니다", systemImage: "clock.arrow.circlepath")
                            .font(.body.weight(.medium))
                        Text("중간지점을 찾으면 참가자와 후보 경로가 자동으로 저장됩니다.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(entries) { entry in
                        Button {
                            onOpen(entry)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.title)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(participantSummary(entry.participants))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Text(searchedAtText(entry.searchedAt))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("midpoint.history.entry")
                        .swipeActions {
                            Button("삭제", role: .destructive) { onDelete(entry) }
                        }
                    }
                }
            }
            .navigationTitle("중간지점 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private func participantSummary(_ participants: [Midpoint.Participant]) -> String {
        participants.map { "\($0.place.name)(\($0.mode.label))" }.joined(separator: " · ")
    }

    private func searchedAtText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 HH:mm"
        return formatter.string(from: date)
    }
}
