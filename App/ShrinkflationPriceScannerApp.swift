import SwiftUI

@main
struct ShrinkflationPriceScannerApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            Group {
                if environment.isReady {
                    ContentView()
                } else {
                    ProgressView(AppLocalization.text("app.preparing"))
                        .accessibilityLabel(AppLocalization.text("app.preparing"))
                }
            }
            .environmentObject(environment)
            .tint(.blue)
            .task { await environment.start() }
        }
    }
}

@MainActor
final class AppEnvironment: ObservableObject {
    @Published private(set) var recentComparisons: [ComparisonResult] = []
    @Published private(set) var recentProducts: [ProductRecord] = []
    @Published private(set) var activeTrip: ShoppingTrip?
    @Published private(set) var lastDeletedObservation: Observation?
    @Published var historyFilter = HistoryFilter()
    @Published var errorMessage: String?
    @Published private(set) var isReady = false

    let purchaseManager = PurchaseManager()
    let adManager = AdManager()
    private var repository: LocalRepository?
    private var repositoryInitializationError: String?

    init() {
        UserDefaults.standard.removeObject(forKey: "preferredMarket")
        UserDefaults.standard.removeObject(forKey: "preferredCurrency")
        if let data = UserDefaults.standard.data(forKey: "activeShoppingTrip"),
           let saved = try? JSONDecoder().decode(ShoppingTrip.self, from: data),
           Calendar.current.isDateInToday(saved.startedAt) {
            activeTrip = saved
        } else {
            UserDefaults.standard.removeObject(forKey: "activeShoppingTrip")
        }
        do {
            repository = try LocalRepository()
            refresh()
        } catch {
            repositoryInitializationError = error.localizedDescription
            errorMessage = repositoryInitializationError
        }
    }

    func start() async {
        await purchaseManager.resolveEntitlement()
        isReady = true
        await Task.yield()
        await purchaseManager.loadProductMetadata()
        if !purchaseManager.hasRemovedAds { await adManager.prepareAds() }
    }

    func product(for barcode: String) -> ProductRecord? {
        guard let repository = availableRepository() else { return nil }
        errorMessage = nil
        do {
            return try repository.lookup(barcode: barcode)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func save(_ draft: ObservationDraft) -> ComparisonResult? {
        guard let observation = draft.makeObservation() else { return nil }
        guard let repository = availableRepository() else { return nil }
        do {
            let result = try repository.save(observation)
            UserDefaults.standard.set(observation.store, forKey: "lastStore")
            refresh()
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func link(_ draft: inout ObservationDraft, to product: ProductRecord) {
        draft.familyID = product.familyID
        draft.isKnownProduct = true
        draft.source = .learned
        if draft.name.isEmpty { draft.name = product.name }
        if draft.brand.isEmpty { draft.brand = product.brand }
        if draft.variant.isEmpty { draft.variant = product.variant }
    }

    @discardableResult
    func delete(_ result: ComparisonResult) -> Bool {
        guard let repository = availableRepository() else { return false }
        do {
            try repository.deleteObservation(id: result.current.id)
            lastDeletedObservation = result.current
            refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func undoDelete() {
        guard let observation = lastDeletedObservation else { return }
        guard let repository = availableRepository() else { return }
        do {
            try repository.restore(observation)
            lastDeletedObservation = nil
            refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func expireUndo() { lastDeletedObservation = nil }

    func updateDecision(for result: ComparisonResult, decision: PurchaseDecision, quantity: Int) {
        guard let repository = availableRepository() else { return }
        do {
            try repository.updateDecision(id: result.current.id, decision: decision, quantity: quantity)
            refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteAllData() {
        guard let repository = availableRepository() else { return }
        do {
            try repository.deleteAllUserData()
            activeTrip = nil
            lastDeletedObservation = nil
            persistTrip()
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() {
        guard let repository = availableRepository() else { return }
        do {
            recentComparisons = try repository.recentComparisons()
            recentProducts = try repository.recentProducts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var defaultStore: String {
        activeTrip?.store.name ?? UserDefaults.standard.string(forKey: "lastStore") ?? ""
    }

    func startTrip(at store: StoreOption) {
        activeTrip = ShoppingTrip(id: UUID(), store: store, startedAt: .now)
        persistTrip()
    }

    func changeTripStore(to store: StoreOption) { startTrip(at: store) }

    func finishTrip() {
        activeTrip = nil
        persistTrip()
    }

    private func persistTrip() {
        guard let activeTrip else {
            UserDefaults.standard.removeObject(forKey: "activeShoppingTrip")
            return
        }
        do {
            let data = try JSONEncoder().encode(activeTrip)
            UserDefaults.standard.set(data, forKey: "activeShoppingTrip")
        } catch {
            errorMessage = AppLocalization.text("error.database_save", error.localizedDescription)
        }
    }

    private func availableRepository() -> LocalRepository? {
        guard let repository else {
            errorMessage = repositoryInitializationError
                ?? AppLocalization.text("error.database_open", AppLocalization.text("error.try_again"))
            return nil
        }
        return repository
    }

    func impactSummary(currency: CurrencyCode, results: [ComparisonResult]) -> ImpactSummary {
        results.reduce(into: ImpactSummary()) { summary, result in
            if result.status == .shrinkflation || result.status == .packageChange { summary.productsCaught += 1 }
            guard result.current.currency == currency,
                  let extra = result.extraCostPerPack,
                  result.current.decision != .none else {
                if result.status == .shrinkflation || result.status == .packageChange { summary.unscoredEvidence += 1 }
                return
            }
            let weighted = extra * Decimal(result.current.purchaseQuantity)
            switch result.current.decision {
            case .bought: summary.cost += weighted
            case .skipped, .switched: summary.protected += weighted
            case .none: break
            }
            summary.scoredBouts += 1
        }
    }
}
