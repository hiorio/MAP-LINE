import CoreLocation
import Combine
import Foundation

/// 현재 위치 한 번만 받아 지도 카메라에 넘긴다. 계속 추적하지 않으므로 배터리를 쓰거나
/// 사용자가 지도를 옮긴 뒤 다시 끌고 가지 않는다.
final class CurrentLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var isRequesting = false

    private let manager = CLLocationManager()
    private var completion: ((Result<GeoPoint, Error>) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request(completion: @escaping (Result<GeoPoint, Error>) -> Void) {
        guard !isRequesting else { return }
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
        guard let location = locations.last else {
            finish(.failure(LocationError.locationUnavailable))
            return
        }
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
        finish(.failure(error))
    }

    private func continueAfterAuthorization(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            finish(.failure(LocationError.permissionDenied))
        @unknown default:
            finish(.failure(LocationError.locationUnavailable))
        }
    }

    private func finish(_ result: Result<GeoPoint, Error>) {
        let callback = completion
        completion = nil
        isRequesting = false
        callback?(result)
    }
}

private enum LocationError: LocalizedError {
    case servicesDisabled, permissionDenied, locationUnavailable

    var errorDescription: String? {
        switch self {
        case .servicesDisabled:
            return "아이폰의 위치 서비스가 꺼져 있습니다. 설정에서 위치 서비스를 켜 주세요."
        case .permissionDenied:
            return "현재 위치를 보려면 설정에서 이 앱의 위치 접근을 허용해 주세요."
        case .locationUnavailable:
            return "현재 위치를 확인하지 못했습니다. 잠시 후 다시 시도해 주세요."
        }
    }
}
