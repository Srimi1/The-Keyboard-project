import Foundation

/// Reads this build's provisioning-profile expiry, so the free personal team's 7-day death
/// (C-23) is something you can see coming instead of discovering as a keyboard that stopped
/// working mid-sentence.
///
/// ⚠️ **OPEN QUESTION Q-11** — whether `embedded.mobileprovision` is readable from the app
/// sandbox at runtime on the installed iOS version is not verified. Every failure path here
/// returns nil and the caller simply does not render the row, so a wrong guess costs a
/// missing hint rather than a wrong number. Simulator builds have no profile at all and will
/// always return nil.
nonisolated enum ProvisioningProfile {

    /// The profile is a CMS-signed container, not a plist — but the plist is embedded in it
    /// verbatim, so slicing between the XML declaration and the closing tag is enough. No
    /// signature verification: this is a UI hint, not a security control.
    static func expiryDate() -> Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8)) else { return nil }

        let plist = data[start.lowerBound..<end.upperBound]
        let parsed = try? PropertyListSerialization.propertyList(from: plist, options: [], format: nil)
        return (parsed as? [String: Any])?["ExpirationDate"] as? Date
    }

    /// Whole days left. Negative once the profile has lapsed — which is exactly when the
    /// keyboard is already gone and the reason matters most.
    static func daysRemaining(from now: Date = Date()) -> Int? {
        guard let expiry = expiryDate() else { return nil }
        return Calendar.current.dateComponents([.day], from: now, to: expiry).day
    }
}
