import SwiftUI

/// 지도를 꾹 눌렀을 때 나오는 선택지.
///
/// 웹에서는 누른 자리에 뜨는 작은 팝업이었다. 그 방식은 화면 밖으로 밀려 나가지
/// 않도록 위치를 계속 계산해 줘야 했고, 손가락이 메뉴를 가리는 문제도 있었다.
/// 아래에서 올라오는 시트로 옮기면 둘 다 사라진다 — 자리가 정해져 있고, 손가락에서
/// 먼 곳에 뜬다.
///
/// 먼저 그 자리 주변의 장소를 찾아 보여 준다. 화면에 보이는 가게를 눌렀는데 좌표만
/// 찍히면 이름을 직접 쳐야 하기 때문이다. 마땅한 것이 없으면 그 지점에 그대로 찍는다.
struct DropPinSheet: View {
    let coordinate: GeoPoint
    /// 고른 장소를 단계로 담는다.
    let onPick: (MapPlace) -> Void
    /// 장소가 아니라 그 자리에 할 말을 남긴다.
    let onWriteMemo: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var places: [PlaceCandidate] = []
    @State private var address: String?
    @State private var phase: Phase = .loading
    @State private var askingMemo = false
    @State private var searchingPlace = false
    @State private var memo = ""

    private enum Phase: Equatable {
        case loading, ready, failed(String)
    }

    var body: some View {
        NavigationStack {
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
                        // 주변을 못 찾아도 "여기에 그대로" 는 할 수 있어야 한다.
                        Text(message).font(.footnote).foregroundStyle(.orange)
                    }
                } header: {
                    Text("이 근처")
                }

            }
            // 목록 안에 두면 주변 장소가 많을 때 스크롤해야 나온다. 이건 마땅한 것이
            // 없을 때 쓰는 대체 수단이라, 목록을 다 훑어본 사람에게 가장 필요하면서도
            // 가장 안 보이는 자리에 있게 된다. 바닥에 붙여 항상 보이게 한다.
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    // 카카오 대표 카테고리에 없는 예식장·상점 등도 이름으로 찾을 수 있다.
                    bottomAction("검색", symbol: "magnifyingglass") { searchingPlace = true }
                        .accessibilityIdentifier("droppin.search")

                    bottomAction("여기에 찍기", symbol: "mappin.and.ellipse") {
                        // 이름이 없으면 목록에서 무엇인지 알 수 없다. 좌표를 이름으로
                        // 쓰면 읽을 수 없으니, 나중에 고쳐 쓸 수 있는 이름을 넣어 둔다.
                        onPick(
                            MapPlace(
                                name: address ?? "직접 찍은 지점",
                                address: address,
                                location: coordinate
                            )
                        )
                        dismiss()
                    }
                    .accessibilityIdentifier("droppin.here")

                    // 장소가 아니라 할 말을 남기는 자리다. "여기 주차 어려움" 같은 것은
                    // 단계로 만들 것이 아니라 지도에 적어 두는 편이 맞다.
                    bottomAction("메모", symbol: "text.bubble") { askingMemo = true }
                        .accessibilityIdentifier("droppin.memo")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .navigationTitle("여기에 무엇을 담을까요")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
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
        onPick(
            MapPlace(
                name: candidate.name,
                address: candidate.displayAddress,
                kakaoPlaceId: candidate.kakaoPlaceId,
                location: GeoPoint(lat: candidate.location.lat, lng: candidate.location.lng)
            )
        )
        dismiss()
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
