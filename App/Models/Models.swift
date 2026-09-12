import Foundation

struct ProductRecord: Identifiable, Hashable, Sendable {
    var id: String { barcode }
    let barcode: String
    var familyID: String
    var name: String
    var brand: String
    var variant: String
    var quantityValue: Double
    var quantityUnit: QuantityUnit
    var packCount: Int
    var category: String
    var market: String
    var source: ProductSource

    var displayName: String {
        [brand, name, variant]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
    }
    var packageDescription: String {
        PackageFormatter.description(value: quantityValue, unit: quantityUnit, packCount: packCount)
    }
}

enum ProductSource: String, Hashable, Codable, Sendable { case bundled, learned, user }
enum QuantityDimension: String, Hashable, Codable, Sendable { case mass, volume, count }

enum QuantityUnit: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case gram = "g", kilogram = "kg", ounce = "oz", pound = "lb"
    case millilitre = "mL", litre = "L", fluidOunce = "fl oz"
    case item = "items", sheet = "sheets", roll = "rolls", load = "loads"
    case pod = "pods", wipe = "wipes", bag = "bags", capsule = "capsules"

    var id: String { rawValue }
    var localizedSymbol: String { AppLocalization.text("unit.\(rawValue.replacingOccurrences(of: " ", with: "_"))") }
    var dimension: QuantityDimension {
        switch self {
        case .gram, .kilogram, .ounce, .pound: .mass
        case .millilitre, .litre, .fluidOunce: .volume
        default: .count
        }
    }
    var normalizedSymbol: String {
        switch dimension { case .mass: "g"; case .volume: "mL"; case .count: rawValue }
    }
    var conversionFactor: Double {
        switch self {
        case .gram, .millilitre: 1
        case .kilogram, .litre: 1_000
        case .ounce: 28.349_523_125
        case .pound: 453.592_37
        case .fluidOunce: 29.573_529_5625
        default: 1
        }
    }
    func normalize(value: Double, packCount: Int) -> Double {
        value * Double(max(packCount, 1)) * conversionFactor
    }
    static func parse(_ raw: String) -> QuantityUnit? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch value {
        case "g", "gram", "grams", "gramo", "gramos", "gramme", "grammes": return .gram
        case "kg", "kilogram", "kilograms", "kilogramo", "kilogramos", "kilogramme", "kilogrammes": return .kilogram
        case "oz", "ounce", "ounces", "onza", "onzas": return .ounce
        case "lb", "lbs", "pound", "pounds", "libra", "libras", "livre", "livres": return .pound
        case "ml", "milliliter", "milliliters", "millilitre", "millilitres", "mililitro", "mililitros": return .millilitre
        case "l", "liter", "liters", "litre", "litres", "litro", "litros": return .litre
        case "fl oz", "floz", "fluid ounce", "fluid ounces", "onza líquida", "onzas líquidas", "once liquide", "onces liquides": return .fluidOunce
        case "sheet", "sheets", "hoja", "hojas", "feuille", "feuilles": return .sheet
        case "roll", "rolls", "rollo", "rollos", "rouleau", "rouleaux": return .roll
        case "load", "loads", "carga", "cargas", "brassée", "brassées": return .load
        case "pod", "pods", "cápsula", "cápsulas": return .pod
        case "wipe", "wipes", "toallita", "toallitas", "lingette", "lingettes": return .wipe
        case "bag", "bags", "bolsa", "bolsas", "sac", "sacs": return .bag
        case "capsule", "capsules", "pastilla", "pastillas", "comprimé", "comprimés": return .capsule
        case "item", "items", "count", "ct", "unit", "units", "piece", "pieces", "unidad", "unidades", "article", "articles": return .item
        default: return nil
        }
    }
}

enum PackageFormatter {
    static func description(value: Double, unit: QuantityUnit, packCount: Int) -> String {
        guard value > 0 else { return AppLocalization.text("status.details_needed") }
        let amount = value.formatted(.number.precision(.fractionLength(0...2)))
        return packCount > 1 ? "\(packCount) × \(amount) \(unit.localizedSymbol)" : "\(amount) \(unit.localizedSymbol)"
    }
}

enum CurrencyCode: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case usd = "USD", cad = "CAD"
    var id: String { rawValue }
    static var deviceDefault: CurrencyCode { Locale.current.currency?.identifier == "CAD" ? .cad : .usd }
}

enum SalesChannel: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case inStore, online
    var id: String { rawValue }
    var title: String { AppLocalization.text("channel.\(rawValue)") }
}

enum PriceType: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case regular, sale, loyalty
    var id: String { rawValue }
    var title: String { AppLocalization.text("price_type.\(rawValue)") }
}

enum PurchaseDecision: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case none, skipped, switched, bought
    var id: String { rawValue }
    var title: String { AppLocalization.text("decision.\(rawValue)") }
}

struct Observation: Identifiable, Hashable, Sendable {
    let id: UUID
    var tripID: UUID
    var familyID: String
    var barcode: String
    var name: String
    var brand: String
    var variant: String
    var category: String
    var quantityValue: Double
    var quantityUnit: QuantityUnit
    var packCount: Int
    var price: Decimal?
    var currency: CurrencyCode
    var store: String
    var branch: String
    var channel: SalesChannel
    var priceType: PriceType
    var source: ProductSource
    var matchConfidence: Double
    var decision: PurchaseDecision
    var purchaseQuantity: Int
    var observedAt: Date
    var isDraft: Bool

    var normalizedQuantity: Double { quantityUnit.normalize(value: quantityValue, packCount: packCount) }
    var normalizedUnit: String { quantityUnit.normalizedSymbol }
    var displayName: String {
        let composed = [brand, name, variant]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        return composed.isEmpty ? AppLocalization.text("status.unknown_product") : composed
    }
    var packageDescription: String { PackageFormatter.description(value: quantityValue, unit: quantityUnit, packCount: packCount) }
    var formattedPrice: String? { price?.formatted(.currency(code: currency.rawValue)) }
}

struct ObservationDraft: Identifiable, Sendable {
    let id: UUID
    var tripID: UUID
    var barcode: String
    var familyID: String
    var name: String
    var brand: String
    var variant: String
    var category: String
    var quantityValue: Double
    var quantityUnit: QuantityUnit
    var packCount: Int
    var price: Decimal?
    var currency: CurrencyCode
    var store: String
    var branch: String
    var channel: SalesChannel
    var priceType: PriceType
    var observedAt: Date
    var isKnownProduct: Bool
    var purchaseQuantity: Int
    var capturedDraftID: UUID?

    init(barcode: String, product: ProductRecord?, trip: ShoppingTrip) {
        id = UUID(); tripID = trip.id; self.barcode = barcode
        familyID = product?.familyID ?? "user:\(UUID().uuidString.lowercased())"
        name = product?.name ?? ""; brand = product?.brand ?? ""; variant = product?.variant ?? ""
        category = product?.category ?? ""; quantityValue = product?.quantityValue ?? 0
        quantityUnit = product?.quantityUnit ?? .gram; packCount = product?.packCount ?? 1
        price = nil; currency = trip.store.currency; store = trip.store.name; branch = ""
        channel = .inStore; priceType = .regular; observedAt = .now
        isKnownProduct = product != nil; purchaseQuantity = 1; capturedDraftID = nil
    }

    init(observation: Observation) {
        id = UUID(); tripID = observation.tripID; barcode = observation.barcode
        familyID = observation.familyID; name = observation.name; brand = observation.brand
        variant = observation.variant; category = observation.category
        quantityValue = observation.quantityValue; quantityUnit = observation.quantityUnit
        packCount = observation.packCount; price = observation.price; currency = observation.currency
        store = observation.store; branch = observation.branch; channel = observation.channel
        priceType = observation.priceType; observedAt = observation.observedAt
        isKnownProduct = observation.source != .user; purchaseQuantity = observation.purchaseQuantity
        capturedDraftID = observation.id
    }

    func makeObservation() -> Observation? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, quantityValue > 0, packCount > 0 else { return nil }
        return Observation(
            id: capturedDraftID ?? UUID(), tripID: tripID, familyID: familyID, barcode: barcode,
            name: cleanName, brand: brand.trimmingCharacters(in: .whitespacesAndNewlines),
            variant: variant.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category.trimmingCharacters(in: .whitespacesAndNewlines),
            quantityValue: quantityValue, quantityUnit: quantityUnit, packCount: packCount,
            price: price, currency: currency, store: store,
            branch: branch.trimmingCharacters(in: .whitespacesAndNewlines), channel: channel,
            priceType: priceType, source: isKnownProduct ? .bundled : .user,
            matchConfidence: isKnownProduct ? 1 : 0.7, decision: .none,
            purchaseQuantity: max(purchaseQuantity, 1), observedAt: observedAt, isDraft: false
        )
    }
}

struct StoreOption: Identifiable, Hashable, Codable, Sendable {
    static let customSentinel = "__other_supermarket__"
    enum Market: String, CaseIterable, Codable, Sendable {
        case canada = "Canada", unitedStates = "United States"
        var displayName: String { AppLocalization.text(self == .canada ? "market.canada" : "market.united_states") }
    }
    let name: String
    let market: Market
    let currency: CurrencyCode
    var id: String { "\(market.rawValue):\(name)" }
    var displayName: String { name == Self.customSentinel ? AppLocalization.text("store.other") : name }
}

struct ShoppingTrip: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var store: StoreOption
    let startedAt: Date
}

enum StoreCatalogue {
    private static let canada = ["Walmart", "Costco", "Loblaws", "Real Canadian Superstore", "No Frills", "Zehrs", "Fortinos", "Maxi", "Provigo", "Metro", "Food Basics", "Sobeys", "FreshCo", "Safeway", "Save-On-Foods", "IGA", "Co-op", "Longo’s", "Farm Boy", "Giant Tiger", "T&T Supermarket", "Shoppers Drug Mart", "London Drugs", "Whole Foods Market", "Amazon Fresh"]
    private static let unitedStates = ["Walmart", "Costco", "Kroger", "Albertsons", "Safeway", "Publix", "Aldi", "Trader Joe’s", "Target", "Whole Foods Market", "Sam’s Club", "H-E-B", "Meijer", "Wegmans", "Food Lion", "Giant Food", "Stop & Shop", "ShopRite", "Harris Teeter", "Sprouts", "WinCo", "Hy-Vee", "Jewel-Osco", "Ralphs", "Vons", "Acme", "Shaw’s", "Star Market", "Market Basket", "Piggly Wiggly", "Save A Lot", "Grocery Outlet", "BJ’s Wholesale", "Dollar General", "Family Dollar", "Walgreens", "CVS", "Amazon Fresh", "Fred Meyer", "QFC", "Mariano’s", "King Soopers", "Smith’s", "Fry’s", "Dillons", "Food 4 Less", "Raley’s", "Stater Bros.", "Gelson’s", "Central Market", "SuperMax", "Pueblo", "Econo", "Selectos"]
    static let all = make(canada, market: .canada, currency: .cad) + make(unitedStates, market: .unitedStates, currency: .usd)
    private static func make(_ names: [String], market: StoreOption.Market, currency: CurrencyCode) -> [StoreOption] {
        (names + [StoreOption.customSentinel]).map { StoreOption(name: $0, market: market, currency: currency) }
    }
}

enum ComparisonStatus: String, CaseIterable, Identifiable, Hashable, Sendable {
    case capturedDraft, baseline, packageChange, shrinkflation, moreExpensive, betterValue, unchanged
    var id: String { rawValue }
    var title: String { AppLocalization.text("status.\(rawValue)") }
}

struct ComparisonResult: Identifiable, Hashable, Sendable {
    var id: UUID { current.id }
    let current: Observation
    let previous: Observation?
    let sizeChange: Double?
    let priceChange: Double?
    let unitPriceChange: Double?
    let priceIsComparable: Bool
    var isBaseline: Bool { previous == nil && !current.isDraft }
    var status: ComparisonStatus {
        if current.isDraft { return .capturedDraft }
        guard previous != nil, let sizeChange else { return .baseline }
        if sizeChange < -0.005 && !priceIsComparable { return .packageChange }
        guard let unitPriceChange else {
            return abs(sizeChange) <= 0.005 ? .unchanged : (sizeChange < 0 ? .packageChange : .betterValue)
        }
        if sizeChange < -0.005 && unitPriceChange > 0.005 { return .shrinkflation }
        if unitPriceChange > 0.005 { return .moreExpensive }
        if unitPriceChange < -0.005 || sizeChange > 0.005 { return .betterValue }
        return .unchanged
    }
    var extraCostPerPack: Decimal? {
        guard priceIsComparable, let previous, let currentPrice = current.price,
              let previousPrice = previous.price, previous.normalizedQuantity > 0 else { return nil }
        let expected = NSDecimalNumber(decimal: previousPrice).doubleValue * current.normalizedQuantity / previous.normalizedQuantity
        let extra = NSDecimalNumber(decimal: currentPrice).doubleValue - expected
        return extra > 0 ? Decimal(extra) : nil
    }
}

enum ComparisonEngine {
    static func compare(current: Observation, previous: Observation?) -> ComparisonResult {
        guard !current.isDraft, let previous, !previous.isDraft,
              previous.normalizedUnit == current.normalizedUnit,
              previous.normalizedQuantity > 0, current.normalizedQuantity > 0 else {
            return ComparisonResult(current: current, previous: nil, sizeChange: nil, priceChange: nil, unitPriceChange: nil, priceIsComparable: false)
        }
        let sizeChange = current.normalizedQuantity / previous.normalizedQuantity - 1
        let sameBranch = previous.branch.isEmpty || current.branch.isEmpty || previous.branch.caseInsensitiveCompare(current.branch) == .orderedSame
        let comparable = previous.store.caseInsensitiveCompare(current.store) == .orderedSame
            && previous.currency == current.currency && previous.channel == current.channel
            && previous.priceType == current.priceType && sameBranch
            && previous.price != nil && current.price != nil
        guard comparable, let previousPrice = previous.price, let currentPrice = current.price,
              previousPrice > 0, currentPrice > 0 else {
            return ComparisonResult(current: current, previous: previous, sizeChange: sizeChange, priceChange: nil, unitPriceChange: nil, priceIsComparable: false)
        }
        let oldPrice = NSDecimalNumber(decimal: previousPrice).doubleValue
        let newPrice = NSDecimalNumber(decimal: currentPrice).doubleValue
        let oldUnitPrice = oldPrice / previous.normalizedQuantity
        let newUnitPrice = newPrice / current.normalizedQuantity
        return ComparisonResult(current: current, previous: previous, sizeChange: sizeChange,
                                priceChange: newPrice / oldPrice - 1,
                                unitPriceChange: newUnitPrice / oldUnitPrice - 1,
                                priceIsComparable: true)
    }
}

struct ImpactSummary: Hashable, Sendable {
    var protected: Decimal = 0
    var cost: Decimal = 0
    var scoredBouts = 0
    var unscoredEvidence = 0
    var productsCaught = 0
}

enum HistoryRange: String, CaseIterable, Identifiable, Hashable, Sendable {
    case sevenDays, thirtyDays, allTime
    var id: String { rawValue }
    var title: String { AppLocalization.text("filter.\(rawValue)") }
    var startDate: Date? {
        switch self {
        case .sevenDays: Calendar.current.date(byAdding: .day, value: -7, to: .now)
        case .thirtyDays: Calendar.current.date(byAdding: .day, value: -30, to: .now)
        case .allTime: nil
        }
    }
}

struct HistoryFilter: Equatable, Sendable {
    var range: HistoryRange = .allTime
    var status: ComparisonStatus?
    var category = ""
    var store = ""
    func includes(_ result: ComparisonResult) -> Bool {
        if let start = range.startDate, result.current.observedAt < start { return false }
        if let status, result.status != status { return false }
        if !category.isEmpty && result.current.category.caseInsensitiveCompare(category) != .orderedSame { return false }
        if !store.isEmpty && result.current.store.caseInsensitiveCompare(store) != .orderedSame { return false }
        return true
    }
}

enum BarcodeNormalizer {
    enum Kind: Equatable, Sendable { case upce, ean8, other }
    static func normalize(_ raw: String, kind: Kind? = nil) -> String? {
        let digits = raw.filter(\.isNumber)
        let expanded: String
        switch digits.count {
        case 8:
            guard isValidGTIN(digits) else { return nil }
            let treatAsUPCE = kind == .upce || (kind == nil && (digits.first == "0" || digits.first == "1"))
            if treatAsUPCE { guard let upca = expandUPCE(digits) else { return nil }; expanded = "00" + upca }
            else { expanded = String(repeating: "0", count: 6) + digits }
        case 12: guard isValidGTIN(digits) else { return nil }; expanded = "00" + digits
        case 13: guard isValidGTIN(digits) else { return nil }; expanded = "0" + digits
        case 14: guard isValidGTIN(digits) else { return nil }; expanded = digits
        default: return nil
        }
        return expanded
    }
    static func isValidGTIN(_ digits: String) -> Bool {
        guard [8, 12, 13, 14].contains(digits.count), digits.allSatisfy(\.isNumber), let expected = digits.last?.wholeNumberValue else { return false }
        let sum = digits.dropLast().reversed().enumerated().reduce(0) { $0 + ($1.element.wholeNumberValue ?? 0) * ($1.offset.isMultiple(of: 2) ? 3 : 1) }
        return (10 - (sum % 10)) % 10 == expected
    }
    private static func expandUPCE(_ digits: String) -> String? {
        let v = digits.compactMap(\.wholeNumberValue); guard v.count == 8 else { return nil }
        let manufacturer: [Int], product: [Int]
        switch v[6] {
        case 0, 1, 2: manufacturer = [v[1], v[2], v[6], 0, 0]; product = [0, 0, v[3], v[4], v[5]]
        case 3: manufacturer = [v[1], v[2], v[3], 0, 0]; product = [0, 0, 0, v[4], v[5]]
        case 4: manufacturer = [v[1], v[2], v[3], v[4], 0]; product = [0, 0, 0, 0, v[5]]
        default: manufacturer = [v[1], v[2], v[3], v[4], v[5]]; product = [0, 0, 0, 0, v[6]]
        }
        return ([v[0]] + manufacturer + product + [v[7]]).map(String.init).joined()
    }
}
