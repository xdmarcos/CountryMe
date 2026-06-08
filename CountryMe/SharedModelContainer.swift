//
//  SharedModelContainer.swift
//  CountryMe
//
//  Created by xdmGzDev on 08/06/2026.
//

import Foundation
import SwiftData

/// Builds the single `ModelContainer` shared by the CountryMe app and its widget extension.
///
/// Both processes need to see the *same* SwiftData store, so it lives in the app-group
/// container rather than each target's private sandbox; it's also backed by the user's
/// private CloudKit database so `CountryStay` rows sync across their devices.
///
/// The app-group and iCloud container identifiers below must match the capabilities
/// registered on both targets in Xcode (Signing & Capabilities) — registering them only in
/// the entitlements XML is not sufficient, the provisioning profile needs them too.
enum SharedModelContainer {
    static let appGroupIdentifier = "group.gz.xdmdev.CountryMe"
    static let cloudKitContainerIdentifier = "iCloud.gz.xdmdev.CountryMe"

    static let shared: ModelContainer = {
        let schema = Schema([CountryStay.self])
        let configuration = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(appGroupIdentifier),
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create shared ModelContainer: \(error)")
        }
    }()
}
