import SwiftUI

enum AwakeDuration: String, CaseIterable, Identifiable {
    case forever, halfHour, oneHour, twoHours, fourHours, eightHours
    
    var id: Self { self }
    
    var title: LocalizedStringKey {
        switch self {
        case .forever: "Forever"
        case .halfHour: "30 Minutes"
        case .oneHour: "1 Hour"
        case .twoHours: "2 Hours"
        case .fourHours: "4 Hours"
        case .eightHours: "8 Hours"
        }
    }
    
    var timeInterval: TimeInterval? {
        switch self {
        case .forever: nil
        case .halfHour: 30 * 60
        case .oneHour: 60 * 60
        case .twoHours: 2 * 60 * 60
        case .fourHours: 4 * 60 * 60
        case .eightHours: 8 * 60 * 60
        }
    }
    
    var shortcut: Int {
        switch self {
        case .forever: 1
        case .halfHour: 2
        case .oneHour: 3
        case .twoHours: 4
        case .fourHours: 5
        case .eightHours: 6
        }
    }
}
