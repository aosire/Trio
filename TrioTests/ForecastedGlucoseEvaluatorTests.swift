import Foundation
import Testing
@testable import Trio

@Suite("15-minute glucose forecast display") struct FifteenMinuteForecastTests {
    private let origin = Date(timeIntervalSince1970: 1700000000)

    private func samples(_ values: [Int]) -> [GlucoseForecastSnapshot.Sample] {
        values.enumerated().map { .init(index: $0.offset, value: $0.element) }
    }

    private func snapshot() -> GlucoseForecastSnapshot {
        .init(origin: origin, curves: ["iob": samples([100, 110, 120, 130, 140, 150, 160])])
    }

    @Test("Fresh forecasts sample index three") func fresh() throws {
        let estimate = try #require(snapshot().estimate(now: origin, glucoseDate: origin))
        #expect(estimate.range == 130 ... 130)
        #expect(estimate.target == origin.addingTimeInterval(900))
        #expect(estimate.generatedAt == origin)
    }

    @Test("Aged forecasts target fifteen minutes from now") func aged() throws {
        let now = origin.addingTimeInterval(300)
        let estimate = try #require(snapshot().estimate(now: now, glucoseDate: now))
        #expect(estimate.range == 140 ... 140)
        #expect(estimate.target == now.addingTimeInterval(900))
    }

    @Test("Between-step targets interpolate by actual elapsed time") func interpolation() throws {
        let now = origin.addingTimeInterval(150)
        #expect(try #require(snapshot().estimate(now: now, glucoseDate: now)).range == 135 ... 135)
    }

    @Test("Available scenarios form a range, never an invented average") func scenarios() throws {
        let curves = ["iob": samples([100, 100, 100, 130]), "cob": samples([100, 100, 100, 160]),
                      "uam": samples([100, 100, 100, 110]), "zt": samples([100, 100, 100, 120])]
        let estimate = try #require(GlucoseForecastSnapshot(origin: origin, curves: curves).estimate(now: origin, glucoseDate: origin))
        #expect(estimate.range == 110 ... 160)
        #expect(estimate.curvesUsed == Set(["iob", "cob", "uam", "zt"]))
    }

    @Test("Unavailable scenarios are omitted without fabricating values") func missingCurves() throws {
        let curves = ["iob": samples([100, 110, 120, 130]), "cob": samples([100]), "unknown": samples([10, 10, 10, 10])]
        let estimate = try #require(GlucoseForecastSnapshot(origin: origin, curves: curves).estimate(now: origin, glucoseDate: origin))
        #expect(estimate.range == 130 ... 130)
        #expect(estimate.curvesUsed == Set(["iob"]))
    }

    @Test("Missing and short forecasts are unavailable") func shortCurves() {
        for curves in [[:], ["iob": samples([100, 110, 120])]] {
            #expect(GlucoseForecastSnapshot(origin: origin, curves: curves).estimate(now: origin, glucoseDate: origin) == nil)
        }
    }

    @Test("Missing indices cannot shift later samples into the target") func missingIndex() {
        let curve: [GlucoseForecastSnapshot.Sample] = [.init(index: 3, value: 130), .init(index: 5, value: 150)]
        let value = GlucoseForecastSnapshot(origin: origin, curves: ["iob": curve])
        #expect(value.estimate(now: origin.addingTimeInterval(150), glucoseDate: origin) == nil)
        #expect(value.estimate(now: origin, glucoseDate: origin)?.range == 130 ... 130)
    }

    @Test("Out-of-order samples use explicit indices; duplicates are rejected") func indices() {
        let curve = Array(samples([100, 110, 120, 130, 140]).reversed())
        #expect(GlucoseForecastSnapshot(origin: origin, curves: ["iob": curve]).estimate(now: origin, glucoseDate: origin)?.range == 130 ... 130)
        let duplicate = curve + [.init(index: 3, value: 999)]
        #expect(GlucoseForecastSnapshot(origin: origin, curves: ["iob": duplicate]).estimate(now: origin, glucoseDate: origin) == nil)
    }

    @Test("Invalid endpoints are not shown or interpolated") func invalidValues() {
        for value in [-10, 0, 1001, Int.max] {
            let curve = samples([100, 110, 120, value, 140])
            #expect(GlucoseForecastSnapshot(origin: origin, curves: ["iob": curve]).estimate(now: origin, glucoseDate: origin) == nil)
        }
    }

    @Test("Stale forecast or glucose suppresses the display at the boundary") func staleness() {
        let fresh = origin.addingTimeInterval(GlucoseForecastSnapshot.maximumAge - 1)
        #expect(snapshot().estimate(now: fresh, glucoseDate: fresh) != nil)
        let now = origin.addingTimeInterval(GlucoseForecastSnapshot.maximumAge)
        #expect(snapshot().estimate(now: now, glucoseDate: now) == nil)
        #expect(snapshot().estimate(now: origin, glucoseDate: origin.addingTimeInterval(-GlucoseForecastSnapshot.maximumAge)) == nil)
        #expect(snapshot().estimate(now: origin, glucoseDate: nil) == nil)
    }

    @Test("Future and non-finite times are unavailable") func invalidDates() {
        #expect(snapshot().estimate(now: origin.addingTimeInterval(-1), glucoseDate: origin) == nil)
        #expect(snapshot().estimate(now: origin, glucoseDate: origin.addingTimeInterval(1)) == nil)
        #expect(snapshot().estimate(now: Date(timeIntervalSince1970: .infinity), glucoseDate: origin) == nil)
        #expect(GlucoseForecastSnapshot(origin: Date(timeIntervalSince1970: .infinity), curves: snapshot().curves)
            .estimate(now: origin, glucoseDate: origin) == nil)
    }

    @Test("The horizon follows elapsed time across a daylight-saving transition") func daylightSaving() throws {
        let parser = ISO8601DateFormatter()
        let transition = try #require(parser.date(from: "2026-10-25T00:55:00Z"))
        let value = GlucoseForecastSnapshot(origin: transition, curves: snapshot().curves)
        let result = try #require(value.estimate(now: transition.addingTimeInterval(300), glucoseDate: transition))
        #expect(result.target == parser.date(from: "2026-10-25T01:15:00Z"))
        #expect(result.range == 140 ... 140)
    }

    @Test("Formatting converts and rounds both endpoints for the selected unit and locale") func formatting() {
        let estimate = GlucoseForecastSnapshot.Estimate(range: 100 ... 180, generatedAt: origin, target: origin, curvesUsed: ["iob"])
        #expect(estimate.formatted(units: .mgdL, locale: Locale(identifier: "en_GB")) == "100–180")
        #expect(estimate.formatted(units: .mmolL, locale: Locale(identifier: "en_GB")) == "5.6–10.0")
        #expect(estimate.formatted(units: .mmolL, locale: Locale(identifier: "de_DE")) == "5,6–10,0")
    }

    @Test("Selection and formatting leave all input predictions unchanged") func immutable() {
        let value = snapshot()
        let original = value
        let result = value.estimate(now: origin.addingTimeInterval(150), glucoseDate: origin)
        _ = result?.formatted(units: .mmolL)
        #expect(value == original)
    }
}

@Suite("Trio Alerts: ForecastedGlucoseEvaluator") struct ForecastedGlucoseEvaluatorTests {
    /// Builds a `Determination` defaulting every non-predictions field, varying only `predictions`.
    private func makeDetermination(predictions: Predictions?) -> Determination {
        Determination(
            id: nil,
            reason: "",
            units: nil,
            insulinReq: nil,
            eventualBG: nil,
            sensitivityRatio: nil,
            rate: nil,
            duration: nil,
            iob: nil,
            cob: nil,
            predictions: predictions,
            deliverAt: nil,
            carbsReq: nil,
            temp: nil,
            bg: nil,
            reservoir: nil,
            isf: nil,
            timestamp: nil,
            tdd: nil,
            current_target: nil,
            minDelta: nil,
            expectedDelta: nil,
            minGuardBG: nil,
            minPredBG: nil,
            threshold: nil,
            carbRatio: nil,
            received: nil
        )
    }

    @Test("Reduces to min across all four curves at default horizon (+20min, index 4)") func minAcrossAllFourCurves() {
        let predictions = Predictions(
            iob: [100, 101, 102, 103, 104],
            zt: [130, 131, 132, 133, 99],
            cob: [110, 111, 112, 113, 90],
            uam: [120, 121, 122, 123, 95]
        )
        let determination = makeDetermination(predictions: predictions)

        let result = ForecastedGlucoseEvaluator.evaluate(determination: determination)
        #expect(result != nil)
        #expect(result?.predictedGlucose == Decimal(90))
        #expect(result?.horizonMinutes == 20)
        #expect(result?.curvesUsed == Set([.iob, .cob, .uam, .zt]))
        #expect(result?.perCurve[.iob] == Decimal(104))
        #expect(result?.perCurve[.cob] == Decimal(90))
        #expect(result?.perCurve[.uam] == Decimal(95))
        #expect(result?.perCurve[.zt] == Decimal(99))
    }

    @Test("nil predictions returns nil") func nilPredictionsReturnsNil() {
        let determination = makeDetermination(predictions: nil)
        #expect(ForecastedGlucoseEvaluator.evaluate(determination: determination) == nil)
    }

    @Test("All curves shorter than the horizon index returns nil") func indexOutOfBoundsAllShortReturnsNil() {
        let predictions = Predictions(
            iob: [100, 101, 102],
            zt: [130, 131, 132],
            cob: [110, 111, 112],
            uam: [120, 121, 122]
        )
        let determination = makeDetermination(predictions: predictions)
        #expect(ForecastedGlucoseEvaluator.evaluate(determination: determination) == nil)
    }

    @Test("Only one populated curve is used") func onlyOneCurvePopulated() {
        let predictions = Predictions(
            iob: [80, 81, 82, 83, 84],
            zt: nil,
            cob: nil,
            uam: nil
        )
        let determination = makeDetermination(predictions: predictions)

        let result = ForecastedGlucoseEvaluator.evaluate(determination: determination)
        #expect(result != nil)
        #expect(result?.predictedGlucose == Decimal(84))
        #expect(result?.curvesUsed == Set([.iob]))
    }

    @Test("Non-default horizon selects the matching index") func nonDefaultHorizonSelectsCorrectIndex() {
        let predictions = Predictions(
            iob: [100, 90, 80, 70],
            zt: nil,
            cob: [105, 95, 85, 75],
            uam: nil
        )
        let determination = makeDetermination(predictions: predictions)

        let result = ForecastedGlucoseEvaluator.evaluate(determination: determination, horizonMinutes: 10)
        #expect(result != nil)
        #expect(result?.predictedGlucose == Decimal(80))
        #expect(result?.curvesUsed == Set([.iob, .cob]))
        #expect(result?.horizonMinutes == 10)
    }

    @Test("Curves with differing lengths skip those missing the index") func differingLengthsSomeMissing() {
        let predictions = Predictions(
            iob: [100, 101, 102, 103, 104],
            zt: [130, 131, 132],
            cob: [110, 111],
            uam: [120, 121, 122, 123, 70]
        )
        let determination = makeDetermination(predictions: predictions)

        let result = ForecastedGlucoseEvaluator.evaluate(determination: determination)
        #expect(result != nil)
        #expect(result?.predictedGlucose == Decimal(70))
        #expect(result?.curvesUsed == Set([.iob, .uam]))
    }

    @Test("All-empty arrays return nil") func emptyArraysReturnNil() {
        let predictions = Predictions(iob: [], zt: [], cob: [], uam: [])
        let determination = makeDetermination(predictions: predictions)
        #expect(ForecastedGlucoseEvaluator.evaluate(determination: determination) == nil)
    }
}
