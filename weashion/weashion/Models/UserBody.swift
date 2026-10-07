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

    var armSize: Double = 1.0
    var legSize: Double = 1.0
    var measuredFields: Set<BodyMeasurement>? = nil


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
