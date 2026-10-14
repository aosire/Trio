import LoopKit

enum BolusStatus: Equatable {
    case noBolus
    case initiating
    case inProgress

    init(pumpState: PumpManagerStatus.BolusState) {
        switch pumpState {
        case .noBolus: self = .noBolus
        case .initiating: self = .initiating
        case .inProgress, .canceling: self = .inProgress
        }
    }
}
