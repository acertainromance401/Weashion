import Foundation
import Combine
import CoreLocation


@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    
    private let manager = CLLocationManager()
    
    // 현재 위치
    @Published var location: CLLocation?
    
    // 위치 권한 상태
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    // 오류 메시지
    @Published var errorMessage: String?
    
    
    override init() {
        super.init()
        
        manager.delegate = self
        
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 1000
    }
    
    
    // 현재 위치 요청
    func requestLocation() {
        
        authorizationStatus = manager.authorizationStatus
        
        switch manager.authorizationStatus {
            
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            
        case .authorizedWhenInUse,
             .authorizedAlways:
            manager.requestLocation()
            
        case .denied,
             .restricted:
            errorMessage =
                "Location permission is required to load local weather."
            
        @unknown default:
            errorMessage =
                "Unknown location authorization status."
        }
    }
    
    
    // 위치 권한 상태가 변경되었을 때
    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        
        authorizationStatus = manager.authorizationStatus
        
        if manager.authorizationStatus == .authorizedWhenInUse ||
            manager.authorizationStatus == .authorizedAlways {
            
            manager.requestLocation()
        }
    }
    
    
    // 위치 가져오기 성공
    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        
        location = locations.first
    }
    
    
    // 위치 가져오기 실패
    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        
        errorMessage = error.localizedDescription
    }
}
