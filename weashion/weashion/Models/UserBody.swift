import Foundation

struct UserBody: Codable {

    // MARK: - Basic measurements

    var height: Double = 175
    var weight: Double = 70

    var shoulderWidth: Double = 45
    var chest: Double = 98
    var waist: Double = 82
    var hip: Double = 98

    var legLength: Double = 82
    var footLength: Double? = nil

    var armSize: Double = 1.0
    var legSize: Double = 1.0
    var measuredFields: Set<BodyMeasurement>? = nil
    var partScales: [String: Double]? = nil
    var shapePreset: BodyShapePreset? = nil
    var femaleFramePreset: FemaleBodyFramePreset? = nil
    var adjustedFields: Set<BodyMeasurement>? = nil

    func shapeProfile(for base: MannequinBase) -> BodyShapeProfile? {
        return BodyShapeProfile(preset: shapePreset ?? .standard, height: height, weight: weight,
                                feminine: base == .female, framePreset: femaleFramePreset ?? .neutral)
    }

    func usesEstimatedMeasurement(_ measurement: BodyMeasurement, base: MannequinBase) -> Bool {
        guard [.chest, .waist, .hip].contains(measurement) else { return false }
        return measuredFields?.contains(measurement) != true
            && adjustedFields?.contains(measurement) != true
            && self[keyPath: measurement.keyPath] == Self.defaults(for: base)[keyPath: measurement.keyPath]
    }

    func measurementValue(_ measurement: BodyMeasurement, base: MannequinBase) -> Double {
        guard usesEstimatedMeasurement(measurement, base: base), let profile = shapeProfile(for: base) else {
            return self[keyPath: measurement.keyPath]
        }
        let values = profile.estimatedCircumferences
        let meters: Float
        switch measurement {
        case .hip: meters = values.x
        case .waist: meters = values.y
        case .chest: meters = values.z
        default: return self[keyPath: measurement.keyPath]
        }
        let range = measurement.range(for: base)
        return min(max(Double(meters) * 100, range.lowerBound), range.upperBound)
    }

    mutating func setMeasurement(_ value: Double, for measurement: BodyMeasurement) {
        guard value.isFinite else { return }
        self[keyPath: measurement.keyPath] = value
        adjustedFields = (adjustedFields ?? []).union([measurement])
        measuredFields?.remove(measurement)
    }

    mutating func restoreEstimate(for measurement: BodyMeasurement, base: MannequinBase) {
        guard [.chest, .waist, .hip].contains(measurement) else { return }
        self[keyPath: measurement.keyPath] = Self.defaults(for: base)[keyPath: measurement.keyPath]
        adjustedFields?.remove(measurement)
        measuredFields?.remove(measurement)
    }

    func partScale(for part: BodyAnatomy.Part) -> Double {
        guard let value = partScales?[part.rawValue], value.isFinite else { return 1 }
        return min(max(value, part.adjustmentRange.lowerBound), part.adjustmentRange.upperBound)
    }

    func shapeScale(for adjustment: BodyAnatomy.ShapeAdjustment) -> Double {
        adjustment.scale(in: partScales ?? [:])
    }

    mutating func setShapeScale(_ value: Double, for adjustment: BodyAnatomy.ShapeAdjustment) {
        guard value.isFinite else { return }
        let scale = min(max(value, adjustment.adjustmentRange.lowerBound), adjustment.adjustmentRange.upperBound)
        var values = partScales ?? [:]
        if abs(scale - 1) < 0.000001 {
            values.removeValue(forKey: adjustment.rawValue)
        } else {
            values[adjustment.rawValue] = scale
        }
        partScales = values.isEmpty ? nil : values
    }

    mutating func setPartScale(_ value: Double, for part: BodyAnatomy.Part, mirrored: Bool) {
        guard value.isFinite else { return }
        let scale = min(max(value, part.adjustmentRange.lowerBound), part.adjustmentRange.upperBound)
        var values = partScales ?? [:]
        let targets = mirrored ? [part, part.counterpart].compactMap { $0 } : [part]
        for target in targets {
            if abs(scale - 1) < 0.000001 {
                values.removeValue(forKey: target.rawValue)
            } else {
                values[target.rawValue] = scale
            }
        }
        partScales = values.isEmpty ? nil : values
    }

    mutating func synchronizePartScales() {
        for part in BodyAnatomy.Part.allCases where part.rawValue.hasPrefix("left") {
            guard let other = part.counterpart else { continue }
            setPartScale((partScale(for: part) + partScale(for: other)) * 0.5, for: part, mirrored: true)
        }
    }

    static func defaults(for base: MannequinBase) -> Self {
        switch base {
        case .male:
            Self()
        case .female:
            Self(height: 160, weight: 57.5, shoulderWidth: 37.5,
                 chest: 85, waist: 70, hip: 92, legLength: 72, footLength: 240)
        }
    }

    mutating func applyDefaults(from previousBase: MannequinBase, to newBase: MannequinBase) {
        let previous = Self.defaults(for: previousBase)
        let next = Self.defaults(for: newBase)
        for measurement in BodyMeasurement.allCases where measurement.isPhysical {
            guard measuredFields?.contains(measurement) != true,
                  adjustedFields?.contains(measurement) != true,
                  self[keyPath: measurement.keyPath] == previous[keyPath: measurement.keyPath] else { continue }
            self[keyPath: measurement.keyPath] = next[keyPath: measurement.keyPath]
        }
        if footLength == previous.footLength {
            footLength = next.footLength
        }
    }


    // MARK: - Normalized values

    var weightRatio: Double {
        normalize(
            weight,
            minimum: 45,
            maximum: 100
        )
    }

    // MARK: - Signed differences from neutral body

    var weightDelta: Double {
        signedDelta(
            weight,
            neutral: 70,
            minimum: 45,
            maximum: 100
        )
    }

    // MARK: - Helpers

    private func normalize(
        _ value: Double,
        minimum: Double,
        maximum: Double
    ) -> Double {

        let result = (value - minimum) / (maximum - minimum)

        return min(
            max(result, 0),
            1
        )
    }

    private func signedDelta(
        _ value: Double,
        neutral: Double,
        minimum: Double,
        maximum: Double
    ) -> Double {

        if value < neutral {

            return (value - neutral) / (neutral - minimum)

        } else {

            return (value - neutral) / (maximum - neutral)
        }
    }
}
