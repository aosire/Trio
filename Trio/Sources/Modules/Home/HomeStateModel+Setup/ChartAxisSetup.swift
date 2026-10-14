import CoreData
import Foundation

extension Home.StateModel {
    /// Recomputes the main glucose chart Y axis bounds from the fetched glucose objects.
    /// Runs on the main actor since the inputs are viewContext managed objects.
    @MainActor func updateGlucoseChartYAxis(glucoseValues: [GlucoseStored]) {
        let glucoseMapped = glucoseValues.map { Decimal($0.glucose) }
        let forecastValues = preprocessedData.map { Decimal($0.forecastValue.value) }
        let range = GlucoseChartBounds.resolve(
            fixed: fixedGlucoseChartBounds, glucose: glucoseMapped, forecasts: forecastValues, lowThreshold: lowGlucose
        )
        minYAxisValue = range.lowerBound
        maxYAxisValue = range.upperBound
    }

    /// Recomputes the COB chart Y axis bounds from the fetched determination objects.
    @MainActor func yAxisChartDataCobChart(determinations: [OrefDetermination]) {
        let cobMapped = determinations.map { Decimal($0.cob) }

        if let maxCob = cobMapped.max() {
            minValueCobChart = 0
            maxValueCobChart = maxCob == 0 ? 20 : maxCob + 20
        } else {
            minValueCobChart = 0
            maxValueCobChart = 20
        }
    }

    /// Recomputes the IOB chart Y axis bounds from the fetched determination objects.
    @MainActor func yAxisChartDataIobChart(determinations: [OrefDetermination]) {
        let iobMapped = determinations.compactMap { $0.iob?.decimalValue }

        if let minIob = iobMapped.min(), let maxIob = iobMapped.max() {
            minValueIobChart = minIob
            maxValueIobChart = maxIob
        } else {
            minValueIobChart = 0
            maxValueIobChart = 5
        }
    }
}

extension GlucoseChartBounds {
    /// Preserve the existing automatic scale; fixed mode ignores data outliers.
    static func resolve(fixed: GlucoseChartBounds?, glucose: [Decimal], forecasts: [Decimal], lowThreshold: Decimal) -> ClosedRange<Decimal> {
        if let fixed { return fixed.range }
        guard let minimum = glucose.min(), let maximum = glucose.max() else { return 39 ... 200 }
        let adjustedMaximum = min(forecasts.max() ?? maximum + 50, maximum + 50)
        let overallMaximum = max(maximum, adjustedMaximum)
        let upper: Decimal
        if overallMaximum <= 200 { upper = 200 }
        else if overallMaximum <= 225 { upper = 250 }
        else if overallMaximum <= 275 { upper = 300 }
        else if overallMaximum <= 325 { upper = 350 }
        else { upper = 400 }
        return min(minimum, forecasts.min() ?? minimum, lowThreshold - 20) ... upper
    }
}
