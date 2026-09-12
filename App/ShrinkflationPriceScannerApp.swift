import SwiftUI

@main
struct ShrinkflationPriceScannerApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            ContentView()
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

    let purchaseManager = PurchaseManager()
    let adManager = AdManager()
    private var repository: LocalRepository?

    init() {
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
            errorMessage = error.localizedDescription
        }
    }

    func start() async {
        await purchaseManager.start()
        guard !purchaseManager.hasRemovedAds else { return }
        await adManager.prepareAds()
    }

    func product(for barcode: String) -> ProductRecord? {
        guard let repository else { return nil }
        do {
            return try repository.lookup(barcode: barcode)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func save(_ draft: ObservationDraft) -> ComparisonResult? {
        guard let repository, let observation = draft.makeObservation() else { return nil }
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

    func captureDraft(barcode: String) -> UUID? {
        guard let repository, let activeTrip else { return nil }
        do {
            let id = try repository.captureDraft(barcode: barcode, trip: activeTrip)
            refresh()
            return id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func link(_ draft: inout ObservationDraft, to product: ProductRecord) {
        draft.familyID = product.familyID
        if draft.name.isEmpty { draft.name = product.name }
        if draft.brand.isEmpty { draft.brand = product.brand }
        if draft.variant.isEmpty { draft.variant = product.variant }
    }

    func delete(_ result: ComparisonResult) {
        guard let repository else { return }
        do {
            try repository.deleteObservation(id: result.current.id)
            lastDeletedObservation = result.current
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func undoDelete() {
        guard let repository, let observation = lastDeletedObservation else { return }
        do {
            try repository.restore(observation)
            lastDeletedObservation = nil
            refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func updateDecision(for result: ComparisonResult, decision: PurchaseDecision, quantity: Int) {
        guard let repository else { return }
        do {
            try repository.updateDecision(id: result.current.id, decision: decision, quantity: quantity)
            refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteAllData() {
        guard let repository else { return }
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
        guard let repository else { return }
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
        if let data = try? JSONEncoder().encode(activeTrip) {
            UserDefaults.standard.set(data, forKey: "activeShoppingTrip")
        }
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
