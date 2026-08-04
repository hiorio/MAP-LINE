import SwiftUI

/// 보관함. 다른 앱에서 공유로 넘겨 담아 둔 장소들.
///
/// 익스텐션은 담기만 하고 끝난다. 담은 것을 코스에 올리는 자리가 없으면 보관함은
/// 들어가기만 하고 나오지 않는 곳이 되고, 그러면 공유 익스텐션을 만든 이유가 없어진다.
struct SavedPlacesView: View {
    /// 고른 장소를 단계로 올린다.
    let onAdd: (MapPlace) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var places: [SavedPlace] = []
    /// 이번에 올린 것들. 무엇을 이미 올렸는지 보이지 않으면 같은 곳을 또 누르게 된다.
    @State private var added: Set<String> = []

    private let store = SavedPlaceStore(storage: AppGroupPlaceStorage())

    var body: some View {
        NavigationStack {
            List {
                if places.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("아직 담아 둔 곳이 없습니다.").font(.body)
                            Text("카카오맵이나 브라우저에서 공유 → MAP-LINE을 고르면 여기에 쌓입니다.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                ForEach(places) { place in
                    HStack(alignment: .firstTextBaseline) {
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
                                    location: GeoPoint(lat: place.lat, lng: place.lng)
                                )
                            )
                            added.insert(place.id)
                        } label: {
                            Image(systemName: added.contains(place.id) ? "checkmark.circle.fill" : "plus.circle")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(added.contains(place.id) ? Color.secondary : Color.accentColor)
                        .disabled(added.contains(place.id))
                        .accessibilityLabel("\(place.name) 단계로 올리기")
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { offsets in
                    // 보관함에서만 지운다. 이미 코스에 올린 단계는 그대로 둔다.
                    for index in offsets { store.remove(id: places[index].id) }
                    places = store.all()
                }
            }
            .navigationTitle("보관함")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        // 화면이 뜰 때마다 다시 읽는다. 앱이 떠 있는 동안 익스텐션이 담았을 수 있고,
        // 그건 우리 프로세스가 알 방법이 없다.
        .onAppear { places = store.all() }
    }
}
