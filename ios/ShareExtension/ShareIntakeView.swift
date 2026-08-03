import SwiftUI

/// 공유로 들어온 장소를 고르는 화면.
///
/// 후보를 자동으로 확정하지 않는다. 프랜차이즈는 같은 이름의 지점이 여럿이라, 한 곳을
/// 말없이 담으면 엉뚱한 지점이 들어간다. 웹의 붙여넣기 흐름도 같은 이유로 항상 고르게 한다.
struct ShareIntakeView: View {
    let rawText: String
    let onDone: () -> Void
    let onCancel: () -> Void

    @State private var phase: Phase = .loading
    @State private var savedName: String?
    @State private var showRaw = false

    /// `State`라고 이름 짓지 않는다. SwiftUI의 `@State`를 가려서 프로퍼티 래퍼가
    /// 통째로 망가진다. 오류 메시지("enum 'State' cannot be used as an attribute")가
    /// 원인을 바로 알려 주지 않아 헤매기 쉽다.
    private enum Phase {
        case loading
        case ready([ShareIntake.Candidate])
        case failed(String)
    }

    private let store = SavedPlaceStore(storage: AppGroupPlaceStorage())

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    ProgressView("장소를 찾는 중…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .ready(let candidates):
                    List {
                        if let savedName {
                            Section {
                                Label("\(savedName) 담았습니다", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        Section("어느 곳인가요?") {
                            ForEach(candidates) { candidate in
                                Button { save(candidate) } label: { row(candidate) }
                            }
                        }
                        rawSection
                    }

                case .failed(let message):
                    List {
                        Section {
                            Text(message).foregroundStyle(.secondary)
                        }
                        rawSection
                    }
                }
            }
            .navigationTitle("보관함에 담기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기", action: savedName == nil ? onCancel : onDone)
                }
            }
        }
        .task { await lookUp() }
    }

    private func row(_ candidate: ShareIntake.Candidate) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(candidate.name).font(.body)
            if let address = candidate.roadAddress ?? candidate.address {
                Text(address).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// 받은 원문을 접어 둔다.
    ///
    /// 어느 앱이 무엇을 넘기는지는 실기기에서만 알 수 있다. 실패했을 때 무엇이 왔는지
    /// 볼 수 없으면 고칠 수가 없다. 평소에는 접혀 있어 방해되지 않는다.
    private var rawSection: some View {
        Section {
            DisclosureGroup("공유된 원문 보기", isExpanded: $showRaw) {
                Text(rawText.isEmpty ? "(빈 값)" : rawText)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
    }

    private func lookUp() async {
        guard !rawText.isEmpty else {
            phase = .failed("공유된 내용이 비어 있습니다.")
            return
        }
        do {
            let candidates = try await ShareIntake.lookUp(text: rawText, baseURL: AppConfig.apiBaseURL)
            phase = .ready(candidates)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func save(_ candidate: ShareIntake.Candidate) {
        let added = store.add(candidate.asSavedPlace())
        savedName = added ? candidate.name : "\(candidate.name)은(는) 이미"
        // 담자마자 닫으면 담긴 게 맞는지 확인할 틈이 없다. 잠깐 보여 주고 닫는다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: onDone)
    }
}
