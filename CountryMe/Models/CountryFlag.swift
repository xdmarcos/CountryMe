//
//  CountryFlag.swift
//  CountryMe
//
//  Created by xdmGzDev on 08/06/2026.
//

import Foundation

extension String {
    /// Converts an ISO 3166-1 alpha-2 country code (e.g. "ES") into its flag emoji ("🇪🇸") by
    /// mapping each letter to the corresponding Unicode regional indicator symbol.
    ///
    /// Falls back to returning the code itself if it isn't a two-letter code (e.g. CLPlacemark
    /// occasionally can't resolve one). Shared between the app and the widget.
    var flagEmoji: String {
        let regionalIndicatorBase: UInt32 = 0x1F1E6 // 🇦, corresponds to 'A'
        let asciiUppercaseA: UInt32 = 65

        let upper = uppercased()
        guard upper.count == 2, upper.unicodeScalars.allSatisfy({ $0.isASCII && $0.properties.isAlphabetic }) else {
            return self
        }

        var scalarView = String.UnicodeScalarView()
        for scalar in upper.unicodeScalars {
            guard let flagScalar = Unicode.Scalar(regionalIndicatorBase + (scalar.value - asciiUppercaseA)) else {
                return self
            }
            scalarView.append(flagScalar)
        }
        return String(scalarView)
    }
}
