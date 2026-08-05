import SwiftUI

/// 담아 둔 단계와 그 사이 이동수단을 본다.
///
/// 지도 위 핀만으로는 순서를 바꾸거나 "1번에서 2번은 걸어간다"를 정할 자리가 없다.
/// 단계와 구간을 번갈아 늘어놓으면 코스가 한 줄로 읽힌다.
struct CourseSheet: View {
    @Binding var stops: [Stop]
    @Binding var legs: [StopLeg]
    var searchCenter: PlaceCandidate.Coordinate?

    @Environment(\.dismiss) private var dismiss
    /// 지금 길찾기를 부르고 있는 구간들. 여러 구간을 동시에 바꿀 수 있다.
    @State private var loading: Set<Int> = []
    @State private var failures: [Int: String] = [:]
    /// 검색해서 후보를 더할 단계. id만 들고 있어 검색 중 단계 배열이 바뀌어도 다시 찾는다.
    @State private var candidateTarget: CandidateTarget?

    private struct CandidateTarget: Identifiable {
        let stopID: String
        var id: String { stopID }
    }

    var body: some View {
        NavigationStack {
            List {
                if stops.isEmpty {
                    Section {
                        Text("지도를 꾹 눌러 장소를 담으면 여기에 쌓입니다.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                    Section {
                        stopRow(index: index, stop: stop)
                        // 마지막 단계 뒤에는 갈 곳이 없다.
                        if index < stops.count - 1 { legRow(index: index) }
                    }
                }
            }
            .navigationTitle("동선")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .sheet(item: $candidateTarget) { target in
                CoursePlacePickerSheet(
                    stops: stops,
                    initialTargetStopID: target.stopID,
                    near: searchCenter
                ) { stopID, candidates in
                    add(candidates, toStopID: stopID)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - 단계

    private func stopRow(index: Int, stop: Stop) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(index + 1)")
                    .font(.caption.weight(.bold))
                    .frame(width: 22, height: 22)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("후보 \(stop.candidates.count)곳")
                        .font(.body.weight(.semibold))
                    if stop.candidates.count > 1, stop.anchor == nil {
                        // 왜 경로가 안 그려지는지 여기서 말해 준다. 말 안 하면 고장으로 읽힌다.
                        Text("후보 \(stop.candidates.count)곳 · 대표를 정해야 경로를 그립니다")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
                Spacer()
            }

            VStack(spacing: 4) {
                ForEach(Array(stop.candidates.enumerated()), id: \.element.id) { candidateIndex, place in
                    HStack(spacing: 8) {
                        if stop.candidates.count > 1 {
                            Button {
                                togglePrimary(stopID: stop.id, placeID: place.id)
                            } label: {
                                Image(systemName: stop.primaryId == place.id ? "largecircle.fill.circle" : "circle")
                                    .font(.body)
                                    .foregroundStyle(stop.primaryId == place.id ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("\(place.name) 대표로 지정")
                            .accessibilityValue(stop.primaryId == place.id ? "대표" : "대표 아님")
                            .accessibilityIdentifier("course.primary.\(index).\(candidateIndex)")
                        } else {
                            Image(systemName: "mappin.circle.fill")
                                .font(.body)
                                .foregroundStyle(Color.accentColor)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(place.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            if let address = place.address, !address.isEmpty {
                                Text(address)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button(role: .destructive) {
                            removeCandidate(stopID: stop.id, placeID: place.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("\(place.name) 후보에서 빼기")
                        .accessibilityIdentifier("course.removeCandidate.\(index).\(candidateIndex)")
                    }
                }
            }
            .padding(.leading, 32)

            Button {
                candidateTarget = CandidateTarget(stopID: stop.id)
            } label: {
                Label("이 단계에 후보 추가", systemImage: "plus.circle")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .padding(.leading, 32)
            .accessibilityIdentifier("course.addCandidate.\(index)")
        }
        .padding(.vertical, 2)
    }

    /// 검색 화면에서 체크한 여러 곳을 한 번에 담는다. 대상이 없으면 웹처럼 한 단계로 묶는다.
    private func add(_ candidates: [PlaceCandidate], toStopID stopID: String?) {
        let places = candidates.map(\.mapPlace)
        guard !places.isEmpty else { return }

        if let stopID {
            guard stops.addCandidates(places, toStopID: stopID) else { return }
        } else {
            stops.append(Stop(candidates: places))
        }
        // 단계 수가 바뀌거나 후보가 하나에서 둘이 되면 기존 경로의 끝점이 달라질 수 있다.
        // 구간 길이를 맞추고, 그리기 규칙이 저장된 경로의 끝점을 다시 검증한다.
        legs = LegRules.synced(stops: stops, legs: legs)
    }

    private func togglePrimary(stopID: String, placeID: String) {
        guard let index = stops.firstIndex(where: { $0.id == stopID }) else { return }
        stops[index].primaryId = stops[index].primaryId == placeID ? nil : placeID
        legs = LegRules.synced(stops: stops, legs: legs)
    }

    private func removeCandidate(stopID: String, placeID: String) {
        guard let index = stops.firstIndex(where: { $0.id == stopID }) else { return }
        stops[index].candidates.removeAll { $0.id == placeID }
        if stops[index].primaryId == placeID { stops[index].primaryId = nil }
        if stops[index].candidates.isEmpty { stops.remove(at: index) }
        legs = LegRules.synced(stops: stops, legs: legs)
    }

    // MARK: - 구간

    @ViewBuilder
    private func legRow(index: Int) -> some View {
        let leg = legs.indices.contains(index) ? legs[index] : StopLeg()

        VStack(alignment: .leading, spacing: 6) {
            Picker("이동수단", selection: modeBinding(index)) {
                ForEach(TravelMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if loading.contains(index) {
                HStack(spacing: 6) {
                    ProgressView()
                    Text("경로를 찾는 중…").font(.caption2).foregroundStyle(.secondary)
                }
            } else if let message = failures[index] {
                Text(message).font(.caption2).foregroundStyle(.orange)
            } else if let route = LegRules.drawableRoute(stops: stops, index: index, leg: leg) {
                HStack(spacing: 8) {
                    Text(formatDistance(Double(route.distanceM)))
                    Text(formatDuration(route.durationS))
                }
                .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            } else if leg.mode.needsRoute, LegRules.endpoints(stops: stops, index: index) == nil {
                Text("양쪽 단계의 대표가 정해져야 경로를 구할 수 있습니다.")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("course.leg.\(index)")
    }

    private func modeBinding(_ index: Int) -> Binding<TravelMode> {
        Binding(
            get: { legs.indices.contains(index) ? legs[index].mode : .straight },
            set: { newMode in
                legs = LegRules.synced(stops: stops, legs: legs)
                guard legs.indices.contains(index) else { return }
                // 수단이 바뀌면 지금 들고 있는 경로는 다른 수단의 것이다.
                legs[index] = StopLeg(mode: newMode)
                failures[index] = nil
                if newMode.needsRoute { Task { await fetchRoute(index) } }
            }
        )
    }

    private func fetchRoute(_ index: Int) async {
        guard let ends = LegRules.endpoints(stops: stops, index: index) else { return }
        let mode = legs.indices.contains(index) ? legs[index].mode : .straight
        guard mode.needsRoute else { return }

        loading.insert(index)
        defer { loading.remove(index) }

        do {
            let route = try await RouteLookup.find(mode: mode, from: ends.from, to: ends.to)
            // 기다리는 동안 사람이 수단을 또 바꿨을 수 있다. 그러면 이 답은 남의 것이다.
            guard legs.indices.contains(index), legs[index].mode == mode else { return }
            legs[index].route = route
        } catch let error as RouteLookup.NoRoute {
            // 실패가 아니라 "그 수단으로는 못 간다"는 답이다. 직선으로 되돌린다.
            guard legs.indices.contains(index), legs[index].mode == mode else { return }
            legs[index] = StopLeg(mode: .straight)
            failures[index] = error.message
        } catch {
            failures[index] = error.localizedDescription
        }
    }
}
