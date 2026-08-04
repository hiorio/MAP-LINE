import SwiftUI

/// 앱의 첫 화면은 지도다.
///
/// 목록을 먼저 보여 주고 거기서 지도로 들어가는 구조였는데, 이 앱에서 사람이 보고
/// 싶은 것은 언제나 지도다. 목록은 지도를 가리는 문턱일 뿐이었다. 지도를 깔고 그 위에
/// 작은 버튼을 얹는다. 목록은 옆에서 꺼내 쓴다.
struct ContentView: View {
    @State private var isDrawing = false
    @State private var plot: MidpointPlot?
    @State private var menuOpen = false
    @State private var showMidpoint = false

    var body: some View {
        // 지도를 ZStack의 자식으로 두면 안 된다. ZStack은 가장 큰 자식에 맞춰 커지는데
        // 지도가 안전 영역을 넘어가므로 ZStack도 같이 넘어가고, 그 안의 버튼들이 상태바
        // 시계·배터리와 겹쳐 읽을 수 없게 된다. 배경과 오버레이는 크기를 정하지 않으므로
        // 지도는 화면 끝까지 그리면서 조작부는 안전 영역 안에 남는다.
        controls
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                KakaoMapView(isDrawing: isDrawing, plot: plot)
                    .ignoresSafeArea()
            }
            .overlay {
                if menuOpen {
                    SideMenu(
                        isOpen: $menuOpen,
                        onDrawCourse: { startDrawing() },
                        onFindMidpoint: { showMidpoint = true }
                    )
                    .ignoresSafeArea()
                }
            }
            .sheet(isPresented: $showMidpoint) {
                NavigationStack {
                    MidpointView { picked in
                        // 결과를 지도에 얹고 시트를 닫는다. 시트가 떠 있으면 지도를 가려서
                        // 정작 그린 것이 안 보인다. 목록은 답을 고르는 자리고, 답 자체는
                        // 지도에서 읽는다.
                        plot = picked
                        showMidpoint = false
                    }
                }
            }
    }

    // MARK: - 지도 위 조작

    private var controls: some View {
        VStack {
            HStack(alignment: .top) {
                roundButton("line.3.horizontal", label: "메뉴") {
                    withAnimation(.easeOut(duration: 0.22)) { menuOpen = true }
                }
                .accessibilityIdentifier("map.menu")

                Spacer()

                if let plot {
                    // 무엇을 보고 있는지 밝힌다. 지도 위 핀만으로는 이게 몇 번째 후보인지,
                    // 애초에 중간지점 결과인지 알 수 없다. 누르면 지운다 — 결과를 치울
                    // 방법이 없으면 지도가 계속 그 상태로 남는다.
                    Button {
                        self.plot = nil
                    } label: {
                        HStack(spacing: 6) {
                            Text("\(plot.rank)순위 · \(plot.meeting.title)")
                                .font(.footnote.weight(.medium))
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("map.plotChip")
                    .accessibilityLabel("\(plot.meeting.title) 결과 지우기")
                }
            }

            Spacer()

            HStack(alignment: .bottom) {
                Spacer()
                VStack(spacing: 10) {
                    roundButton(
                        "point.topleft.down.curvedto.point.bottomright.up",
                        label: "중간지점 찾기"
                    ) { showMidpoint = true }
                        .accessibilityIdentifier("map.midpoint")

                    roundButton(
                        "scribble.variable",
                        label: "동선 만들기",
                        active: isDrawing
                    ) { startDrawing() }
                        .accessibilityIdentifier("map.draw")
                }
                // 지도 오른쪽 아래 구석에는 카카오 로고가 박혀 있다. 그 위에 버튼을
                // 얹으면 로고가 가려지는데, SDK 이용약관이 로고 노출을 요구한다.
                .padding(.bottom, 24)
            }

            if isDrawing {
                Text("지도가 잠깁니다. 손가락으로 동선을 그리세요.")
                    .font(.caption)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func roundButton(
        _ symbol: String,
        label: String,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 46, height: 46)
                .background(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.regularMaterial))
                .foregroundStyle(active ? Color.white : Color.primary)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .accessibilityLabel(label)
    }

    private func startDrawing() {
        isDrawing.toggle()
    }
}

/// 옆에서 나오는 메뉴.
///
/// 예전 첫 화면이 그대로 여기로 들어왔다. 자주 쓰는 것은 지도 위 버튼으로 꺼내 두고,
/// 여기는 전체 목록을 보는 자리로 둔다.
struct SideMenu: View {
    @Binding var isOpen: Bool
    let onDrawCourse: () -> Void
    let onFindMidpoint: () -> Void

    private let width: CGFloat = 280

    var body: some View {
        ZStack(alignment: .leading) {
            // 바깥을 누르면 닫힌다. 뒤 지도가 움직이지 않도록 덮어 둔다.
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(alignment: .leading, spacing: 0) {
                Text("MAP-LINE")
                    .font(.title2.weight(.bold))
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 20)

                item("scribble.variable", "동선 만들기", "지도에 직접 그립니다") {
                    close()
                    onDrawCourse()
                }
                .accessibilityIdentifier("menu.draw")

                item(
                    "point.topleft.down.curvedto.point.bottomright.up",
                    "중간지점 찾기",
                    "여러 곳에서 오는 사람들이 모일 자리"
                ) {
                    close()
                    onFindMidpoint()
                }
                .accessibilityIdentifier("menu.midpoint")

                Spacer()
            }
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .background(Color(.systemBackground))
            .ignoresSafeArea(edges: .vertical)
            .transition(.move(edge: .leading))
        }
    }

    private func item(
        _ symbol: String,
        _ title: String,
        _ subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.body)
                    .frame(width: 26)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        // List 밖의 Button도 강조색을 물려주므로 꺼 둔다. 안에서 지정한 색이 살아야 한다.
        .buttonStyle(.plain)
    }

    private func close() {
        withAnimation(.easeIn(duration: 0.18)) { isOpen = false }
    }
}
