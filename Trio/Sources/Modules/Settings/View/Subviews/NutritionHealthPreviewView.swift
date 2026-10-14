import HealthKit
import SwiftUI
import Swinject

struct NutritionHealthPreviewView: View {
    @State private var reader: NutritionHealthPreview
    @State private var sources: [NutritionPreviewSource] = []
    @State private var selectedSource = ""
    @State private var groups: [NutritionPreviewGroup] = []
    @State private var offsetMinutes = 0
    @State private var busy = false
    @State private var error: String?

    init(resolver: Resolver) {
        _reader = State(initialValue: NutritionHealthPreview(store: resolver.resolve(HKHealthStore.self)!))
    }

    var body: some View {
        Form {
            introduction
            sourceSection
            timeSection
            if busy { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(groups) { group in
                previewSection(group)
            }
        }
        .navigationTitle(String(localized: "Cronometer Health preview", table: "NutritionPreview"))
        .onChange(of: selectedSource) { _, _ in groups = []; offsetMinutes = 0 }
    }

    private var introduction: some View {
        Section {
            Text(String(localized: "Read-only preview. Nothing here is logged in Trio, converted to FPUs or used for insulin decisions.", table: "NutritionPreview"))
            Text(String(localized: "Check the source, quantities and times against Cronometer. Matching timestamps are grouped together; this does not prove they are one meal. Missing nutrients remain unknown, never zero.", table: "NutritionPreview"))
        }
    }

    private var sourceSection: some View {
        Section {
            Button(String(localized: "Connect nutrition read access", table: "NutritionPreview")) {
                Task { await connect() }
            }.disabled(busy)
            Picker(String(localized: "Cronometer source", table: "NutritionPreview"), selection: $selectedSource) {
                Text(String(localized: "Select a source", table: "NutritionPreview")).tag("")
                ForEach(sources) { source in Text(source.name + " · " + source.id).tag(source.id) }
            }.disabled(busy)
            Button(String(localized: "Refresh preview", table: "NutritionPreview")) {
                Task { await refresh() }
            }.disabled(busy || selectedSource.isEmpty)
            if groups.isEmpty {
                Text(String(localized: "No preview records. Empty results can also mean read access was denied, not synced, or dates are outside the sample-time window. HealthKit does not disclose whether read permission was denied.", table: "NutritionPreview"))
                    .font(.footnote)
            }
        } footer: {
            Text(String(localized: "Only the selected source is read. Trio’s own source is excluded. Your existing Apple Health export setting is unchanged.", table: "NutritionPreview"))
        }
    }

    private var timeSection: some View {
        Section {
            Stepper(value: $offsetMinutes, in: -1440 ... 1440, step: 5) {
                LabeledContent(String(localized: "Preview correction in minutes", table: "NutritionPreview")) {
                    Text(verbatim: String(offsetMinutes))
                }
            }
            Button(String(localized: "Reset time correction", table: "NutritionPreview")) { offsetMinutes = 0 }
        } footer: {
            Text(String(localized: "Correction defaults to zero and changes only this preview. Negative values move sample times earlier. Date Added to Health is not exposed by the public HealthKit sample API. Refresh time is not meal time. Records cover sample dates from 48 hours ago through 24 hours ahead. Sample and preview times use the phone’s time zone; metadata is shown as provided by its source.", table: "NutritionPreview"))
            Text(verbatim: TimeZone.current.identifier)
        }
    }

    private func previewSection(_ group: NutritionPreviewGroup) -> some View {
        Section {
            timestamp(String(localized: "Health sample start", table: "NutritionPreview"), group.id.start)
            timestamp(String(localized: "Health sample end", table: "NutritionPreview"), group.id.end)
            if let adjusted = group.adjustedStart(offsetMinutes: offsetMinutes) {
                timestamp(String(localized: "Preview time", table: "NutritionPreview"), adjusted)
                if adjusted > Date() { Text(String(localized: "This preview time is in the future.", table: "NutritionPreview")).foregroundStyle(.orange) }
            }
            macroRow(String(localized: "Carbohydrates", table: "NutritionPreview"), group.grams(.carbs))
            macroRow(String(localized: "Fat", table: "NutritionPreview"), group.grams(.fat))
            macroRow(String(localized: "Protein", table: "NutritionPreview"), group.grams(.protein))
            if !group.isPointInTime {
                Text(String(localized: "This is a time span. Do not assume it describes an individual meal.", table: "NutritionPreview"))
                    .foregroundStyle(.orange)
            }
            DisclosureGroup(String(localized: "Source records and metadata", table: "NutritionPreview")) {
                ForEach(group.samples) { sample in record(sample) }
            }
        }
    }

    private func timestamp(_ title: String, _ date: Date) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption)
            Text(date.formatted(date: .abbreviated, time: .standard))
        }
    }

    private func macroRow(_ name: String, _ grams: Double?) -> some View {
        LabeledContent(name) {
            if let grams { Text(grams, format: .number.precision(.fractionLength(0 ... 3))) + Text(verbatim: " g") }
            else { Text(String(localized: "Unknown or invalid", table: "NutritionPreview")) }
        }
    }

    private func record(_ sample: NutritionPreviewSample) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: sample.macro.rawValue + ": " + String(sample.grams) + " g")
            Text(verbatim: sample.id.uuidString)
            Text(verbatim: sample.sourceID)
            ForEach(sample.metadata.keys.sorted(), id: \.self) { key in
                Text(verbatim: key + ": " + (sample.metadata[key] ?? ""))
            }
        }.font(.caption).textSelection(.enabled)
    }

    @MainActor private func connect() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        groups = []; sources = []; selectedSource = ""; error = nil
        do { sources = try await reader.connect() } catch { self.error = error.localizedDescription }
    }

    @MainActor private func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        groups = []; error = nil
        let source = selectedSource
        do {
            let result = try await reader.read(sourceID: source)
            guard selectedSource == source else { return }
            groups = result
        } catch { self.error = error.localizedDescription }
    }
}
