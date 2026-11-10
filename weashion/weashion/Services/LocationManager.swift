import Foundation
import Combine
import CoreLocation

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private let timeout: Duration
    private var timeoutTask: Task<Void, Never>?
    @Published private(set) var location: CLLocation?
    @Published private(set) var locationRevision = 0
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isRequesting = false
    @Published private(set) var errorMessage: String?

    init(manager: CLLocationManager = CLLocationManager(), timeout: Duration = .seconds(15)) {
        self.manager = manager
        self.timeout = timeout
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 1000
    }

    func requestLocation() {
        guard !isRequesting else { return }
        errorMessage = nil
        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .notDetermined:
            isRequesting = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            isRequesting = true
            requestAuthorizedLocation()
        case .denied, .restricted:
            finish(error: permissionMessage)
        @unknown default:
            finish(error: L("위치 권한 상태를 확인하지 못했습니다."))
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if isRequesting { requestAuthorizedLocation() }
        case .denied, .restricted:
            let shouldExplain = isRequesting || location != nil
            location = nil
            finish(error: shouldExplain ? permissionMessage : nil)
        case .notDetermined:
            break
        @unknown default:
            finish(error: L("위치 권한 상태를 확인하지 못했습니다."))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRequesting else { return }
        guard let current = locations.last(where: {
            $0.horizontalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) < 300
                && CLLocationCoordinate2DIsValid($0.coordinate)
        }) else {
            finish(error: L("현재 위치를 확인하지 못했습니다. 다시 시도해 주세요."))
            return
        }
        location = current
        locationRevision += 1
        finish(error: nil)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard isRequesting else { return }
        finish(error: (error as? CLError)?.code == .denied ? permissionMessage : error.localizedDescription)
    }

    private var permissionMessage: String {
        L("현재 날씨를 보려면 설정에서 위치 접근을 허용해 주세요. 피팅룸은 위치 없이 사용할 수 있습니다.")
    }

    private func requestAuthorizedLocation() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self, timeout] in
            do {
                try await Task.sleep(for: timeout)
                self?.finish(error: L("현재 위치를 확인하지 못했습니다. 다시 시도해 주세요."))
            } catch is CancellationError {
                // A response or permission change ends the location deadline.
            } catch {
                self?.finish(error: error.localizedDescription)
            }
        }
        manager.requestLocation()
    }

    private func finish(error: String?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        isRequesting = false
        errorMessage = error
    }
}
