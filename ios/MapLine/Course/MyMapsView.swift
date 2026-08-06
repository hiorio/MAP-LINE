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
    @State private var duplicatingSlug: String?
    @State private var resultMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("아직 저장한 지도가 없습니다.").font(.body)
                            Text("장소·메모·손그림을 추가하면 자동으로 저장됩니다.")
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
                        HStack(spacing: 12) {
                            mapThumbnail(entry)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title.isEmpty ? "제목 없는 지도" : entry.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                HStack(spacing: 7) {
                                    Label(
                                        entry.stopCount.map { "\($0)단계" } ?? "단계 확인 중",
                                        systemImage: "mappin.and.ellipse"
                                    )
                                    .accessibilityIdentifier("mymaps.stopCount")
                                    Text(savedAtText(entry.savedAt))
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if duplicatingSlug == entry.slug {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                    .disabled(duplicatingSlug != nil)
                    .accessibilityIdentifier("mymaps.row.\(entry.slug)")
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button { duplicate(entry) } label: {
                            Label("복제", systemImage: "plus.square.on.square")
                        }
                        .tint(.blue)
                        .accessibilityIdentifier("mymaps.duplicate")
                    }
                    .contextMenu {
                        Button { duplicate(entry) } label: {
                            Label("지도 복제", systemImage: "plus.square.on.square")
                        }
                    }
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
        .alert(
            "지도 복제",
            isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-uiTestingSeedMaps") {
                MapStore.remember(slug: "ui-map", title: "주말 나들이", stopCount: 3)
            }
            entries = MapStore.rememberedMaps()
        }
        .task { await refreshMissingMetadata() }
    }

    private func mapThumbnail(_ entry: MapStore.Entry) -> some View {
        AsyncImage(url: MapStore.thumbnailURL(slug: entry.slug)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    Color(.secondarySystemBackground)
                    Image(systemName: "map")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 72, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
        .accessibilityIdentifier("mymaps.thumbnail")
    }

    private func duplicate(_ entry: MapStore.Entry) {
        guard duplicatingSlug == nil else { return }
        duplicatingSlug = entry.slug
        Task {
            do {
                _ = try await MapStore.duplicate(slug: entry.slug)
                entries = MapStore.rememberedMaps()
                resultMessage = "‘\(entry.title.isEmpty ? "제목 없는 지도" : entry.title)’ 복사본을 만들었습니다."
            } catch {
                resultMessage = error.localizedDescription
            }
            duplicatingSlug = nil
        }
    }

    /// 예전 앱이 저장한 목록에는 단계 수가 없다. 목록은 먼저 즉시 보여 주고, 모르는
    /// 항목만 뒤에서 불러와 다음 실행부터는 서버 호출 없이 표시한다.
    private func refreshMissingMetadata() async {
        let missing = entries.filter { $0.stopCount == nil }
        guard !missing.isEmpty else { return }
        for entry in missing {
            guard !Task.isCancelled, let loaded = try? await MapStore.load(slug: entry.slug) else {
                continue
            }
            let savedAt = ISO8601DateFormatter().date(from: entry.savedAt) ?? Date()
            MapStore.remember(
                slug: entry.slug,
                title: loaded.document.title,
                stopCount: loaded.document.stops.count,
                savedAt: savedAt
            )
        }
        entries = MapStore.rememberedMaps()
    }

    private func savedAtText(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 HH:mm"
        return formatter.string(from: date) + "에 저장"
    }
}
