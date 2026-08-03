import SwiftUI

/// 앱의 첫 화면.
///
/// 들어가는 문이 둘이다. 지도를 바로 만들 수도 있고, 여러 곳에서 오는 사람들이 모일
/// 자리를 먼저 찾을 수도 있다. 뒤쪽에서 자리를 고르면 그대로 지도로 이어진다 —
/// 중간지점 찾기는 지도 만들기의 시작점이지 별개의 도구가 아니다.
struct ContentView: View {
    /// 값으로 쌓는 내비게이션.
    ///
    /// `navigationDestination(item:)`은 iOS 17부터라 쓰지 않는다. 경로 배열을 직접
    /// 들고 있으면 iOS 16에서도 되고, 중간지점 화면이 결과를 고른 뒤 스스로 다음
    /// 화면을 밀어 넣을 수 있다.
    @State private var path: [Route] = []

    private enum Route: Hashable {
        case midpoint
        case blankMap
        /// 중간지점에서 고른 자리에서 시작하는 지도.
        case mapAt(name: String, lat: Double, lng: Double)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                // Button이 아니라 NavigationLink를 쓴다. List 안의 Button은 강조색을
                // 내용 전체에 입혀서 부제까지 파랗게 만든다. 안에서 색을 지정해도
                // 덮인다. NavigationLink는 목록 스타일을 제대로 받고 화살표도 붙는다.
                Section {
                    NavigationLink(value: Route.blankMap) {
                        entry("지도 만들기", "빈 지도에서 시작합니다", "map")
                    }
                    .accessibilityIdentifier("home.blankMap")

                    NavigationLink(value: Route.midpoint) {
                        entry(
                            "중간지점 찾기",
                            "여러 곳에서 오는 사람들이 모일 자리",
                            "point.topleft.down.curvedto.point.bottomright.up"
                        )
                    }
                    .accessibilityIdentifier("home.midpoint")
                }
            }
            .navigationTitle("MAP-LINE")
            .navigationDestination(for: Route.self) { destination in
                switch destination {
                case .midpoint:
                    MidpointView { candidate in
                        path.append(.mapAt(
                            name: candidate.place.name,
                            lat: candidate.place.location.lat,
                            lng: candidate.place.location.lng
                        ))
                    }
                case .blankMap:
                    MapScreen(center: nil)
                case .mapAt(let name, let lat, let lng):
                    MapScreen(center: .init(name: name, lat: lat, lng: lng))
                }
            }
        }
    }

    private func entry(_ title: String, _ subtitle: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 32)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// 지도 화면. 스파이크에서 쓰던 그리기 토글을 그대로 얹는다.
struct MapScreen: View {
    struct Center: Hashable {
        let name: String
        let lat: Double
        let lng: Double
    }

    let center: Center?
    @State private var isDrawing = false

    var body: some View {
        ZStack(alignment: .bottom) {
            KakaoMapView(isDrawing: isDrawing, center: center)
                .ignoresSafeArea(edges: .bottom)

            HStack(spacing: 8) {
                Button { isDrawing.toggle() } label: {
                    Label(isDrawing ? "그리는 중" : "그리기", systemImage: "pencil.tip")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(isDrawing ? Color.accentColor : Color(.systemBackground))
                        .foregroundStyle(isDrawing ? Color.white : Color.primary)
                        .clipShape(Capsule())
                        .shadow(radius: 4, y: 2)
                }
                .accessibilityIdentifier("drawToggle")

                Text(isDrawing ? "지도가 잠깁니다" : "지도를 옮겨 보세요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground).opacity(0.9))
                    .clipShape(Capsule())
            }
            .padding(.bottom, 24)
        }
        .navigationTitle(center?.name ?? "새 지도")
        .navigationBarTitleDisplayMode(.inline)
    }
}
