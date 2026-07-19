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
    static let tabiaSyncGames     = Notification.Name("tabia.syncGames")
    static let tabiaLibraryToggleFilters = Notification.Name("tabia.libraryToggleFilters")
    static let tabiaLibraryImportPGN     = Notification.Name("tabia.libraryImportPGN")
    static let tabiaOpenMyGames          = Notification.Name("tabia.openMyGames")

    // Screen switching
    static let tabiaScreenAnalysis   = Notification.Name("tabia.screen.analysis")
    static let tabiaScreenRepertoire = Notification.Name("tabia.screen.repertoire")
    static let tabiaScreenMyGames    = Notification.Name("tabia.screen.chesscom")
    static let tabiaScreenLibrary    = Notification.Name("tabia.screen.database")

    // Actions added with the rebindable-shortcut system
    static let tabiaSetUpPosition     = Notification.Name("tabia.setUpPosition")
    static let tabiaFullReview        = Notification.Name("tabia.fullReview")
    static let tabiaToggleEngine      = Notification.Name("tabia.toggleEngine")
    static let tabiaToggleAutoAnalyze = Notification.Name("tabia.toggleAutoAnalyze")
    static let tabiaDeleteMove        = Notification.Name("tabia.deleteMove")
    static let tabiaFocusSearch       = Notification.Name("tabia.focusSearch")
    static let tabiaNewDatabase       = Notification.Name("tabia.newDatabase")
    static let tabiaNewRepertoire     = Notification.Name("tabia.newRepertoire")
    static let tabiaAnnBrilliant      = Notification.Name("tabia.ann.brilliant")
    static let tabiaAnnGood           = Notification.Name("tabia.ann.good")
    static let tabiaAnnInteresting    = Notification.Name("tabia.ann.interesting")
    static let tabiaAnnDubious        = Notification.Name("tabia.ann.dubious")
    static let tabiaAnnMistake        = Notification.Name("tabia.ann.mistake")
    static let tabiaAnnBlunder        = Notification.Name("tabia.ann.blunder")
}
