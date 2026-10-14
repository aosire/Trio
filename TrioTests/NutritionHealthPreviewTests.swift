import Foundation
import HealthKit
import Testing

@testable import Trio

@Suite("Nutrition Health source and time preview") struct NutritionHealthPreviewTests {
    private let source = "test.nutrition.source"
    private let own = "test.trio.source"
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(
        _ macro: NutritionPreviewMacro = .carbs, grams: Double = 20,
        id: UUID = UUID(), source: String? = nil, start: Date? = nil, end: Date? = nil,
        metadata: [String: String] = [:]
    ) -> NutritionPreviewSample {
        .init(id: id, sourceID: source ?? self.source, macro: macro,
              start: start ?? date, end: end ?? start ?? date, grams: grams, metadata: metadata)
    }

    private func build(_ samples: [NutritionPreviewSample]) throws -> [NutritionPreviewGroup] {
        try NutritionPreviewGroup.build(samples, sourceID: source, ownSourceID: own)
    }

    @Test("Selected source excludes Trio and other nutrition exporters") func sources() throws {
        let groups = try build([sample(grams: 10), sample(grams: 99, source: own), sample(grams: 70, source: "other")])
        #expect(groups.count == 1)
        #expect(groups[0].grams(.carbs) == 10)
        #expect(groups[0].samples.count == 1)
    }

    @Test("Trio cannot be selected as an external nutrition source") func ownSource() {
        #expect(throws: NutritionPreviewError.self) {
            try NutritionPreviewGroup.build([sample(source: own)], sourceID: own, ownSourceID: own)
        }
        #expect(throws: NutritionPreviewError.self) {
            try NutritionPreviewGroup.build([], sourceID: "", ownSourceID: own)
        }
    }

    @Test("Equal source timestamps sum macros without assuming individual food names") func matchingTimes() throws {
        let groups = try build([sample(grams: 10), sample(grams: 7.5), sample(.fat, grams: 5), sample(.protein, grams: 12)])
        #expect(groups.count == 1)
        #expect(groups[0].grams(.carbs) == 17.5)
        #expect(groups[0].grams(.fat) == 5)
        #expect(groups[0].grams(.protein) == 12)
    }

    @Test("Missing fat or protein remains unknown rather than zero") func missingMacros() throws {
        let group = try #require(build([sample()]).first)
        #expect(group.grams(.fat) == nil)
        #expect(group.grams(.protein) == nil)
        #expect(group.hasMissingOrInvalidValues)
    }

    @Test("Explicit zero nutrient samples remain known") func zeroMacros() throws {
        let group = try #require(build([sample(), sample(.fat, grams: 0), sample(.protein, grams: 0)]).first)
        #expect(group.grams(.fat) == 0)
        #expect(group.grams(.protein) == 0)
        #expect(!group.hasMissingOrInvalidValues)
    }

    @Test("Nearby timestamps are not silently merged into one meal") func nearbyTimes() throws {
        let groups = try build([sample(), sample(.fat, start: date.addingTimeInterval(1))])
        #expect(groups.count == 2)
        #expect(groups.allSatisfy(\.hasMissingOrInvalidValues))
        #expect(groups[0].id.start > groups[1].id.start)
    }

    @Test("Different end times stay separate and long spans remain visible") func spans() throws {
        let groups = try build([sample(), sample(.fat, end: date.addingTimeInterval(86400))])
        #expect(groups.count == 2)
        #expect(groups.filter(\.isPointInTime).count == 1)
    }

    @Test("Duplicate sample UUIDs reject the snapshot instead of doubling amounts") func duplicateUUID() {
        let a = sample()
        #expect(throws: NutritionPreviewError.self) { try build([a, a]) }
    }

    @Test("Invalid sample dates reject the snapshot") func invalidDates() {
        #expect(throws: NutritionPreviewError.self) { try build([sample(start: Date(timeIntervalSince1970: .infinity))]) }
        #expect(throws: NutritionPreviewError.self) { try build([sample(end: date.addingTimeInterval(-1))]) }
    }

    @Test("Negative and nonfinite nutrient quantities are visible as invalid, never clamped") func invalidAmounts() throws {
        for value in [-1.0, Double.nan, Double.infinity] {
            let group = try #require(build([sample(grams: value)]).first)
            #expect(group.grams(.carbs) == nil)
            #expect(group.hasMissingOrInvalidValues)
            #expect(group.samples.count == 1)
        }
    }

    @Test("Overflowing totals remain invalid") func overflow() throws {
        let group = try #require(build([sample(grams: .greatestFiniteMagnitude), sample(grams: .greatestFiniteMagnitude)]).first)
        #expect(group.grams(.carbs) == nil)
    }

    @Test("Time correction preserves raw sample identity, date and quantity") func correction() throws {
        let original = sample()
        let group = try #require(build([original]).first)
        #expect(group.adjustedStart(offsetMinutes: 0) == date)
        #expect(group.adjustedStart(offsetMinutes: -730) == date.addingTimeInterval(-43800))
        #expect(group.adjustedStart(offsetMinutes: 730) == date.addingTimeInterval(43800))
        #expect(group.samples == [original])
        #expect(group.id.start == date)
    }

    @Test("Correction is bounded and cannot silently overflow") func correctionLimits() throws {
        let group = try #require(build([sample()]).first)
        #expect(group.adjustedStart(offsetMinutes: -1440) != nil)
        #expect(group.adjustedStart(offsetMinutes: 1440) != nil)
        #expect(group.adjustedStart(offsetMinutes: -1441) == nil)
        #expect(group.adjustedStart(offsetMinutes: Int.max) == nil)
    }

    @Test("Future and old source timestamps remain raw for diagnosis") func futureAndOld() throws {
        let future = date.addingTimeInterval(43800)
        let old = date.addingTimeInterval(-86400)
        let groups = try build([sample(start: future), sample(start: old)])
        #expect(groups.map(\.id.start) == [future, old])
    }

    @Test("Source metadata survives grouping without becoming a dosing timestamp") func metadata() throws {
        let metadata = [HKMetadataKeySyncIdentifier: "synthetic-id", "source-test-date": "untrusted-date"]
        let group = try #require(build([sample(metadata: metadata)]).first)
        #expect(group.samples[0].metadata == metadata)
        #expect(group.id.start == date)
    }

    @Test("Empty source data is a valid empty preview, not a permission claim") func empty() throws {
        #expect(try build([]).isEmpty)
    }

    @Test("Health macro types use grams and remain distinct") func quantityTypes() {
        #expect(NutritionPreviewMacro.carbs.type.identifier == HKQuantityTypeIdentifier.dietaryCarbohydrates.rawValue)
        #expect(NutritionPreviewMacro.fat.type.identifier == HKQuantityTypeIdentifier.dietaryFatTotal.rawValue)
        #expect(NutritionPreviewMacro.protein.type.identifier == HKQuantityTypeIdentifier.dietaryProtein.rawValue)
        for macro in NutritionPreviewMacro.allCases {
            let sample = HKQuantitySample(type: macro.type, quantity: HKQuantity(unit: .gram(), doubleValue: 1), start: date, end: date)
            #expect(sample.quantity.doubleValue(for: .gram()) == 1)
        }
    }
}
