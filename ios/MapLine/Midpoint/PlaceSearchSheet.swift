import SwiftUI

/// 장소를 이름으로 찾아 하나 고른다.
///
/// 중간지점에서 "친구는 홍대에서 와"를 입력하는 자리이고, 나중에 편집기의 장소 검색도
/// 같은 화면을 쓴다. 그래서 어디에 쓰이는지 모르게 만들어 둔다.
struct PlaceSearchSheet: View {
    let title: String
    /// 검색 기준점. 넘기면 같은 이름 중 가까운 지점이 위로 온다.
    var near: PlaceCandidate.Coordinate?
    let onPick: (PlaceCandidate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [PlaceCandidate] = []
    @State private var phase: Phase = .idle
    /// 글자를 칠 때마다 부르면 카카오 쿼터가 타이핑 속도로 나간다.
    @State private var searchTask: Task<Void, Never>?

    private enum Phase: Equatable {
        case idle, searching, done, failed(String)
    }

    var body: some View {
        NavigationStack {
            List {
                switch phase {
                case .searching:
                    HStack { ProgressView(); Text("찾는 중…").foregroundStyle(.secondary) }
                case .failed(let message):
                    Text(message).foregroundStyle(.secondary)
                case .done where results.isEmpty:
                    Text("결과가 없습니다.").foregroundStyle(.secondary)
                default:
                    EmptyView()
                }

                ForEach(results) { place in
                    Button {
                        onPick(place)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name).foregroundStyle(.primary)
                            if let address = place.displayAddress {
                                Text(address).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                }
            }
            .searchable(text: $query, prompt: "장소나 주소")
            .onChange(of: query) { _ in schedule() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
        }
    }

    /// 잠깐 기다렸다 부른다. 치는 도중의 조각들로 검색하면 쿼터만 태우고 결과도 쓸모없다.
    private func schedule() {
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
