import Foundation
import Combine
import WeatherKit
import CoreLocation

@MainActor
final class WeatherManager: ObservableObject {
    struct Snapshot {
        let weather: WeatherInfo
        let hourly: [WeatherHour]
        let attributionURL: URL
    }

    @Published private(set) var weather: WeatherInfo?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hourly: [WeatherHour] = []
    @Published private(set) var attributionURL: URL?
    @Published private(set) var lastUpdated: Date?
    private let fetch: (CLLocation) async throws -> Snapshot
    private var generation = 0

    init(fetch: @escaping (CLLocation) async throws -> Snapshot = WeatherManager.fetchWeather) {
        self.fetch = fetch
    }

    func clear() {
        generation += 1
        weather = nil
        hourly = []
        attributionURL = nil
        lastUpdated = nil
        errorMessage = nil
        isLoading = false
    }

    func loadWeather(for location: CLLocation) async {
        generation += 1
        let token = generation
        isLoading = true
        errorMessage = nil
        do {
            let snapshot = try await fetch(location)
            try Task.checkCancellation()
            guard generation == token else { return }
            weather = snapshot.weather
            hourly = snapshot.hourly
            attributionURL = snapshot.attributionURL
            lastUpdated = Date()
            isLoading = false
        } catch {
            guard generation == token else { return }
            isLoading = false
            if !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
    }

    private static func fetchWeather(for location: CLLocation) async throws -> Snapshot {
        let service = WeatherService.shared
        let data = try await service.weather(for: location)
        let attributionURL = try await service.attribution.legalPageURL
        let current = data.currentWeather
        return Snapshot(
            weather: WeatherInfo(
                temperature: current.temperature.converted(to: .celsius).value,
                feelsLike: current.apparentTemperature.converted(to: .celsius).value,
                humidity: current.humidity,
                windSpeed: current.wind.speed.converted(to: .metersPerSecond).value,
                precipitationProbability: data.hourlyForecast.forecast.first?.precipitationChance ?? 0,
                condition: current.condition.description,
                locationName: L("현재 위치")),
            hourly: data.hourlyForecast.forecast
                .filter { $0.date >= Date().addingTimeInterval(-3600) }
                .prefix(6)
                .map { WeatherHour(date: $0.date, temperature: $0.temperature.converted(to: .celsius).value,
                                   symbol: $0.symbolName) },
            attributionURL: attributionURL)
    }
}
