import Foundation
import SQLite3

enum DatabaseError: LocalizedError {
    case missingCatalogue, openFailed(String), prepareFailed(String), executionFailed(String)
    var errorDescription: String? {
        switch self {
        case .missingCatalogue: AppLocalization.text("error.catalogue_missing")
        case .openFailed(let message): AppLocalization.text("error.database_open", message)
        case .prepareFailed(let message): AppLocalization.text("error.database_prepare", message)
        case .executionFailed(let message): AppLocalization.text("error.database_save", message)
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class SQLiteConnection {
    private var handle: OpaquePointer?
    init(url: URL, readOnly: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX : SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(url.path, &handle, flags, nil) != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? AppLocalization.text("error.unknown")
            sqlite3_close(handle); handle = nil
            throw DatabaseError.openFailed(message)
        }
        sqlite3_busy_timeout(handle, 2_000)
    }
    deinit { sqlite3_close(handle) }
    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? lastError
            sqlite3_free(error); throw DatabaseError.executionFailed(message)
        }
    }
    func statement(_ sql: String) throws -> SQLiteStatement {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DatabaseError.prepareFailed(lastError)
        }
        return SQLiteStatement(connection: self, handle: statement)
    }
    fileprivate var lastError: String { handle.map { String(cString: sqlite3_errmsg($0)) } ?? AppLocalization.text("error.sqlite_unknown") }
}

final class SQLiteStatement {
    private unowned let connection: SQLiteConnection
    private let handle: OpaquePointer
    fileprivate init(connection: SQLiteConnection, handle: OpaquePointer) { self.connection = connection; self.handle = handle }
    deinit { sqlite3_finalize(handle) }
    func bind(_ value: String, at index: Int32) { sqlite3_bind_text(handle, index, value, -1, sqliteTransient) }
    func bind(_ value: Double, at index: Int32) { sqlite3_bind_double(handle, index, value) }
    func bind(_ value: Int, at index: Int32) { sqlite3_bind_int(handle, index, Int32(value)) }
    @discardableResult func step() throws -> Bool {
        switch sqlite3_step(handle) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw DatabaseError.executionFailed(connection.lastError)
        }
    }
    func text(_ index: Int32) -> String {
        guard let value = sqlite3_column_text(handle, index) else { return "" }
        return String(cString: value)
    }
    func double(_ index: Int32) -> Double { sqlite3_column_double(handle, index) }
    func int(_ index: Int32) -> Int { Int(sqlite3_column_int(handle, index)) }
}

@MainActor
final class LocalRepository {
    private let catalogue: SQLiteConnection
    private let user: SQLiteConnection

    init(bundle: Bundle = .main, fileManager: FileManager = .default) throws {
        guard let catalogueURL = bundle.url(forResource: "catalogue", withExtension: "sqlite3") else { throw DatabaseError.missingCatalogue }
        catalogue = try SQLiteConnection(url: catalogueURL, readOnly: true)
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ShrinkflationPriceScanner", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        user = try SQLiteConnection(url: support.appendingPathComponent("user.sqlite3"))
        try createUserSchema()
    }

    private func createUserSchema() throws {
        try user.execute("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")
        try user.execute("""
            CREATE TABLE IF NOT EXISTS learned_products (
                barcode TEXT PRIMARY KEY NOT NULL, family_id TEXT NOT NULL,
                source_barcode TEXT NOT NULL DEFAULT '', source_barcode_length INTEGER NOT NULL DEFAULT 0,
                product_name TEXT NOT NULL, brand TEXT NOT NULL DEFAULT '', variant TEXT NOT NULL DEFAULT '',
                quantity_value REAL NOT NULL, quantity_unit TEXT NOT NULL, pack_count INTEGER NOT NULL DEFAULT 1,
                category TEXT NOT NULL DEFAULT '', updated_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_learned_family ON learned_products(family_id);
            CREATE TABLE IF NOT EXISTS observations (
                id TEXT PRIMARY KEY NOT NULL, family_id TEXT NOT NULL, barcode TEXT NOT NULL,
                product_name TEXT NOT NULL, brand TEXT NOT NULL DEFAULT '', variant TEXT NOT NULL DEFAULT '',
                quantity_value REAL NOT NULL, quantity_unit TEXT NOT NULL, pack_count INTEGER NOT NULL DEFAULT 1,
                price TEXT NOT NULL, currency TEXT NOT NULL, store TEXT NOT NULL DEFAULT '', observed_at REAL NOT NULL
            );
            """)
        let migrations: [(String, String)] = [
            ("trip_id", "TEXT NOT NULL DEFAULT ''"), ("category", "TEXT NOT NULL DEFAULT ''"),
            ("branch", "TEXT NOT NULL DEFAULT ''"), ("channel", "TEXT NOT NULL DEFAULT 'inStore'"),
            ("price_type", "TEXT NOT NULL DEFAULT 'regular'"), ("source", "TEXT NOT NULL DEFAULT 'user'"),
            ("match_confidence", "REAL NOT NULL DEFAULT 1"), ("decision", "TEXT NOT NULL DEFAULT 'none'"),
            ("purchase_quantity", "INTEGER NOT NULL DEFAULT 1"), ("is_draft", "INTEGER NOT NULL DEFAULT 0"),
            ("source_barcode", "TEXT NOT NULL DEFAULT ''"), ("source_barcode_length", "INTEGER NOT NULL DEFAULT 0")
        ]
        let columns = try tableColumns("observations")
        for (name, declaration) in migrations where !columns.contains(name) {
            try user.execute("ALTER TABLE observations ADD COLUMN \(name) \(declaration);")
        }
        let learnedMigrations: [(String, String)] = [
            ("source_barcode", "TEXT NOT NULL DEFAULT ''"),
            ("source_barcode_length", "INTEGER NOT NULL DEFAULT 0")
        ]
        let learnedColumns = try tableColumns("learned_products")
        for (name, declaration) in learnedMigrations where !learnedColumns.contains(name) {
            try user.execute("ALTER TABLE learned_products ADD COLUMN \(name) \(declaration);")
        }
        try user.execute("""
            CREATE INDEX IF NOT EXISTS idx_observations_family_date ON observations(family_id, observed_at DESC);
            CREATE INDEX IF NOT EXISTS idx_observations_trip ON observations(trip_id, observed_at DESC);
            CREATE INDEX IF NOT EXISTS idx_observations_store ON observations(store COLLATE NOCASE, observed_at DESC);
            DELETE FROM observations WHERE currency <> 'USD' OR is_draft = 1;
            PRAGMA user_version=4;
            """)
    }

    private func tableColumns(_ table: String) throws -> Set<String> {
        let statement = try user.statement("PRAGMA table_info(\(table));")
        var names = Set<String>()
        while try statement.step() { names.insert(statement.text(1)) }
        return names
    }

    func lookup(barcode raw: String) throws -> ProductRecord? {
        guard let gtin = BarcodeNormalizer.normalize(raw) else { return nil }
        let statement = try catalogue.statement("""
            SELECT gtin14, original_gtin, original_gtin_length, usda_fdc_id,
                   source_description, product_name, family_id, brand, category, data_source,
                   publication_date, modified_date, available_date, discontinued_date, market_country
            FROM products WHERE gtin14 = ? LIMIT 1;
            """)
        statement.bind(gtin, at: 1)
        if try statement.step() {
            return ProductRecord(
                barcode: statement.text(0), familyID: statement.text(6), name: statement.text(5),
                brand: statement.text(7), variant: "", quantityValue: 0, quantityUnit: .gram,
                packCount: 1, category: statement.text(8), market: statement.text(14), source: .bundled,
                originalBarcode: statement.text(1), originalBarcodeLength: statement.int(2),
                sourceID: statement.text(3), sourceDescription: statement.text(4),
                dataSource: statement.text(9), publicationDate: statement.text(10),
                modifiedDate: statement.text(11), availableDate: statement.text(12),
                discontinuedDate: statement.text(13)
            )
        }
        return try lookupLearned(gtin: gtin)
    }

    private func lookupLearned(gtin: String) throws -> ProductRecord? {
        let statement = try user.statement("""
            SELECT barcode, family_id, source_barcode, source_barcode_length,
                   product_name, brand, variant, quantity_value, quantity_unit, pack_count, category
            FROM learned_products WHERE barcode = ? LIMIT 1;
            """)
        statement.bind(gtin, at: 1)
        guard try statement.step(), let unit = QuantityUnit.parse(statement.text(8)) else { return nil }
        return ProductRecord(barcode: statement.text(0), familyID: statement.text(1), name: statement.text(4),
                             brand: statement.text(5), variant: statement.text(6), quantityValue: statement.double(7),
                             quantityUnit: unit, packCount: max(statement.int(9), 1), category: statement.text(10),
                             market: "US", source: .learned, originalBarcode: statement.text(2),
                             originalBarcodeLength: statement.int(3))
    }

    func save(_ observation: Observation) throws -> ComparisonResult {
        let previous = try latestComparableFamilyObservation(for: observation, before: observation.observedAt)
        try user.execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            if observation.source != .bundled, BarcodeNormalizer.normalize(observation.barcode) != nil {
                try upsertLearnedProduct(from: observation)
            }
            try insertObservation(observation, replacing: true)
            try user.execute("COMMIT;")
        } catch { try? user.execute("ROLLBACK;"); throw error }
        return ComparisonEngine.compare(current: observation, previous: previous)
    }

    func restore(_ observation: Observation) throws { try insertObservation(observation, replacing: true) }

    private func upsertLearnedProduct(from observation: Observation) throws {
        let statement = try user.statement("""
            INSERT INTO learned_products (barcode, family_id, source_barcode, source_barcode_length, product_name, brand, variant, quantity_value, quantity_unit, pack_count, category, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(barcode) DO UPDATE SET family_id=excluded.family_id, product_name=excluded.product_name,
                source_barcode=excluded.source_barcode, source_barcode_length=excluded.source_barcode_length,
                brand=excluded.brand, variant=excluded.variant, quantity_value=excluded.quantity_value,
                quantity_unit=excluded.quantity_unit, pack_count=excluded.pack_count,
                category=excluded.category, updated_at=excluded.updated_at;
            """)
        let values: [(String, Int32)] = [
            (observation.barcode,1),(observation.familyID,2),(observation.sourceBarcode,3),
            (observation.name,5),(observation.brand,6),(observation.variant,7)
        ]
        values.forEach { statement.bind($0.0, at: $0.1) }
        statement.bind(observation.sourceBarcodeLength, at: 4)
        statement.bind(observation.quantityValue, at: 8); statement.bind(observation.quantityUnit.rawValue, at: 9)
        statement.bind(observation.packCount, at: 10); statement.bind(observation.category, at: 11)
        statement.bind(observation.observedAt.timeIntervalSince1970, at: 12); _ = try statement.step()
    }

    private func insertObservation(_ observation: Observation, replacing: Bool = false) throws {
        let statement = try user.statement("""
            INSERT \(replacing ? "OR REPLACE " : "")INTO observations (
                id, family_id, barcode, product_name, brand, variant, quantity_value, quantity_unit,
                pack_count, price, currency, store, observed_at, trip_id, category, branch, channel,
                price_type, source, match_confidence, decision, purchase_quantity, is_draft,
                source_barcode, source_barcode_length
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        let textValues: [(String, Int32)] = [
            (observation.id.uuidString,1),(observation.familyID,2),(observation.barcode,3),(observation.name,4),
            (observation.brand,5),(observation.variant,6),(observation.quantityUnit.rawValue,8),
            (observation.price.map { NSDecimalNumber(decimal: $0).stringValue } ?? "",10),
            (observation.currency.rawValue,11),(observation.store,12),(observation.tripID.uuidString,14),
            (observation.category,15),(observation.branch,16),(observation.channel.rawValue,17),
            (observation.priceType.rawValue,18),(observation.source.rawValue,19),(observation.decision.rawValue,21),
            (observation.sourceBarcode,24)
        ]
        textValues.forEach { statement.bind($0.0, at: $0.1) }
        statement.bind(observation.quantityValue, at: 7); statement.bind(observation.packCount, at: 9)
        statement.bind(observation.observedAt.timeIntervalSince1970, at: 13)
        statement.bind(observation.matchConfidence, at: 20); statement.bind(observation.purchaseQuantity, at: 22)
        statement.bind(observation.isDraft ? 1 : 0, at: 23)
        statement.bind(observation.sourceBarcodeLength, at: 25); _ = try statement.step()
    }

    private static let observationColumns = """
        id, family_id, barcode, product_name, brand, variant, quantity_value, quantity_unit, pack_count,
        price, currency, store, observed_at, trip_id, category, branch, channel, price_type, source,
        match_confidence, decision, purchase_quantity, is_draft, source_barcode, source_barcode_length
        """

    private func latestComparableFamilyObservation(for current: Observation, before date: Date) throws -> Observation? {
        let statement = try user.statement("""
            SELECT \(Self.observationColumns) FROM observations
            WHERE family_id = ? AND trip_id != ? AND observed_at <= ? AND is_draft = 0
            ORDER BY observed_at DESC;
            """)
        statement.bind(current.familyID, at: 1); statement.bind(current.tripID.uuidString, at: 2)
        statement.bind(date.timeIntervalSince1970, at: 3)
        var newestCrossStore: Observation?
        while try statement.step() {
            guard let candidate = decodeObservation(statement), candidate.normalizedUnit == current.normalizedUnit else { continue }
            if newestCrossStore == nil { newestCrossStore = candidate }
            let sameRetailContext = candidate.store.caseInsensitiveCompare(current.store) == .orderedSame
                && candidate.currency == current.currency && candidate.channel == current.channel
                && candidate.priceType == current.priceType
            if sameRetailContext { return candidate }
        }
        return newestCrossStore
    }

    func recentComparisons() throws -> [ComparisonResult] {
        let statement = try user.statement("SELECT \(Self.observationColumns) FROM observations WHERE is_draft = 0 ORDER BY observed_at DESC, rowid DESC;")
        var observations: [Observation] = []
        while try statement.step() { if let value = decodeObservation(statement) { observations.append(value) } }
        var results: [ComparisonResult] = []
        for (index, current) in observations.enumerated() {
            let candidates = observations.dropFirst(index + 1).filter {
                !$0.isDraft && $0.familyID == current.familyID && $0.tripID != current.tripID && $0.normalizedUnit == current.normalizedUnit
            }
            let previous = candidates.first {
                $0.store.caseInsensitiveCompare(current.store) == .orderedSame
                    && $0.currency == current.currency && $0.channel == current.channel && $0.priceType == current.priceType
            } ?? candidates.first
            results.append(ComparisonEngine.compare(current: current, previous: previous))
        }
        return results
    }

    func recentProducts() throws -> [ProductRecord] {
        let statement = try user.statement("""
            SELECT current.barcode, current.family_id, current.source_barcode, current.source_barcode_length,
                   current.product_name, current.brand, current.variant, current.quantity_value,
                   current.quantity_unit, current.pack_count, current.category, current.source
            FROM observations AS current
            WHERE current.is_draft = 0
              AND NOT EXISTS (
                  SELECT 1 FROM observations AS newer
                  WHERE newer.is_draft = 0
                    AND newer.family_id = current.family_id
                    AND (
                        newer.observed_at > current.observed_at
                        OR (newer.observed_at = current.observed_at AND newer.rowid > current.rowid)
                    )
              )
            ORDER BY current.observed_at DESC, current.rowid DESC;
            """)
        var products: [ProductRecord] = []
        while try statement.step() {
            guard let unit = QuantityUnit.parse(statement.text(8)) else { continue }
            products.append(ProductRecord(barcode: statement.text(0), familyID: statement.text(1), name: statement.text(4),
                                          brand: statement.text(5), variant: statement.text(6), quantityValue: statement.double(7),
                                          quantityUnit: unit, packCount: max(statement.int(9),1), category: statement.text(10),
                                          market: "US", source: ProductSource(rawValue: statement.text(11)) ?? .user,
                                          originalBarcode: statement.text(2),
                                          originalBarcodeLength: statement.int(3)))
        }
        return products
    }

    func updateDecision(id: UUID, decision: PurchaseDecision, quantity: Int) throws {
        let statement = try user.statement("UPDATE observations SET decision = ?, purchase_quantity = ? WHERE id = ?;")
        statement.bind(decision.rawValue, at: 1); statement.bind(max(quantity,1), at: 2); statement.bind(id.uuidString, at: 3)
        _ = try statement.step()
    }
    func deleteObservation(id: UUID) throws {
        let statement = try user.statement("DELETE FROM observations WHERE id = ?;")
        statement.bind(id.uuidString, at: 1); _ = try statement.step()
    }
    func deleteAllUserData() throws {
        try user.execute("BEGIN IMMEDIATE TRANSACTION;")
        do { try user.execute("DELETE FROM observations; DELETE FROM learned_products; COMMIT;") }
        catch { try? user.execute("ROLLBACK;"); throw error }
    }

    private func decodeObservation(_ s: SQLiteStatement) -> Observation? {
        guard let id = UUID(uuidString: s.text(0)), let unit = QuantityUnit.parse(s.text(7)) else { return nil }
        let currency = CurrencyCode(rawValue: s.text(10)) ?? .usd
        return Observation(
            id: id, tripID: UUID(uuidString: s.text(13)) ?? UUID(), familyID: s.text(1), barcode: s.text(2),
            sourceBarcode: s.text(23), sourceBarcodeLength: s.int(24),
            name: s.text(3), brand: s.text(4), variant: s.text(5), category: s.text(14),
            quantityValue: s.double(6), quantityUnit: unit, packCount: max(s.int(8),1),
            price: Decimal(string: s.text(9), locale: Locale(identifier: "en_US_POSIX")),
            currency: currency, store: s.text(11), branch: s.text(15),
            channel: SalesChannel(rawValue: s.text(16)) ?? .inStore,
            priceType: PriceType(rawValue: s.text(17)) ?? .regular,
            source: ProductSource(rawValue: s.text(18)) ?? .user,
            matchConfidence: s.double(19), decision: PurchaseDecision(rawValue: s.text(20)) ?? .none,
            purchaseQuantity: max(s.int(21),1), observedAt: Date(timeIntervalSince1970: s.double(12)), isDraft: s.int(22) == 1
        )
    }
}
