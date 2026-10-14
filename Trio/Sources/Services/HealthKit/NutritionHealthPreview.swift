import Foundation
import HealthKit

enum NutritionPreviewMacro: String, CaseIterable {
    case carbs, fat, protein

    var type: HKQuantityType {
        let identifier: HKQuantityTypeIdentifier
        switch self {
        case .carbs: identifier = .dietaryCarbohydrates
        case .fat: identifier = .dietaryFatTotal
        case .protein: identifier = .dietaryProtein
        }
        return HKObjectType.quantityType(forIdentifier: identifier)!
    }
}

struct NutritionPreviewSource: Identifiable, Equatable {
    let id: String
    let name: String
}

struct NutritionPreviewSample: Identifiable, Equatable {
    let id: UUID
    let sourceID: String
    let macro: NutritionPreviewMacro
    let start: Date
    let end: Date
    let grams: Double
    let metadata: [String: String]
}

/// Read-only grouping, never an algorithm or meal-storage input. Missing nutrient
/// types remain unknown. Exact timestamps group samples, not an assumed food ID.
struct NutritionPreviewGroup: Identifiable {
    struct Key: Hashable {
        let sourceID: String
        let start: Date
        let end: Date
    }

    let id: Key
    let samples: [NutritionPreviewSample]

    func grams(_ macro: NutritionPreviewMacro) -> Double? {
        let matching = samples.filter { $0.macro == macro }
        guard !matching.isEmpty, matching.allSatisfy({ $0.grams.isFinite && $0.grams >= 0 }) else { return nil }
        let result = matching.reduce(0) { $0 + $1.grams }
        return result.isFinite ? result : nil
    }

    var hasMissingOrInvalidValues: Bool { NutritionPreviewMacro.allCases.contains { grams($0) == nil } }
    var isPointInTime: Bool { id.start == id.end }

    func adjustedStart(offsetMinutes: Int) -> Date? {
        guard (-1440 ... 1440).contains(offsetMinutes), id.start.timeIntervalSince1970.isFinite else { return nil }
        return id.start.addingTimeInterval(TimeInterval(offsetMinutes) * 60)
    }

    static func build(
        _ samples: [NutritionPreviewSample], sourceID: String, ownSourceID: String
    ) throws -> [NutritionPreviewGroup] {
        guard !sourceID.isEmpty, sourceID != ownSourceID else { throw NutritionPreviewError.invalidSource }
        let selected = samples.filter { $0.sourceID == sourceID && $0.sourceID != ownSourceID }
        guard Set(selected.map(\.id)).count == selected.count,
              selected.allSatisfy({ $0.start.timeIntervalSince1970.isFinite && $0.end.timeIntervalSince1970.isFinite && $0.end >= $0.start })
        else { throw NutritionPreviewError.invalidSamples }
        let groups = Dictionary(grouping: selected) { Key(sourceID: $0.sourceID, start: $0.start, end: $0.end) }
        return groups.map { key, values in
            NutritionPreviewGroup(id: key, samples: values.sorted { $0.id.uuidString < $1.id.uuidString })
        }.sorted {
            if $0.id.start != $1.id.start { return $0.id.start > $1.id.start }
            return $0.id.end > $1.id.end
        }
    }
}

enum NutritionPreviewError: LocalizedError {
    case unavailable, invalidSource, invalidSamples, tooManySamples

    var errorDescription: String? {
        switch self {
        case .unavailable: return String(localized: "Health data is unavailable. Unlock the phone and try again.", table: "NutritionPreview")
        case .invalidSource: return String(localized: "Select the Cronometer source. Trio’s own exports cannot be selected.", table: "NutritionPreview")
        case .invalidSamples: return String(localized: "The returned records contain duplicate identifiers or invalid dates. No preview was accepted.", table: "NutritionPreview")
        case .tooManySamples: return String(localized: "Too many nutrition records were returned. The preview was not truncated.", table: "NutritionPreview")
        }
    }
}

/// Explicit foreground reads only. This gateway has no write, carb-storage,
/// settings, determination or pump dependency. Health's creation/Date Added field
/// is not a public HKSample property; never substitute download/observation time.
final class NutritionHealthPreview {
    private let store: HKHealthStore
    private var sources: [String: HKSource] = [:]
    var ownSourceID: String { HKSource.default().bundleIdentifier }

    init(store: HKHealthStore) { self.store = store }

    @MainActor func connect() async throws -> [NutritionPreviewSource] {
        guard HKHealthStore.isHealthDataAvailable() else { throw NutritionPreviewError.unavailable }
        try await store.requestAuthorization(toShare: [], read: Set<HKObjectType>(NutritionPreviewMacro.allCases.map(\.type)))
        var discovered: [String: HKSource] = [:]
        for macro in NutritionPreviewMacro.allCases {
            let result: Set<HKSource> = try await withCheckedThrowingContinuation { continuation in
                let query = HKSourceQuery(sampleType: macro.type, samplePredicate: nil) { _, sources, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: sources ?? []) }
                }
                store.execute(query)
            }
            for source in result where source.bundleIdentifier != ownSourceID {
                discovered[source.bundleIdentifier] = source
            }
        }
        sources = discovered
        return discovered.values.map { NutritionPreviewSource(id: $0.bundleIdentifier, name: $0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @MainActor func read(sourceID: String, now: Date = Date()) async throws -> [NutritionPreviewGroup] {
        guard sourceID != ownSourceID, let source = sources[sourceID], now.timeIntervalSince1970.isFinite else {
            throw NutritionPreviewError.invalidSource
        }
        // Include future sample dates so an incorrectly timestamped source can
        // actually be diagnosed. The range is a sample-time range, not Date Added.
        let start = now.addingTimeInterval(-48 * 3600)
        let end = now.addingTimeInterval(24 * 3600)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: source),
            HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate, .strictEndDate])
        ])
        var samples: [NutritionPreviewSample] = []
        for macro in NutritionPreviewMacro.allCases {
            let records: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(sampleType: macro.type, predicate: predicate, limit: 1001, sortDescriptors: nil) { _, results, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let records = results as? [HKQuantitySample] { continuation.resume(returning: records) }
                    else if results == nil { continuation.resume(returning: []) }
                    else { continuation.resume(throwing: NutritionPreviewError.invalidSamples) }
                }
                store.execute(query)
            }
            guard records.count <= 1000 else { throw NutritionPreviewError.tooManySamples }
            samples += records.map {
                NutritionPreviewSample(
                    id: $0.uuid, sourceID: $0.sourceRevision.source.bundleIdentifier,
                    macro: macro, start: $0.startDate, end: $0.endDate,
                    grams: $0.quantity.doubleValue(for: .gram()),
                    metadata: ($0.metadata ?? [:]).mapValues { String(describing: $0) }
                )
            }
        }
        try Task.checkCancellation()
        return try NutritionPreviewGroup.build(samples, sourceID: sourceID, ownSourceID: ownSourceID)
    }
}
