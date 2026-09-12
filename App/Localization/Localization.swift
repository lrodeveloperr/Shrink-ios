import Foundation

enum AppLocalization {
    static var languageCode: String {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if preferred.hasPrefix("fr") { return "fr" }
        if preferred.hasPrefix("es") { return "es" }
        return "en"
    }

    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let format = NSLocalizedString(key, comment: "")
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale.current, arguments: arguments)
    }

    static var policyLocalePath: String {
        switch languageCode {
        case "fr": "fr-ca"
        case "es": "es-419"
        default: "en"
        }
    }
}

enum AppLinks {
    private static let policyOrigin = "https://worksbienstudios.com/apps/shrinkflation-price-scanner"

    static var privacyPolicy: URL {
        policyURL(document: "privacy")
    }

    static var termsOfUse: URL {
        policyURL(document: "terms")
    }

    private static func policyURL(document: String) -> URL {
        URL(string: "\(policyOrigin)/\(AppLocalization.policyLocalePath)/\(document)/")!
    }
}
