//
//  ChocoPanApp.swift
//  ChocoPan
//
//  Created by Edgar Zarco on 9/16/26.
//

import SwiftUI
import SwiftData

@main
struct ChocoPanApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(ChocoPanModelContainer.shared)
    }
}
