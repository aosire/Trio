import Foundation

/// Picks a predicted-glucose value at a fixed horizon across the available
/// `Determination.predictions` curves (IOB / COB / UAM / ZT).
///
/// Mirrors the multi-curve selection in the oref-swift port
/// (`ForecastGenerator.blendForecasts`) but at a single index instead of
/// across the post-peak window. The Trio determination JSON already holds
/// every curve at 5-min increments, so index 4 ≈ +20 min.
///
/// Reduction is `min` of available curves at the horizon — conservative for
/// low detection. oref-swift's own blender uses `max` because it feeds SMB
/// dosing safety; flipping to `min` for an alarm uses the same input set but
/// with the inverted intent.
enum ForecastedGlucoseEvaluator {
    static let defaultHorizonMinutes = 20

    enum Curve: String { case iob, cob, uam, zt }

    struct Result: Equatable {
        let predictedGlucose: Decimal
        let horizonMinutes: Int
        let curvesUsed: Set<Curve>
        let perCurve: [Curve: Decimal]
    }

    static func evaluate(
        determination: Determination,
        horizonMinutes: Int = defaultHorizonMinutes
    ) -> Result? {
        let index = horizonMinutes / 5
        guard let predictions = determination.predictions else { return nil }

        var samples: [Curve: Decimal] = [:]
        if let v = sample(predictions.iob, at: index) { samples[.iob] = v }
        if let v = sample(predictions.cob, at: index) { samples[.cob] = v }
        if let v = sample(predictions.uam, at: index) { samples[.uam] = v }
        if let v = sample(predictions.zt, at: index) { samples[.zt] = v }
        guard let minSample = samples.values.min() else { return nil }

        return Result(
            predictedGlucose: minSample,
            horizonMinutes: horizonMinutes,
            curvesUsed: Set(samples.keys),
            perCurve: samples
        )
    }

    private static func sample(_ array: [Int]?, at index: Int) -> Decimal? {
        guard let array, array.indices.contains(index) else { return nil }
        return Decimal(array[index])
    }
}

/// Display-only snapshot. A scenario range is not a statistical confidence
/// interval, and this selector is never used to calculate insulin or alarms.
struct GlucoseForecastSnapshot: Equatable {
    struct Sample: Equatable {
        let index: Int
        let value: Int
    }

    struct Estimate: Equatable {
        let range: ClosedRange<Decimal>
        let generatedAt: Date
        let target: Date
        let curvesUsed: Set<String>

        func formatted(units: GlucoseUnits, locale: Locale = .current) -> String {
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = false
            formatter.minimumFractionDigits = units == .mgdL ? 0 : 1
            formatter.maximumFractionDigits = units == .mgdL ? 0 : 1
            formatter.roundingMode = .halfUp
            func value(_ glucose: Decimal) -> String {
                let converted = units == .mgdL ? glucose : glucose * GlucoseUnits.exchangeRate
                return formatter.string(from: converted as NSDecimalNumber) ?? "—"
            }
            let lower = value(range.lowerBound)
            let upper = value(range.upperBound)
            return lower == upper ? lower : lower + "–" + upper
        }
    }

    let origin: Date
    let curves: [String: [Sample]]
    static let maximumAge: TimeInterval = 12 * 60

    func estimate(now: Date, glucoseDate: Date?) -> Estimate? {
        guard let glucoseDate,
              now.timeIntervalSince1970.isFinite, origin.timeIntervalSince1970.isFinite,
              glucoseDate.timeIntervalSince1970.isFinite,
              now >= origin, now >= glucoseDate,
              now.timeIntervalSince(origin) < Self.maximumAge,
              now.timeIntervalSince(glucoseDate) < Self.maximumAge
        else { return nil }

        // The target advances with wall-clock time, not the forecast's age.
        let target = now.addingTimeInterval(15 * 60)
        let position = target.timeIntervalSince(origin) / 300
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = Int(position.rounded(.up))
        let fraction = Decimal(position - Double(lowerIndex))
        var interpolated: [String: Decimal] = [:]
        for (curve, samples) in curves where ["iob", "cob", "uam", "zt"].contains(curve) {
            // Duplicate indices are ambiguous. Missing endpoints are not
            // filled by shifting the array, extrapolation or zero padding.
            guard Set(samples.map(\.index)).count == samples.count,
                  let lower = samples.first(where: { $0.index == lowerIndex }),
                  let upper = samples.first(where: { $0.index == upperIndex }),
                  (1 ... 1000).contains(lower.value), (1 ... 1000).contains(upper.value)
            else { continue }
            interpolated[curve] = Decimal(lower.value) + Decimal(upper.value - lower.value) * fraction
        }
        guard let lower = interpolated.values.min(), let upper = interpolated.values.max() else { return nil }
        return Estimate(range: lower ... upper, generatedAt: origin, target: target, curvesUsed: Set(interpolated.keys))
    }
}
