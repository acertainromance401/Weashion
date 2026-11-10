import Foundation

nonisolated enum OutfitSlot: String, Codable, CaseIterable, Identifiable, Sendable {
    case top, outer, bottom, shoes

    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .top: L("상의")
        case .outer: L("아우터")
        case .bottom: L("하의")
        case .shoes: L("신발")
        }

    }

    static let fittingOrder: [Self] = [.shoes, .bottom, .top, .outer]
}

enum GarmentFabricKind: String, Codable, CaseIterable, Identifiable {
    case cotton, linen, wool, polyester, nylon, denim, leather, fleece, down

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cotton: L("코튼")
        case .linen: L("린넨")
        case .wool: L("울")
        case .polyester: L("폴리에스터")
        case .nylon: L("나일론")
        case .denim: L("데님")
        case .leather: L("가죽")
        case .fleece: L("플리스")
        case .down: L("다운")
        }
    }

    /// Baseline warmth on a 1–5 scale before weight and category adjustments.
    var baseWarmth: Int {
        switch self {
        case .linen: 1
        case .cotton, .polyester, .nylon: 2
        case .denim, .leather: 3
        case .wool, .fleece: 4
        case .down: 5
        }
    }
}

enum GarmentWeight: String, Codable, CaseIterable, Identifiable {
    case light, medium, heavy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: L("얇음")
        case .medium: L("보통")
        case .heavy: L("두꺼움")
        }
    }

    var warmthAdjustment: Int {
        switch self {
        case .light: -1
        case .medium: 0
        case .heavy: 1
        }
    }
}

enum RainResponse: String, Codable, CaseIterable, Identifiable {
    case none, waterRepellent, waterproof

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: L("비 대응 없음")
        case .waterRepellent: L("발수")
        case .waterproof: L("방수")
        }
    }

    var handlesRain: Bool { self != .none }
}

enum Season: String, Codable, CaseIterable, Identifiable {
    case spring, summer, autumn, winter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spring: L("봄")
        case .summer: L("여름")
        case .autumn: L("가을")
        case .winter: L("겨울")
        }
    }
}

/// Weather-facing attributes of a product. Material and weight are chosen from lists; warmth,
/// rain response and seasons start from a suggested table and stay editable.
struct GarmentClimate: Codable, Equatable {
    static let warmthRange = 1...5

    var material: GarmentFabricKind
    var weight: GarmentWeight
    var warmth: Int
    var rain: RainResponse
    var seasons: Set<Season>

    static func suggested(kind: GarmentKind, material: GarmentFabricKind, weight: GarmentWeight) -> GarmentClimate {
        let warmth = min(max(material.baseWarmth + weight.warmthAdjustment + kind.warmthAdjustment,
                             warmthRange.lowerBound), warmthRange.upperBound)
        let rain: RainResponse
        switch (material, kind.slot) {
        case (.nylon, .outer), (.polyester, .outer), (.nylon, .shoes): rain = .waterRepellent
        case (.leather, _): rain = .waterRepellent
        default: rain = .none
        }
        return GarmentClimate(material: material, weight: weight, warmth: warmth, rain: rain,
                              seasons: seasons(forWarmth: warmth))
    }

    static func seasons(forWarmth warmth: Int) -> Set<Season> {
        switch warmth {
        case ...1: [.summer]
        case 2: [.spring, .summer, .autumn]
        case 3: [.spring, .autumn]
        case 4: [.autumn, .winter]
        default: [.winter]
        }
    }

    var warmthTitle: String {
        switch warmth {
        case ...1: L("아주 시원함")
        case 2: L("시원함")
        case 3: L("보통")
        case 4: L("따뜻함")
        default: L("아주 따뜻함")
        }
    }
}

/// Today's look chosen from the user's own closet, slot by slot. Slots the closet cannot fill
/// fall back to the generic weather recommendation and are marked as samples.
struct ClosetLook: Equatable {
    struct Pick: Equatable, Identifiable {
        let slot: OutfitSlot
        let product: GarmentProduct?
        let fallback: String?

        var id: OutfitSlot { slot }
        var isSample: Bool { product == nil }
        var title: String { product?.name ?? fallback ?? "" }
    }

    let targetWarmth: Int
    let needsRainProtection: Bool
    let picks: [Pick]
}

enum ClosetRecommendation {
    /// Warmth a garment should offer for the perceived temperature.
    static func targetWarmth(feelsLike: Double) -> Int {
        switch feelsLike {
        case 27...: 1
        case 20..<27: 2
        case 12..<20: 3
        case 5..<12: 4
        default: 5
        }
    }

    static func look(weather: WeatherInfo, products: [GarmentProduct]) -> ClosetLook {
        let generic = OutfitRecommendation.recommend(weather: weather)
        let target = targetWarmth(feelsLike: weather.feelsLike)
        let rainy = weather.precipitationProbability >= 0.5
        let fallbacks: [OutfitSlot: String?] = [
            .top: generic.top, .outer: generic.outer, .bottom: generic.bottom, .shoes: generic.shoes
        ]
        let picks = OutfitSlot.allCases.compactMap { slot -> ClosetLook.Pick? in
            let fallback = fallbacks[slot] ?? nil
            let chosen = best(for: slot, products: products, target: target, rainy: rainy)
            // An outer layer is only part of the look when the weather calls for one.
            if slot == .outer, fallback == nil, chosen == nil { return nil }
            return ClosetLook.Pick(slot: slot, product: chosen, fallback: fallback)
        }
        return ClosetLook(targetWarmth: target, needsRainProtection: rainy, picks: picks)
    }

    /// The closest warmth match within one step of the target; rain-ready pieces win on wet days.
    static func best(for slot: OutfitSlot, products: [GarmentProduct], target: Int, rainy: Bool) -> GarmentProduct? {
        let candidates = products.filter { $0.kind.slot == slot }
        let scored = candidates.map { product -> (GarmentProduct, Int) in
            let climate = product.effectiveClimate
            var score = abs(climate.warmth - target) * 10
            if rainy && (slot == .outer || slot == .shoes) && !climate.rain.handlesRain { score += 15 }
            return (product, score)
        }
        .filter { $0.1 <= 15 }
        .sorted { lhs, rhs in
            lhs.1 != rhs.1 ? lhs.1 < rhs.1 : lhs.0.updatedAt > rhs.0.updatedAt
        }
        return scored.first?.0
    }
}
