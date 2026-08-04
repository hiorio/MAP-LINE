import SwiftUI

/// 이 기기에서 만든 지도들.
///
/// 저장만 되고 다시 열 길이 없으면 앱을 끄는 순간 그 지도는 사라진 것과 같다.
/// 로그인이 없는 제품이라 "내 지도"는 이 기기가 편집 토큰을 갖고 있는 지도를 뜻한다.
struct MyMapsView: View {
    /// 고른 지도를 화면에 올린다.
    let onOpen: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var entries: [MapStore.Entry] = []

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("아직 저장한 지도가 없습니다.").font(.body)
                            Text("장소를 담고 공유 버튼을 누르면 저장됩니다.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                ForEach(entries) { entry in
                    Button {
                        onOpen(entry.slug)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title.isEmpty ? "제목 없는 지도" : entry.title)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(savedAtText(entry.savedAt))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    // 목록에서만 지운다. 서버의 지도와 이미 나눠 준 링크는 그대로 산다 —
                    // 링크를 받은 사람 화면에서 지도가 사라지면 안 된다.
                    for index in offsets { MapStore.forget(slug: entries[index].slug) }
                    entries = MapStore.rememberedMaps()
                }
            }
            .navigationTitle("내 지도")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .onAppear { entries = MapStore.rememberedMaps() }
    }

    private func savedAtText(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 HH:mm"
        return formatter.string(from: date) + "에 저장"
    }
}
