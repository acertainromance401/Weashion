import Foundation
import Combine
import WeatherKit
import CoreLocation


@MainActor
final class WeatherManager: ObservableObject {
    
    // 현재 날씨
    @Published var weather: WeatherInfo?
    
    // 날씨를 가져오는 중인지
    @Published var isLoading = false
    
    // 오류 메시지
    @Published var errorMessage: String?
    
    
    private let service = WeatherService.shared
    
    
    func loadWeather(for location: CLLocation) async {
        
        isLoading = true
        errorMessage = nil
        
        
        do {
            
            // 현재 위치의 날씨 가져오기
            let weatherData = try await service.weather(
                for: location
            )
            
            
            // 현재 날씨
            let current = weatherData.currentWeather
            
            
            // 기온
            let temperature =
                current.temperature.value
            
            
            // 체감온도
            let feelsLike =
                current.apparentTemperature.value
            
            
            // 습도
            let humidity =
                current.humidity
            
            
            // 풍속
            let windSpeed =
                current.wind.speed.value
            
            
            // 앱에서 사용할 WeatherInfo 생성
            self.weather = WeatherInfo(
                temperature: temperature,
                feelsLike: feelsLike,
                humidity: humidity,
                windSpeed: windSpeed,
                precipitationProbability: 0,
                condition: current.condition.description,
                locationName: "Current Location"
            )
            
        } catch {
            
            errorMessage =
                error.localizedDescription
        }
        
        
        isLoading = false
    }
}
