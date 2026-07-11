import Foundation

/// Menu-bar commands live at the Scene level and can't touch `MainWindowView`'s state directly.
/// Each command posts one of these notifications; the window subscribes via `.onReceive` and runs
/// the action in its own view context (where mutating @State is well-defined).
extension Notification.Name {
    static let tabiaNewGame     = Notification.Name("tabia.newGame")
    static let tabiaOpenPGN      = Notification.Name("tabia.openPGN")
    static let tabiaSavePGN      = Notification.Name("tabia.savePGN")
    static let tabiaExportGame    = Notification.Name("tabia.exportGame")
    static let tabiaCopyFEN       = Notification.Name("tabia.copyFEN")
    static let tabiaPasteFEN      = Notification.Name("tabia.pasteFEN")
    static let tabiaFlipBoard     = Notification.Name("tabia.flipBoard")
    static let tabiaStartEngine   = Notification.Name("tabia.startEngine")
    static let tabiaStopEngine    = Notification.Name("tabia.stopEngine")
    static let tabiaAnalyzePosition = Notification.Name("tabia.analyzePosition")
    static let tabiaShowBestMove  = Notification.Name("tabia.showBestMove")
    static let tabiaGoToStart     = Notification.Name("tabia.goToStart")
    static let tabiaPreviousMove  = Notification.Name("tabia.previousMove")
    static let tabiaNextMove      = Notification.Name("tabia.nextMove")
    static let tabiaGoToEnd       = Notification.Name("tabia.goToEnd")
}
