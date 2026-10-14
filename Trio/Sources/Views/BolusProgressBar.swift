import SwiftUI

struct BolusProgressBar: View {
    let progress: Decimal

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 15)
                .frame(height: 6)
                .foregroundColor(.clear)
                .background(
                    LinearGradient(colors: [
                        Color(red: 0.7215686275, green: 0.3411764706, blue: 1),
                        Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569),
                        Color(red: 0.4862745098, green: 0.5450980392, blue: 0.9529411765),
                        Color(red: 0.3411764706, green: 0.6666666667, blue: 0.9254901961),
                        Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902)
                    ], startPoint: .leading, endPoint: .trailing)
                        .mask(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 15)
                                .frame(width: geo.size.width * CGFloat(progress))
                                .animation(.easeInOut(duration: 0.25), value: progress)
                        }
                )
        }
        .frame(height: 6)
    }
}

/// Pending/failed stop requests remain visible even if a driver's progress
/// reporter disappears. Only the acknowledged result says the bolus stopped.
struct BolusCancellationStatusView: View {
    let state: BolusCancellationState
    let progress: Decimal?
    let total: Decimal?
    let retry: () -> Void
    let dismiss: () -> Void

    private var title: String {
        switch state {
        case .idle: return ""
        case .cancelling: return String(localized: "Cancelling bolus…", table: "BolusCancellation")
        case .retrying: return String(localized: "Retrying cancellation…", table: "BolusCancellation")
        case .unconfirmed, .failed: return String(localized: "Stop not confirmed", table: "BolusCancellation")
        case .stopped: return String(localized: "Bolus stopped", table: "BolusCancellation")
        }
    }

    private var detail: String {
        switch state {
        case .idle: return ""
        case .cancelling, .retrying: return String(localized: "Waiting for pump confirmation.", table: "BolusCancellation")
        case .unconfirmed, .failed: return String(localized: "Insulin may still be delivering.", table: "BolusCancellation")
        case .stopped: return String(localized: "Confirmed by pump.", table: "BolusCancellation")
        }
    }

    private var deliveryText: String? {
        guard state.isPending, let progress, let total else { return nil }
        return (Formatter.decimalFormatterWithThreeFractionDigits.string(from: (progress * total) as NSNumber) ?? "")
            + String(localized: " of ")
            + (Formatter.decimalFormatterWithThreeFractionDigits.string(from: total as NSNumber) ?? "")
            + String(localized: " U")
    }

    var body: some View {
        HStack(spacing: 10) {
            if state.isPending {
                ProgressView()
                    .accessibilityLabel(Text(title))
            } else {
                Image(systemName: state == .stopped ? "checkmark.circle" : "exclamationmark.triangle")
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline).lineLimit(1)
                Text(detail).font(.caption2).lineLimit(state.isPending ? 1 : 2)
                if let deliveryText {
                    Text(deliveryText)
                        .font(.caption2)
                        .accessibilityLabel(Text(String(localized: "Estimated bolus delivery", table: "BolusCancellation")))
                        .accessibilityValue(Text(deliveryText))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            if case .failed = state {
                Button(action: retry) {
                    Image(systemName: "arrow.clockwise")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text(String(localized: "Retry bolus cancellation", table: "BolusCancellation")))
                .accessibilityIdentifier("retryBolusCancellation")
                Button(action: dismiss) {
                    Text(String(localized: "Dismiss", table: "BolusCancellation"))
                        .font(.caption)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text(String(localized: "Dismiss cancellation warning", table: "BolusCancellation")))
                .accessibilityHint(Text(String(localized: "Dismissing this warning does not stop insulin.", table: "BolusCancellation")))
            } else if state == .stopped {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text(String(localized: "Dismiss cancellation result", table: "BolusCancellation")))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(minHeight: 56)
        .background(Color.insulin.opacity(0.15), in: RoundedRectangle(cornerRadius: 15))
        .overlay(alignment: .bottom) {
            if state != .stopped, let progress {
                BolusProgressBar(progress: progress).padding(.horizontal, 8)
            }
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("bolusCancellationStatus")
    }
}
