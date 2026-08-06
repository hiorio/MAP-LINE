import CoreLocation
import Combine
import Foundation

/// 현재 위치 한 번만 받아 지도 카메라에 넘긴다. 계속 추적하지 않으므로 배터리를 쓰거나
/// 사용자가 지도를 옮긴 뒤 다시 끌고 가지 않는다.
final class CurrentLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var isRequesting = false

    private let manager = CLLocationManager()
    private var completion: ((Result<GeoPoint, Error>) -> Void)?
    private var timeoutWorkItem: DispatchWorkItem?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func request(completion: @escaping (Result<GeoPoint, Error>) -> Void) {
        guard !isRequesting else { return }

        #if DEBUG
        // CI 시뮬레이터는 실제 GPS가 없다. 버튼부터 파란 위치점까지의 화면 흐름을
        // 검증할 때만 성수동의 고정 좌표를 위치 센서처럼 돌려준다.
        if ProcessInfo.processInfo.arguments.contains("-uiTestingCurrentLocation") {
            isRequesting = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.isRequesting = false
                completion(.success(GeoPoint(lat: 37.5444, lng: 127.0374)))
            }
            return
        }
        #endif

        guard CLLocationManager.locationServicesEnabled() else {
            completion(.failure(LocationError.servicesDisabled))
            return
        }

        self.completion = completion
        isRequesting = true
        continueAfterAuthorization(manager.authorizationStatus)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isRequesting else { return }
        continueAfterAuthorization(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // 위치 관리자는 오래된 캐시를 먼저 섞어 보내기도 한다. 정확도와 시각이 유효한
        // 가장 최신 값이 올 때까지 기다린다.
        guard let location = mostRecentUsableLocation(locations) else { return }
        finish(
            .success(
                GeoPoint(
                    lat: location.coordinate.latitude,
                    lng: location.coordinate.longitude
                )
            )
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // GPS가 준비되는 동안 흔히 한두 번 오는 임시 오류다. 여기서 요청을 끝내면
        // 권한을 허용했는데도 버튼이 아무 일도 안 하는 것처럼 보인다.
        guard !isTransientLocationError(error) else { return }
        finish(.failure(error))
    }

    private func continueAfterAuthorization(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            // 앱을 막 열었을 때 이미 받은 최근 위치가 있으면 기다리지 않고 쓴다.
            if let cached = manager.location,
               let usable = mostRecentUsableLocation([cached]) {
                finish(
                    .success(
                        GeoPoint(
                            lat: usable.coordinate.latitude,
                            lng: usable.coordinate.longitude
                        )
                    )
                )
                return
            }
            manager.startUpdatingLocation()
            scheduleTimeout()
        case .denied, .restricted:
            finish(.failure(LocationError.permissionDenied))
        @unknown default:
            finish(.failure(LocationError.locationUnavailable))
        }
    }

    private func scheduleTimeout() {
        timeoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard self?.isRequesting == true else { return }
            self?.finish(.failure(LocationError.timedOut))
        }
        timeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
    }

    private func finish(_ result: Result<GeoPoint, Error>) {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        manager.stopUpdatingLocation()
        let callback = completion
        completion = nil
        isRequesting = false
        callback?(result)
    }
}

/// 위치 관리자가 준 값 중 현재 위치로 쓸 수 있는 가장 최신 값만 고른다. CLLocationManager
/// 없이도 테스트할 수 있게 순수 함수로 둔다.
func mostRecentUsableLocation(
    _ locations: [CLLocation],
    now: Date = Date(),
    maximumAge: TimeInterval = 120
) -> CLLocation? {
    locations
        .filter { location in
            let age = now.timeIntervalSince(location.timestamp)
            return CLLocationCoordinate2DIsValid(location.coordinate)
                && location.horizontalAccuracy >= 0
                && age >= -5
                && age <= maximumAge
        }
        .max { $0.timestamp < $1.timestamp }
}

func isTransientLocationError(_ error: Error) -> Bool {
    (error as? CLError)?.code == .locationUnknown
}

private enum LocationError: LocalizedError {
    case servicesDisabled, permissionDenied, locationUnavailable, timedOut

    var errorDescription: String? {
        switch self {
        case .servicesDisabled:
            return "아이폰의 위치 서비스가 꺼져 있습니다. 설정에서 위치 서비스를 켜 주세요."
        case .permissionDenied:
            return "현재 위치를 보려면 설정에서 이 앱의 위치 접근을 허용해 주세요."
        case .locationUnavailable:
            return "현재 위치를 확인하지 못했습니다. 잠시 후 다시 시도해 주세요."
        case .timedOut:
            return "현재 위치 확인이 늦어지고 있습니다. 하늘이 보이는 곳에서 다시 시도해 주세요."
        }
    }
}
