import SwiftUI
import UIKit

/// 지도 위의 개인 보관 마커를 한 번 눌렀을 때 나오는 상세.
///
/// 보관함 마크는 어디에 저장했는지를 뜻하지만 이름이 지도에 항상 노출되지는 않는다.
/// 이 화면에서 장소와 폴더를 확인하고, 새 단계나 기존 단계 후보로 바로 보낸다.
struct SavedPlacePinSheet: View {
    let pin: SavedPlacePin
    let stops: [Stop]
    let onAddToCourse: (_ stopID: String?, _ place: MapPlace) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: pin.marker.symbolName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(groupColor)
                            .frame(width: 42, height: 42)
                            .background(
                                groupColor.opacity(0.14),
                                in: Circle()
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pin.name).font(.title3.weight(.semibold))
                            if let address = pin.address, !address.isEmpty {
                                Text(address).font(.footnote).foregroundStyle(.secondary)
                            }
                            Label(pin.group.name, systemImage: "folder.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                } header: {
                    Text("보관한 장소")
                }

                if existingStopNumbers.isEmpty {
                    Section("동선에 담기") {
                        targetRow(
                            title: "새 단계 만들기",
                            subtitle: "\(stops.count + 1)단계로 추가합니다",
                            symbol: "plus.circle.fill",
                            stopID: nil,
                            identifier: "savedPin.course.new"
                        )

                        ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                            targetRow(
                                title: "\(index + 1)단계에 후보로 추가",
                                subtitle: stopSummary(stop),
                                symbol: "square.stack.3d.up.fill",
                                stopID: stop.id,
                                identifier: "savedPin.course.\(index)"
                            )
                        }
                    }
                } else {
                    Section("동선") {
                        Label(
                            "이미 \(existingStopNumbers.map { String($0) }.joined(separator: ", "))단계에 있습니다",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("장소 정보")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private var existingStopNumbers: [Int] {
        stops.enumerated().compactMap { index, stop in
            stop.candidates.contains { isSamePlace(pin.place, $0.savedPlace()) } ? index + 1 : nil
        }
    }

    private var groupColor: Color {
        Color(uiColor: UIColor(hex: pin.colorHex) ?? .systemBlue)
    }

    private func targetRow(
        title: String,
        subtitle: String,
        symbol: String,
        stopID: String?,
        identifier: String
    ) -> some View {
        Button {
            onAddToCourse(stopID, pin.mapPlace)
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
