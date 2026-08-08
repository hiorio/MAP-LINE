import SwiftUI

/// 이 기기에서 만든 지도들.
///
/// 저장만 되고 다시 열 길이 없으면 앱을 끄는 순간 그 지도는 사라진 것과 같다.
/// 로그인이 없는 제품이라 "내 동선"은 이 기기가 편집 토큰을 갖고 있는 지도를 뜻한다.
struct MyMapsView: View {
    /// 고른 지도를 화면에 올린다.
    let onOpen: (String) -> Void
    /// 현재 열려 있는 지도가 완전 삭제된 경우 편집 화면도 안전하게 비우기 위한 알림.
    let onDelete: (String) -> Void

    init(
        onOpen: @escaping (String) -> Void,
        onDelete: @escaping (String) -> Void = { _ in }
    ) {
        self.onOpen = onOpen
        self.onDelete = onDelete
    }

    @Environment(\.dismiss) private var dismiss
    @State private var entries: [MapStore.Entry] = []
    @State private var hiddenEntries: [MapStore.Entry] = []
    @State private var duplicatingSlug: String?
    @State private var deletingSlug: String?
    @State private var deletingEntry: MapStore.Entry?
    @State private var resultMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty && hiddenEntries.isEmpty {
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
                    .disabled(duplicatingSlug != nil || deletingSlug != nil)
                    .accessibilityIdentifier("mymaps.row.\(entry.slug)")
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button { duplicate(entry) } label: {
                            Label("복제", systemImage: "plus.square.on.square")
                        }
                        .tint(.blue)
                        .accessibilityIdentifier("mymaps.duplicate")
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { deletingEntry = entry } label: {
                            Label("완전 삭제", systemImage: "trash")
                        }
                        Button { hide(entry) } label: {
                            Label("숨기기", systemImage: "eye.slash")
                        }
                        .tint(.gray)
                    }
                    .contextMenu {
                        Button { duplicate(entry) } label: {
                            Label("지도 복제", systemImage: "plus.square.on.square")
                        }
                        Button { hide(entry) } label: {
                            Label("목록에서 숨기기", systemImage: "eye.slash")
                        }
                        Button(role: .destructive) { deletingEntry = entry } label: {
                            Label("공유 지도 완전 삭제", systemImage: "trash")
                        }
                    }
                }

                if !hiddenEntries.isEmpty {
                    Section {
                        ForEach(hiddenEntries) { entry in
                            HStack(spacing: 12) {
                                mapThumbnail(entry)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title.isEmpty ? "제목 없는 지도" : entry.title)
                                        .font(.body.weight(.semibold))
                                        .lineLimit(1)
                                    Text("공유 링크와 편집 권한은 유지됩니다.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("복원") { restore(entry) }
                                    .buttonStyle(.bordered)
                                    .disabled(deletingSlug != nil)
                            }
                            .padding(.vertical, 3)
                            .contextMenu {
                                Button { restore(entry) } label: {
                                    Label("목록으로 복원", systemImage: "eye")
                                }
                                Button(role: .destructive) { deletingEntry = entry } label: {
                                    Label("공유 지도 완전 삭제", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text("숨긴 지도")
                    } footer: {
                        Text("완전 삭제하기 전까지 링크를 받은 사람은 계속 지도를 볼 수 있습니다.")
                    }
                }
            }
            .navigationTitle("내 동선")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .confirmationDialog(
            "공유 지도까지 완전히 삭제할까요?",
            isPresented: Binding(
                get: { deletingEntry != nil },
                set: { if !$0 { deletingEntry = nil } }
            ),
            titleVisibility: .visible,
            presenting: deletingEntry
        ) { entry in
            Button("완전 삭제", role: .destructive) { delete(entry) }
            Button("취소", role: .cancel) { deletingEntry = nil }
        } message: { _ in
            Text("서버의 지도와 공유 링크가 함께 사라지며 되돌릴 수 없습니다.")
        }
        .alert(
            "내 동선",
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
            reloadEntries()
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
                reloadEntries()
                resultMessage = "‘\(entry.title.isEmpty ? "제목 없는 지도" : entry.title)’ 복사본을 만들었습니다."
            } catch {
                resultMessage = error.localizedDescription
            }
            duplicatingSlug = nil
        }
    }

    private func hide(_ entry: MapStore.Entry) {
        MapStore.hide(slug: entry.slug)
        reloadEntries()
    }

    private func restore(_ entry: MapStore.Entry) {
        MapStore.restoreHidden(slug: entry.slug)
        reloadEntries()
    }

    private func delete(_ entry: MapStore.Entry) {
        guard deletingSlug == nil else { return }
        deletingEntry = nil
        deletingSlug = entry.slug
        Task {
            do {
                try await MapStore.delete(slug: entry.slug)
                onDelete(entry.slug)
                reloadEntries()
                resultMessage = "‘\(entry.title.isEmpty ? "제목 없는 지도" : entry.title)’와 공유 링크를 삭제했습니다."
            } catch {
                resultMessage = error.localizedDescription
            }
            deletingSlug = nil
        }
    }

    private func reloadEntries() {
        entries = MapStore.rememberedMaps()
        hiddenEntries = MapStore.hiddenMaps()
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
        reloadEntries()
    }

    private func savedAtText(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 HH:mm"
        return formatter.string(from: date) + "에 저장"
    }
}
