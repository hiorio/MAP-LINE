import SwiftUI

/// 동선에 넣을 장소를 여러 곳 골라 한 번에 담는다.
///
/// 웹 `PlacePanel`과 같은 흐름이다. 검색 결과를 누를 때마다 바로 닫지 않고 체크해 두며,
/// 새 단계로 묶을지 이미 있는 단계의 후보로 넣을지도 이 화면 안에서 바꿀 수 있다.
/// 중간지점과 핀 상세는 한 곳만 고르는 일이므로 기존 `PlaceSearchSheet`를 그대로 쓴다.
struct CoursePlacePickerSheet: View {
    let stops: [Stop]
    /// 현재 지도 중심. 웹과 같이 같은 이름 중 가까운 결과를 먼저 받는다.
    let near: PlaceCandidate.Coordinate?
    let onCommit: (_ targetStopID: String?, _ candidates: [PlaceCandidate]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var targetStopID: String?
    @State private var query = ""
    @State private var results: [PlaceCandidate] = []
    @State private var selected: [PlaceCandidate] = []
    @State private var phase: Phase = .idle
    @State private var searchTask: Task<Void, Never>?

    private enum Phase: Equatable {
        case idle, searching, done, failed(String)
    }

    init(
        stops: [Stop],
        initialTargetStopID: String? = nil,
        near: PlaceCandidate.Coordinate? = nil,
        onCommit: @escaping (_ targetStopID: String?, _ candidates: [PlaceCandidate]) -> Void
    ) {
        self.stops = stops
        self.near = near
        self.onCommit = onCommit
        _targetStopID = State(initialValue: initialTargetStopID)
    }

    private var targetIndex: Int? {
        guard let targetStopID else { return nil }
        return stops.firstIndex { $0.id == targetStopID }
    }

    private var targetStop: Stop? {
        guard let targetIndex, stops.indices.contains(targetIndex) else { return nil }
        return stops[targetIndex]
    }

    private var commitCandidates: [PlaceCandidate] {
        selected.filter { !isAlreadyAdded($0) }
    }

    private var commitLabel: String {
        let count = commitCandidates.count
        if let targetIndex { return "\(targetIndex + 1)단계 후보로 \(count)곳 추가" }
        return "새 단계로 \(count)곳 담기"
    }

    var body: some View {
        NavigationStack {
            List {
                targetSection

                if let targetStop {
                    Section("현재 후보 \(targetStop.candidates.count)곳") {
                        ForEach(targetStop.candidates) { place in
                            Label(place.name, systemImage: "mappin.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                statusSection
                resultSection
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "장소나 주소")
            .onChange(of: query) { _ in scheduleSearch() }
            .onDisappear { searchTask?.cancel() }
            .navigationTitle("장소 담기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    let candidates = commitCandidates
                    guard !candidates.isEmpty else { return }
                    onCommit(targetStopID, candidates)
                    dismiss()
                } label: {
                    Text(commitLabel)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.borderedProminent)
                .disabled(commitCandidates.isEmpty)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial)
                .accessibilityIdentifier("coursePicker.commit")
            }
        }
    }

    private var targetSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    targetButton(title: "새 단계", stopID: nil, identifier: "coursePicker.target.new")
                    ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                        targetButton(
                            title: "\(index + 1)단계",
                            stopID: stop.id,
                            identifier: "coursePicker.target.\(index)"
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text(targetIndex.map { "\($0 + 1)단계의 후보로 담습니다" } ?? "고른 장소들을 새 단계 하나로 담습니다")
        }
    }

    private func targetButton(title: String, stopID: String?, identifier: String) -> some View {
        let chosen = targetStopID == stopID
        return Button {
            targetStopID = stopID
        } label: {
            HStack(spacing: 5) {
                if chosen { Image(systemName: "checkmark") }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(chosen ? Color.accentColor : Color.secondary.opacity(0.1), in: Capsule())
            .foregroundStyle(chosen ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var statusSection: some View {
        switch phase {
        case .idle:
            Section {
                Text("검색 결과에서 여러 곳을 체크한 뒤 아래 버튼으로 한 번에 담으세요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .searching:
            Section { HStack { ProgressView(); Text("찾는 중…").foregroundStyle(.secondary) } }
        case .failed(let message):
            Section { Text(message).foregroundStyle(.secondary) }
        case .done where results.isEmpty:
            Section { Text("결과가 없습니다.").foregroundStyle(.secondary) }
        case .done:
            EmptyView()
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if !results.isEmpty {
            Section("검색 결과") {
                ForEach(results) { place in
                    let added = isAlreadyAdded(place)
                    let checked = isSelected(place)
                    Button {
                        guard !added else { return }
                        toggle(place)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: added ? "checkmark.circle" : checked ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(added ? Color.secondary : checked ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(place.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if added {
                                        Text("추가됨")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if let address = place.displayAddress {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(added ? "추가됨" : checked ? "선택됨" : "선택 안 됨")
                }
            }
        }
    }

    private func isSelected(_ candidate: PlaceCandidate) -> Bool {
        selected.contains { $0.id == candidate.id }
    }

    private func toggle(_ candidate: PlaceCandidate) {
        if isSelected(candidate) {
            selected.removeAll { $0.id == candidate.id }
        } else {
            selected.append(candidate)
        }
    }

    private func isAlreadyAdded(_ candidate: PlaceCandidate) -> Bool {
        guard let targetStop else { return false }
        return targetStop.candidates.contains { place in
            if let candidateID = candidate.kakaoPlaceId, let placeID = place.kakaoPlaceId {
                return candidateID == placeID
            }
            return candidate.name == place.name
                && abs(candidate.location.lat - place.location.lat) < 0.000_000_1
                && abs(candidate.location.lng - place.location.lng) < 0.000_000_1
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            results = []
            phase = .idle
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }

            phase = .searching
            do {
                let found = try await PlaceLookup.search(text, near: near)
                guard !Task.isCancelled else { return }
                results = found
                phase = .done
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                phase = .failed(error.localizedDescription)
            }
        }
    }
}

extension PlaceCandidate {
    /// 검색 결과를 저장 가능한 동선 장소로 바꾼다.
    var mapPlace: MapPlace {
        MapPlace(
            name: name,
            address: displayAddress,
            kakaoPlaceId: kakaoPlaceId,
            location: GeoPoint(lat: location.lat, lng: location.lng)
        )
    }
}
