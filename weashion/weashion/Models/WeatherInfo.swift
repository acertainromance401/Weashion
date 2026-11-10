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

    var mood: WeatherMood {
        let value = condition.lowercased()
        if value.contains("snow") || value.contains("sleet") || value.contains("눈") || value.contains("雪") { return .snow }
        if value.contains("rain") || value.contains("drizzle") || value.contains("storm") || value.contains("비") || value.contains("雨") { return .rain }
        if value.contains("cloud") || value.contains("fog") || value.contains("overcast") || value.contains("흐") || value.contains("曇") || value.contains("霧") { return .cloud }
        return .clear
    }

    var conditionTitle: String {
        switch mood {
        case .clear: L("맑은 하늘")
        case .cloud: L("구름 낀 하늘")
        case .rain: L("비 오는 날")
        case .snow: L("눈 오는 날")
        }
    }

    var symbol: String {
        switch mood {
        case .clear: "sun.max"
        case .cloud: "cloud.sun"
        case .rain: "cloud.rain"
        case .snow: "cloud.snow"
        }
    }
    
    
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

enum WeatherMood: String, CaseIterable, Identifiable {
    case clear, cloud, rain, snow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clear: L("맑음")
        case .cloud: L("흐림")
        case .rain: L("비")
        case .snow: L("눈")
        }
    }
}

extension WeatherInfo {
    /// Sample weather for a given mood, used before a live forecast is connected.
    static func sample(for mood: WeatherMood) -> WeatherInfo {
        var info = WeatherInfo.sample
        switch mood {
        case .clear:
            info.condition = "Clear"; info.temperature = 24; info.feelsLike = 24; info.precipitationProbability = 0
        case .cloud:
            break
        case .rain:
            info.condition = "Rain"; info.temperature = 16; info.feelsLike = 14; info.precipitationProbability = 0.8
            info.windSpeed = 4.5
        case .snow:
            info.condition = "Snow"; info.temperature = -2; info.feelsLike = -6; info.precipitationProbability = 0.7
            info.windSpeed = 3.0
        }
        return info
    }
}

struct WeatherHour: Identifiable {
    let date: Date
    let temperature: Double
    let symbol: String
    var id: Date { date }
}

enum WeatherPreview {
    /// UserDefaults key for the sample mood shown before a live forecast arrives.
    static let key = "previewWeatherMood"
}
