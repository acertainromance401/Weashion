import Foundation
import CoreLocation
import Testing
@testable import weashion

@MainActor
struct WeatherServiceTests {
    private final class LocationStub: CLLocationManager {
        var status = CLAuthorizationStatus.authorizedWhenInUse
        var permissionRequests = 0
        var locationRequests = 0
        override var authorizationStatus: CLAuthorizationStatus { status }
        override func requestWhenInUseAuthorization() { permissionRequests += 1 }
        override func requestLocation() { locationRequests += 1 }
    }

    @Test func locationRequiresAnExplicitRequestAndCanRefreshTheSameCoordinate() {
        let stub = LocationStub()
        let manager = LocationManager(manager: stub)
        manager.locationManagerDidChangeAuthorization(stub)
        #expect(stub.locationRequests == 0)
        manager.requestLocation()
        manager.requestLocation()
        #expect(manager.isRequesting)
        #expect(stub.locationRequests == 1)
        let location = CLLocation(latitude: 37, longitude: 127)
        manager.locationManager(stub, didUpdateLocations: [location])
        #expect(!manager.isRequesting)
        #expect(manager.locationRevision == 1)
        manager.requestLocation()
        manager.locationManager(stub, didUpdateLocations: [location])
        #expect(manager.locationRevision == 2)
        #expect(stub.locationRequests == 2)
    }

    @Test func locationPermissionDenialAndRevocationEndRequests() {
        let stub = LocationStub()
        stub.status = .notDetermined
        let manager = LocationManager(manager: stub)
        manager.requestLocation()
        #expect(stub.permissionRequests == 1)
        stub.status = .denied
        manager.locationManagerDidChangeAuthorization(stub)
        #expect(!manager.isRequesting)
        #expect(manager.errorMessage != nil)
        #expect(manager.location == nil)
        stub.status = .authorizedWhenInUse
        manager.locationManagerDidChangeAuthorization(stub)
        #expect(stub.locationRequests == 0)
        manager.requestLocation()
        manager.locationManager(stub, didUpdateLocations: [CLLocation(latitude: 37, longitude: 127)])
        stub.status = .restricted
        manager.locationManagerDidChangeAuthorization(stub)
        #expect(manager.location == nil)
        #expect(manager.errorMessage != nil)
    }

    @Test func grantingPermissionContinuesTheRequestedLocationWithoutAnotherTap() {
        let stub = LocationStub()
        stub.status = .notDetermined
        let manager = LocationManager(manager: stub)
        manager.requestLocation()
        stub.status = .authorizedWhenInUse
        manager.locationManagerDidChangeAuthorization(stub)
        #expect(manager.isRequesting)
        #expect(stub.locationRequests == 1)
        manager.locationManager(stub, didUpdateLocations: [CLLocation(latitude: 37, longitude: 127)])
        #expect(manager.location != nil)
        #expect(!manager.isRequesting)
    }

    @Test func invalidLocationsAndFailuresCanBeRetried() {
        let stub = LocationStub()
        let manager = LocationManager(manager: stub)
        manager.requestLocation()
        let invalid = CLLocation(coordinate: .init(latitude: 37, longitude: 127), altitude: 0,
                                 horizontalAccuracy: -1, verticalAccuracy: -1, timestamp: Date())
        manager.locationManager(stub, didUpdateLocations: [invalid])
        #expect(manager.location == nil)
        #expect(manager.errorMessage != nil)
        #expect(!manager.isRequesting)
        manager.requestLocation()
        manager.locationManager(stub, didFailWithError: CLError(.locationUnknown))
        #expect(!manager.isRequesting)
        #expect(manager.errorMessage != nil)
        manager.requestLocation()
        manager.locationManager(stub, didUpdateLocations: [CLLocation(latitude: 37, longitude: 127)])
        #expect(manager.location != nil)
        #expect(manager.errorMessage == nil)
    }

    @Test func locationDeadlineDoesNotLeaveTheConnectButtonBusy() async throws {
        let stub = LocationStub()
        let manager = LocationManager(manager: stub, timeout: .milliseconds(10))
        manager.requestLocation()
        try await Task.sleep(for: .milliseconds(40))
        #expect(!manager.isRequesting)
        #expect(manager.errorMessage != nil)
    }

    private enum Failure: Error { case offline }

    private func snapshot(_ temperature: Double) -> WeatherManager.Snapshot {
        WeatherManager.Snapshot(weather: WeatherInfo(temperature: temperature), hourly: [],
                                attributionURL: URL(string: "https://weather.apple.com/legal")!)
    }

    @Test func weatherPublishesOnlyTheLatestLocationResponse() async throws {
        let manager = WeatherManager { location in
            if location.coordinate.latitude == 1 { try await Task.sleep(for: .milliseconds(80)) }
            return snapshot(location.coordinate.latitude)
        }
        let old = Task { await manager.loadWeather(for: CLLocation(latitude: 1, longitude: 0)) }
        try await Task.sleep(for: .milliseconds(10))
        await manager.loadWeather(for: CLLocation(latitude: 2, longitude: 0))
        await old.value
        #expect(manager.weather?.temperature == 2)
        #expect(manager.attributionURL != nil)
        #expect(manager.lastUpdated != nil)
        #expect(!manager.isLoading)
    }

    @Test func failedWeatherRefreshKeepsTheLastResultAndRetryClearsTheError() async {
        var offline = false
        let manager = WeatherManager { _ in
            if offline { throw Failure.offline }
            return snapshot(22)
        }
        let location = CLLocation(latitude: 1, longitude: 0)
        await manager.loadWeather(for: location)
        let receivedAt = manager.lastUpdated
        offline = true
        await manager.loadWeather(for: location)
        #expect(manager.weather?.temperature == 22)
        #expect(manager.lastUpdated == receivedAt)
        #expect(manager.errorMessage != nil)
        #expect(!manager.isLoading)
        offline = false
        await manager.loadWeather(for: location)
        #expect(manager.errorMessage == nil)
        #expect(manager.weather?.temperature == 22)
    }

    @Test func clearingWeatherRejectsAnInFlightResultAndReturnsToSampleState() async throws {
        let manager = WeatherManager { _ in
            try await Task.sleep(for: .milliseconds(60))
            return snapshot(22)
        }
        let pending = Task { await manager.loadWeather(for: CLLocation(latitude: 1, longitude: 0)) }
        try await Task.sleep(for: .milliseconds(10))
        manager.clear()
        await pending.value
        #expect(manager.weather == nil)
        #expect(manager.hourly.isEmpty)
        #expect(manager.attributionURL == nil)
        #expect(manager.lastUpdated == nil)
        #expect(!manager.isLoading)
    }

    @Test func cancelledWeatherRequestIsNotPresentedAsANetworkFailure() async throws {
        let manager = WeatherManager { _ in
            try await Task.sleep(for: .seconds(1))
            return snapshot(22)
        }
        let pending = Task { await manager.loadWeather(for: CLLocation(latitude: 1, longitude: 0)) }
        try await Task.sleep(for: .milliseconds(10))
        pending.cancel()
        await pending.value
        #expect(manager.weather == nil)
        #expect(manager.errorMessage == nil)
        #expect(!manager.isLoading)
    }

    @Test func firstWeatherFailureDoesNotPublishASuccessShapedFallback() async {
        let manager = WeatherManager { _ in throw Failure.offline }
        await manager.loadWeather(for: CLLocation(latitude: 1, longitude: 0))
        #expect(manager.weather == nil)
        #expect(manager.lastUpdated == nil)
        #expect(manager.attributionURL == nil)
        #expect(manager.errorMessage != nil)
        #expect(!manager.isLoading)
    }

    @Test func anOldWeatherFailureCannotReplaceANewerSuccess() async throws {
        let manager = WeatherManager { location in
            if location.coordinate.latitude == 1 {
                try await Task.sleep(for: .milliseconds(60))
                throw Failure.offline
            }
            return snapshot(22)
        }
        let old = Task { await manager.loadWeather(for: CLLocation(latitude: 1, longitude: 0)) }
        try await Task.sleep(for: .milliseconds(10))
        await manager.loadWeather(for: CLLocation(latitude: 2, longitude: 0))
        await old.value
        #expect(manager.weather?.temperature == 22)
        #expect(manager.errorMessage == nil)
        #expect(!manager.isLoading)
    }
}
