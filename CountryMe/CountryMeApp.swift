//
//  CountryMeApp.swift
//  CountryMe
//
//  Created by xdmGzDev on 08/06/2026.
//

import SwiftUI
import SwiftData

@main
struct CountryMeApp: App {
    @StateObject private var locationManager = LocationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationManager)
                .onAppear { locationManager.start() }
        }
        .modelContainer(SharedModelContainer.shared)
    }
}
