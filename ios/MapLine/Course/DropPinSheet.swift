import SwiftUI

/// 지도를 꾹 눌렀을 때 나오는 선택지.
///
/// 먼저 그 자리 주변의 장소를 찾아 보여 준다. 장소를 고른 뒤에는 새 단계로 만들지,
/// 이미 있는 단계의 후보로 담을지 고른다. 첫 장소에는 선택지가 하나뿐이므로 곧바로
/// 1단계로 담는다.
struct DropPinSheet: View {
    let coordinate: GeoPoint
    let stops: [Stop]
    /// `stopID`가 nil이면 새 단계, 값이 있으면 그 단계의 후보로 담는다.
    let onPick: (_ stopID: String?, _ place: MapPlace) -> Void
    /// 장소가 아니라 그 자리에 할 말을 남긴다.
    let onWriteMemo: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var places: [PlaceCandidate] = []
    @State private var address: String?
    @State private var phase: Phase = .loading
    @State private var askingMemo = false
    @State private var searchingPlace = false
    @State private var memo = ""
    @State private var pickedPlace: MapPlace?

    private enum Phase: Equatable {
        case loading, ready, failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let pickedPlace {
                    targetPicker(for: pickedPlace)
                } else {
                    placePicker
                }
            }
            .navigationTitle(pickedPlace == nil ? "여기에 무엇을 담을까요" : "어디에 담을까요")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if pickedPlace == nil {
                        Button("취소") { dismiss() }
                    } else {
                        Button("뒤로") { pickedPlace = nil }
                    }
                }
            }
            .alert("메모 남기기", isPresented: $askingMemo) {
                TextField("여기에 대해 할 말", text: $memo)
                Button("취소", role: .cancel) { memo = "" }
                Button("남기기") {
                    let text = memo.trimmingCharacters(in: .whitespacesAndNewlines)
                    memo = ""
                    guard !text.isEmpty else { return }
                    onWriteMemo(text)
                    dismiss()
                }
            }
            .sheet(isPresented: $searchingPlace) {
                PlaceSearchSheet(
                    title: "이 근처 장소 검색",
                    near: PlaceCandidate.Coordinate(lat: coordinate.lat, lng: coordinate.lng)
                ) { candidate in
                    pick(candidate)
                }
            }
        }
        .task { await load() }
    }

    private var placePicker: some View {
        List {
            if let address {
                Section {
                    Text(address).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section {
                switch phase {
                case .loading:
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("주변을 찾는 중…").foregroundStyle(.secondary)
                    }
                case .ready where places.isEmpty:
                    Text("주변에 등록된 장소가 없습니다.").foregroundStyle(.secondary)
                case .ready:
                    ForEach(places) { place in
                        Button { pick(place) } label: { row(place) }
                            .buttonStyle(.plain)
                    }
                case .failed(let message):
                    // 주변 검색에 실패해도 좌표를 직접 찍을 수 있어야 한다.
                    Text(message).font(.footnote).foregroundStyle(.orange)
                }
            } header: {
                Text("이 근처")
            }
        }
        // 목록이 길어도 검색·직접 찍기·메모는 항상 손이 닿는 곳에 둔다.
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                bottomAction("검색", symbol: "magnifyingglass") { searchingPlace = true }
                    .accessibilityIdentifier("droppin.search")

                bottomAction("핀 찍기", symbol: "mappin.and.ellipse") {
                    chooseTarget(
                        MapPlace(
                            name: address ?? "직접 찍은 지점",
                            address: address,
                            location: coordinate
                        )
                    )
                }
                .accessibilityIdentifier("droppin.here")

                bottomAction("메모", symbol: "text.bubble") { askingMemo = true }
                    .accessibilityIdentifier("droppin.memo")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    /// 첫 핀은 바로 1단계가 된다. 이미 단계가 있을 때만 목적지를 묻는다.
    private func chooseTarget(_ place: MapPlace) {
        if stops.isEmpty {
            onPick(nil, place)
            dismiss()
        } else {
            pickedPlace = place
        }
    }

    private func targetPicker(for place: MapPlace) -> some View {
        List {
            Section("고른 장소") {
                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name).font(.body.weight(.medium))
                    if let address = place.address, address != place.name {
                        Text(address).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }

            Section("담을 위치") {
                Button {
                    commit(place, to: nil)
                } label: {
                    targetRow(
                        title: "새 단계 만들기",
                        subtitle: "\(stops.count + 1)단계로 추가합니다",
                        symbol: "plus.circle.fill"
                    )
                }
                .accessibilityIdentifier("droppin.target.new")

                ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                    Button {
                        commit(place, to: stop.id)
                    } label: {
                        targetRow(
                            title: "\(index + 1)단계에 후보로 추가",
                            subtitle: stopSummary(stop),
                            symbol: "square.stack.3d.up.fill"
                        )
                    }
                    .accessibilityIdentifier("droppin.target.\(index)")
                }
            }
        }
        .accessibilityIdentifier("droppin.targetPicker")
    }

    private func targetRow(title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func stopSummary(_ stop: Stop) -> String {
        let names = stop.candidates.prefix(2).map(\.name).joined(separator: ", ")
        let more = stop.candidates.count > 2 ? " 외 \(stop.candidates.count - 2)곳" : ""
        return names + more
    }

    private func commit(_ place: MapPlace, to stopID: String?) {
        onPick(stopID, place)
        dismiss()
    }

    private func bottomAction(
        _ title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func row(_ place: PlaceCandidate) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.body)
                if let address = place.displayAddress {
                    Text(address).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let distance = place.distanceM {
                Text(formatDistance(distance))
                    .font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
            }
        }
    }

    private func pick(_ candidate: PlaceCandidate) {
        chooseTarget(
            MapPlace(
                name: candidate.name,
                address: candidate.displayAddress,
                kakaoPlaceId: candidate.kakaoPlaceId,
                location: GeoPoint(lat: candidate.location.lat, lng: candidate.location.lng)
            )
        )
    }

    private func load() async {
        do {
            let found = try await NearbyLookup.find(lat: coordinate.lat, lng: coordinate.lng)
            address = found.address
            places = found.places
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

/// 거리 표기. 웹 `formatDistance`와 같은 규칙이다.
func formatDistance(_ meters: Double) -> String {
    guard meters.isFinite, meters >= 0 else { return "" }
    if meters < 1000 { return "\(Int(meters.rounded()))m" }
    return String(format: "%.1fkm", meters / 1000)
}
