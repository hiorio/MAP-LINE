import SwiftUI

/// 스파이크 화면. 지도와 "그리기" 토글 하나뿐이다.
///
/// 확인하려는 것은 딱 하나다 — 손가락으로 그은 선이 위경도에 고정되어, 지도를
/// 옮기고 확대해도 제자리에 남는가.
struct ContentView: View {
    @State private var isDrawing = false

    var body: some View {
        ZStack(alignment: .bottom) {
            KakaoMapView(isDrawing: isDrawing)

            HStack(spacing: 8) {
                Button {
                    isDrawing.toggle()
                } label: {
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
            .padding(.bottom, 40)
        }
    }
}
