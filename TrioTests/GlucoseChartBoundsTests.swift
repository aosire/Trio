import Foundation
import Testing
@testable import Trio

@Suite("Fixed glucose chart bounds") struct GlucoseChartBoundsTests {
    @Test("A 30 mmol/L outlier cannot resize a fixed chart or change its data") func outlier() throws {
        let bounds = try #require(GlucoseChartBounds(minimum: 50, maximum: 200))
        let readings: [Decimal] = [90, 110, 540, 100]
        let original = readings
        let range = GlucoseChartBounds.resolve(fixed: bounds, glucose: readings, forecasts: [30, 600], lowThreshold: 70)
        #expect(range == 50 ... 200)
        #expect(readings == original)
        #expect(!range.contains(readings[2]))
        #expect(range.contains(readings[0]))
        #expect(GlucoseChartBounds.resolve(fixed: nil, glucose: readings, forecasts: [], lowThreshold: 70).upperBound == 400)
    }

    @Test("Fixed bounds survive missing glucose and forecast data") func noData() throws {
        let bounds = try #require(GlucoseChartBounds(minimum: 60, maximum: 180))
        #expect(GlucoseChartBounds.resolve(fixed: bounds, glucose: [], forecasts: [], lowThreshold: 70) == 60 ... 180)
        #expect(GlucoseChartBounds.resolve(fixed: nil, glucose: [], forecasts: [], lowThreshold: 70) == 39 ... 200)
    }

    @Test("Automatic scaling retains its original steps and forecast cap") func automaticScale() {
        let inputs: [(Decimal, Decimal)] = [(200, 200), (225, 250), (275, 300), (325, 350), (326, 400)]
        for (reading, expected) in inputs {
            #expect(GlucoseChartBounds.resolve(fixed: nil, glucose: [reading], forecasts: [reading], lowThreshold: 70).upperBound == expected)
        }
        #expect(GlucoseChartBounds.resolve(fixed: nil, glucose: [100], forecasts: [600], lowThreshold: 70) == 50 ... 200)
        #expect(GlucoseChartBounds.resolve(fixed: nil, glucose: [40, 100], forecasts: [30], lowThreshold: 70).lowerBound == 30)
    }

    @Test("Invalid or collapsed domains are rejected") func invalidBounds() {
        let pairs: [(Decimal, Decimal)] = [(200, 50), (50, 50), (-1, 180), (0, 1001), (40, Decimal(string: "40.5")!)]
        for pair in pairs {
            #expect(GlucoseChartBounds(minimum: pair.0, maximum: pair.1) == nil)
        }
        #expect(GlucoseChartBounds(minimum: .nan, maximum: 180) == nil)
        #expect(GlucoseChartBounds(minimum: 40, maximum: .nan) == nil)
    }

    @Test("Unit conversion preserves endpoints without collapsing narrow ranges") func units() throws {
        let bounds = try #require(GlucoseChartBounds(minimum: 40, maximum: 41))
        let converted = bounds.displayRange(units: .mmolL)
        #expect(converted.lowerBound < converted.upperBound)
        #expect(converted.contains(GlucoseChartBounds.displayValue(40, units: .mmolL)))
        #expect(converted.contains(GlucoseChartBounds.displayValue(41, units: .mmolL)))
        #expect(bounds.displayRange(units: .mgdL) == 40 ... 41)
    }

    @Test("Older settings keep automatic scaling") func migration() throws {
        let settings = try JSONDecoder().decode(TrioSettings.self, from: Data("{}".utf8))
        #expect(!settings.useFixedGlucoseChartBounds)
        #expect(settings.fixedGlucoseChartBounds == nil)
    }

    @Test("Settings round-trip in either display unit") func roundTrip() throws {
        for units in [GlucoseUnits.mgdL, .mmolL] {
            var settings = TrioSettings()
            settings.units = units
            settings.useFixedGlucoseChartBounds = true
            settings.glucoseChartMinimum = 55
            settings.glucoseChartMaximum = 220
            let restored = try JSONDecoder().decode(TrioSettings.self, from: JSONEncoder().encode(settings))
            #expect(restored == settings)
            #expect(restored.fixedGlucoseChartBounds?.range == 55 ... 220)
        }
    }

    @Test("Corrupt imported bounds fall back to automatic scaling") func invalidImport() throws {
        for json in [
            #"{"useFixedGlucoseChartBounds":true,"glucoseChartMinimum":200,"glucoseChartMaximum":50}"#,
            #"{"useFixedGlucoseChartBounds":true,"glucoseChartMinimum":50}"#,
            #"{"useFixedGlucoseChartBounds":true,"glucoseChartMinimum":"invalid","glucoseChartMaximum":200}"#
        ] {
            let settings = try JSONDecoder().decode(TrioSettings.self, from: Data(json.utf8))
            #expect(settings.fixedGlucoseChartBounds == nil)
            #expect(!settings.useFixedGlucoseChartBounds)
        }
    }

    @Test("Locale-aware input rejects partial numbers and grouping ambiguity") func parsing() throws {
        let british = Locale(identifier: "en_GB")
        let german = Locale(identifier: "de_DE")
        #expect(GlucoseChartBounds.parse(" 180 ", units: .mgdL, locale: british) == 180)
        #expect(GlucoseChartBounds.parse("5,5", units: .mmolL, locale: german) == Decimal(string: "5.5")! / GlucoseUnits.exchangeRate)
        for value in ["", "NaN", "12oops", "1,000", "-1", "1.2.3"] {
            #expect(GlucoseChartBounds.parse(value, units: .mgdL, locale: british) == nil)
        }
    }
}
