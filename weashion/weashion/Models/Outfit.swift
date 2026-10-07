// 하나의 Outfit
struct Outfit {
    
    var top: String
    
    var outer: String?
    
    var bottom: String
    
    var shoes: String
    
    var reason: String
}


// 날씨 → 옷 추천
struct OutfitRecommendation {
    
    
    static func recommend(weather: WeatherInfo) -> Outfit {
        
        let temperature = weather.feelsLike
        
        let rainProbability = weather.precipitationProbability
        
        
        // 매우 추운 날
        if temperature < 5 {
            
            return Outfit(
                top: "Knit",
                outer: "Heavy Coat",
                bottom: "Long Pants",
                shoes: "Boots",
                reason: "Cold weather: warm layers are recommended."
            )
        }
        
        
        // 추운 날
        if temperature < 12 {
            
            return Outfit(
                top: "Long Sleeve",
                outer: "Jacket",
                bottom: "Long Pants",
                shoes: rainProbability >= 0.4
                    ? "Rain Shoes"
                    : "Sneakers",
                reason: "Cool weather: a light outer layer is recommended."
            )
        }
        
        
        // 선선한 날
        if temperature < 20 {
            
            return Outfit(
                top: "Long Sleeve",
                outer: rainProbability >= 0.5
                    ? "Rain Jacket"
                    : "Light Jacket",
                bottom: "Long Pants",
                shoes: rainProbability >= 0.5
                    ? "Rain Shoes"
                    : "Sneakers",
                reason: rainProbability >= 0.5
                    ? "Cool and rainy weather."
                    : "Mild weather with a light outer layer."
            )
        }
        
        
        // 따뜻한 날
        if temperature < 27 {
            
            return Outfit(
                top: "T-Shirt",
                outer: rainProbability >= 0.5
                    ? "Rain Jacket"
                    : nil,
                bottom: "Long Pants",
                shoes: rainProbability >= 0.5
                    ? "Rain Shoes"
                    : "Sneakers",
                reason: rainProbability >= 0.5
                    ? "Warm but rainy weather."
                    : "Comfortable weather for a light outfit."
            )
        }
        
        
        // 더운 날
        return Outfit(
            top: "T-Shirt",
            outer: rainProbability >= 0.5
                ? "Light Rain Jacket"
                : nil,
            bottom: "Shorts",
            shoes: "Sneakers",
            reason: "Warm weather: lightweight clothing is recommended."
        )
    }
}
