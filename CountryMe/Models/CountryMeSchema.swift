//
//  CountryMeSchema.swift
//  CountryMe
//
//  Created by xdmGzDev on 08/06/2026.
//

import Foundation
import SwiftData

/// Version 1 of the CountryMe SwiftData schema: `CountryStay` and its per-day `VisitDay` history.
///
/// Pinning the current models to an explicit `VersionedSchema` (rather than handing them to
/// `Schema` directly) is what lets `CountryMeMigrationPlan` describe how to move to future
/// versions without losing data — worth doing now even though there's only one version, since
/// adding versioning later requires a migration *from* an unversioned store, which SwiftData
/// does not support.
enum CountryMeSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [CountryStay.self, VisitDay.self]
    }
}

/// Describes how the CountryMe store evolves across schema versions.
///
/// Only one version exists today, so there are no migration stages. When the model changes
/// (new property, renamed relationship, etc.), add a `CountryMeSchemaV2` alongside this one and
/// a corresponding `.lightweight` or `.custom` stage here — don't mutate `CountryMeSchemaV1` in
/// place, or existing local and CloudKit-synced stores won't have a path to migrate from.
enum CountryMeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CountryMeSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
