import Foundation

enum AppLanguagePreference: String, CaseIterable, Identifiable {
    case system
    case english
    case spanishPuertoRico

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: AppLocalization.text("settings.language.automatic")
        case .english: AppLocalization.text("settings.language.english")
        case .spanishPuertoRico: AppLocalization.text("settings.language.spanish_pr")
        }
    }
}

enum AppLocalization {
    static let preferenceKey = "app.language.preference"

    private static var preference: AppLanguagePreference {
        guard let value = UserDefaults.standard.string(forKey: preferenceKey),
              let preference = AppLanguagePreference(rawValue: value) else { return .system }
        return preference
    }

    static var languageCode: String {
        switch preference {
        case .english: return "en"
        case .spanishPuertoRico: return "es"
        case .system: break
        }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if preferred.hasPrefix("es") { return "es" }
        return "en"
    }

    static var locale: Locale {
        languageCode == "es" ? Locale(identifier: "es_PR") : Locale(identifier: "en_US")
    }

    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let resource = languageCode == "es" ? "es-419" : "en"
        let bundle = Bundle.main.path(forResource: resource, ofType: "lproj")
            .flatMap { Bundle(path: $0) } ?? .main
        let format = bundle.localizedString(forKey: key, value: nil, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: arguments)
    }

    static var policyLocalePath: String {
        switch languageCode {
        case "es": "es-419"
        default: "en"
        }
    }
}

enum AppLinks {
    private static let policyOrigin = "https://worksbienstudios.com/apps/shrinkflation-price-scanner"

    static let support = URL(string: "https://worksbienstudios.com/customerservice")!

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
