import SwiftUI
import UIKit

@main
struct NocturneApp: App {
    @StateObject private var environment: AppEnvironment

    init() {
        _environment = StateObject(wrappedValue: AppEnvironment())
        // Тёмная база для системных списков (iOS 15 не имеет scrollContentBackground).
        UITableView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = .clear
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(environment.player)
                .environmentObject(environment.settings)
                .environmentObject(environment.downloads)
                .environmentObject(environment.wave)
                .environmentObject(environment.assistant)
                .preferredColorScheme(.dark)
        }
    }
}
