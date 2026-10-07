import Foundation

struct WeatherInfo {
    
    // 현재 기온
    var temperature: Double = 20
    
    // 체감온도
    var feelsLike: Double = 20
    
    // 습도
    // 0.0 ~ 1.0
    var humidity: Double = 0.5
    
    // 풍속
    var windSpeed: Double = 0
    
    // 강수확률
    // 0.0 ~ 1.0
    var precipitationProbability: Double = 0
    
    // 날씨 상태
    var condition: String = "Loading..."
    
    // 지역
    var locationName: String = "Current Location"
    
    
    // 실제 날씨를 가져오기 전까지 사용할 테스트 데이터
    static let sample = WeatherInfo(
        temperature: 20,
        feelsLike: 19,
        humidity: 0.55,
        windSpeed: 2.0,
        precipitationProbability: 0.1,
        condition: "Partly Cloudy",
        locationName: "Sample Location"
    )
}
