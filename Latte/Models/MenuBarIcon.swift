import Foundation

enum MenuBarIcon: String, CaseIterable, Identifiable {
    case cupAndSaucer, cupAndHeatWaves, mug

    var id: Self { self }

    var title: String {
        switch self {
        case .cupAndSaucer: "Cup & Saucer"
        case .cupAndHeatWaves: "Cup & Heat Waves"
        case .mug: "Mug"
        }
    }

    var inactiveSymbolName: String {
        switch self {
        case .cupAndSaucer: "cup.and.saucer"
        case .cupAndHeatWaves: "cup.and.heat.waves"
        case .mug: "mug"
        }
    }

    var activeSymbolName: String {
        switch self {
        case .cupAndSaucer: "cup.and.saucer.fill"
        case .cupAndHeatWaves: "cup.and.heat.waves.fill"
        case .mug: "mug.fill"
        }
    }

    func symbolName(isActive: Bool) -> String {
        isActive ? activeSymbolName : inactiveSymbolName
    }
}
