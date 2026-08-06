import SwiftUI

/// 찍어 둔 핀을 눌렀을 때 나오는 상세.
///
/// 웹에서는 저장된 마커를 한 번 누르면 메뉴가 떴다. 같은 규칙을 따른다 — 찍어 둔
/// 것은 한 번 눌러서 열리고, 빈 자리는 꾹 눌러야 열린다. 두 동작을 구별해 두지 않으면
/// 지도를 옮기려다 계속 무언가가 열린다.
struct StopPinSheet: View {
    let place: MapPlace
    let stopNumber: Int
    /// 같은 단계에 후보가 여럿인가. 하나뿐이면 대표를 고를 일이 없다.
    let canChoosePrimary: Bool
    let isPrimary: Bool
    let onMakePrimary: () -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.name).font(.title3.weight(.semibold))
                        if let address = place.address {
                            Text(address).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("\(stopNumber)번째 단계")
                }

                if canChoosePrimary {
                    Section {
                        Button {
                            onMakePrimary()
                            dismiss()
                        } label: {
                            Label(
                                isPrimary ? "이 단계의 대표입니다" : "이 단계의 대표로 지정",
                                systemImage: isPrimary ? "checkmark.circle.fill" : "circle"
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .disabled(isPrimary)
                    } footer: {
                        // 왜 골라야 하는지 밝힌다. 안 밝히면 그냥 표시로만 읽힌다.
                        Text("후보가 여럿인 단계는 대표를 정해야 실제 경로를 그릴 수 있습니다.")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        onRemove()
                        dismiss()
                    } label: {
                        Label("지우기", systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("stop.remove")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}
