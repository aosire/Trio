import Charts
import Foundation
import SwiftUI

struct ForecastView: ChartContent {
    let preprocessedData: [(id: UUID, forecast: Forecast, forecastValue: ForecastValue)]
    let minForecast: [Int]
    let maxForecast: [Int]
    let units: GlucoseUnits
    let maxValue: Decimal
    let forecastDisplayType: ForecastDisplayType
    let lastDeterminationDate: Date
    var isFixedScale: Bool = false

    var body: some ChartContent {
        if forecastDisplayType == .lines {
            drawForecastsLines()
        } else {
            drawForecastsCone()
        }
    }

    private func timeForIndex(_ index: Int32) -> Date {
        let currentTime = lastDeterminationDate
        let timeInterval = TimeInterval(index * 300)
        return currentTime.addingTimeInterval(timeInterval)
    }

    private func displayValue(_ value: Decimal) -> Decimal {
        isFixedScale ? GlucoseChartBounds.displayValue(value, units: units) : value.asUnit(units)
    }

    private func drawForecastsCone() -> some ChartContent {
        // Draw AreaMark for the forecast bounds
        ForEach(0 ..< max(minForecast.count, maxForecast.count), id: \.self) { index in
            if index < minForecast.count, index < maxForecast.count {
                let yMinMaxDelta = Decimal(minForecast[index] - maxForecast[index])
                let xValue = timeForIndex(Int32(index))

                // if distance between respective min and max is 0, provide a default range
                if yMinMaxDelta == 0 {
                    let yMinValue = displayValue(Decimal(minForecast[index] - 1))
                    let yMaxValue = displayValue(Decimal(minForecast[index] + 1))

                    if xValue <= Date(timeIntervalSinceNow: TimeInterval(hours: 2.5)) {
                        AreaMark(
                            x: .value("Time", xValue),
                            // maxValue is already parsed to user units, no need to parse
                            yStart: .value("Min Value", isFixedScale ? yMinValue : min(yMinValue, maxValue)),
                            yEnd: .value("Max Value", isFixedScale ? yMaxValue : min(yMaxValue, maxValue))
                        )
                        .foregroundStyle(Color.blue.opacity(0.5))
                        .interpolationMethod(isFixedScale ? .linear : .catmullRom)
                    }
                } else {
                    let yMinValue = displayValue(Decimal(minForecast[index]))
                    let yMaxValue = displayValue(Decimal(maxForecast[index]))

                    if xValue <= Date(timeIntervalSinceNow: TimeInterval(hours: 2.5)) {
                        AreaMark(
                            x: .value("Time", xValue),
                            // maxValue is already parsed to user units, no need to parse
                            yStart: .value("Min Value", isFixedScale ? yMinValue : min(yMinValue, maxValue)),
                            yEnd: .value("Max Value", isFixedScale ? yMaxValue : min(yMaxValue, maxValue))
                        )
                        .foregroundStyle(Color.blue.opacity(0.5))
                        .interpolationMethod(isFixedScale ? .linear : .catmullRom)
                    }
                }
            }
        }
    }

    private func drawForecastsLines() -> some ChartContent {
        ForEach(preprocessedData, id: \.forecastValue.objectID) { tuple in
            let forecastValue = tuple.forecastValue
            let forecast = tuple.forecast
            let valueAsDecimal = Decimal(forecastValue.value)
            let displayValue = displayValue(valueAsDecimal)
            let xValue = timeForIndex(forecastValue.index)

            if xValue <= Date(timeIntervalSinceNow: TimeInterval(hours: 2.5)) {
                LineMark(
                    x: .value("Time", xValue),
                    y: .value("Value", displayValue)
                )
                .foregroundStyle(by: .value("Predictions", forecast.type ?? ""))
            }
        }
    }
}
