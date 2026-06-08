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
    @State private var locationManager = LocationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(locationManager)
                .onAppear { locationManager.start() }
        }
        .modelContainer(SharedModelContainer.shared)
    }
}
