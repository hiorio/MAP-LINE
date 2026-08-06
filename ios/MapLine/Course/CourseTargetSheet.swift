import SwiftUI

/// 보관함 등에서 고른 장소들을 새 단계 또는 기존 단계 후보로 보낼 곳을 고른다.
struct CourseTargetSheet: View {
    let places: [MapPlace]
    let stops: [Stop]
    let onCommit: (_ stopID: String?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("고른 장소 \(places.count)곳") {
                    ForEach(places) { place in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name).font(.body.weight(.medium))
                            if let address = place.address {
                                Text(address).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("담을 위치") {
                    targetRow(
                        title: "새 단계 만들기",
                        subtitle: "\(stops.count + 1)단계로 추가합니다",
                        symbol: "plus.circle.fill",
                        stopID: nil,
                        identifier: "courseTarget.new"
                    )

                    ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                        targetRow(
                            title: "\(index + 1)단계에 후보로 추가",
                            subtitle: stopSummary(stop),
                            symbol: "square.stack.3d.up.fill",
                            stopID: stop.id,
                            identifier: "courseTarget.\(index)"
                        )
                    }
                }
            }
            .navigationTitle("동선에 담기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
        }
    }

    private func targetRow(
        title: String,
        subtitle: String,
        symbol: String,
        stopID: String?,
        identifier: String
    ) -> some View {
        Button {
            onCommit(stopID)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func stopSummary(_ stop: Stop) -> String {
        let names = stop.candidates.prefix(2).map(\.name).joined(separator: ", ")
        let more = stop.candidates.count > 2 ? " 외 \(stop.candidates.count - 2)곳" : ""
        return names + more
    }
}
