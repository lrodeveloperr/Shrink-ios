import Charts
import SwiftUI

private enum RootTab: Hashable { case scan, history, impact }

struct ContentView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var tab: RootTab = .scan

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $tab) {
                NavigationStack { ScanHomeView() }
                    .tabItem { Label(AppLocalization.text("tab.scan"), systemImage: "barcode.viewfinder") }
                    .tag(RootTab.scan)
                NavigationStack { HistoryView() }
                    .tabItem { Label(AppLocalization.text("tab.history"), systemImage: "clock") }
                    .tag(RootTab.history)
                NavigationStack { ImpactView() }
                    .tabItem { Label(AppLocalization.text("tab.impact"), systemImage: "chart.bar.xaxis") }
                    .tag(RootTab.impact)
            }
            if !environment.purchaseManager.hasRemovedAds {
                Color.clear.frame(height: 8)
                PersistentAdStrip(purchaseManager: environment.purchaseManager, adManager: environment.adManager)
            }
        }
        .alert(AppLocalization.text("Something went wrong"), isPresented: Binding(
            get: { environment.errorMessage != nil },
            set: { if !$0 { environment.errorMessage = nil } }
        )) {
            Button(AppLocalization.text("OK")) { environment.errorMessage = nil }
        } message: {
            Text(environment.errorMessage ?? AppLocalization.text("error.try_again"))
        }
    }
}

private struct PremiumSurface<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(18)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.primary.opacity(0.07)) }
            .shadow(color: .black.opacity(0.045), radius: 16, y: 7)
    }
}

private struct ScanHomeView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showingStorePicker = false
    @State private var showingScanner = false
    @State private var showingManual = false
    @State private var showingSettings = false
    @State private var draft: ObservationDraft?
    @State private var result: ComparisonResult?
    @State private var scanMessage: String?

    private var tripResults: [ComparisonResult] {
        guard let trip = environment.activeTrip else { return [] }
        return environment.recentComparisons.filter { $0.current.tripID == trip.id }
    }

    private var caughtThisTrip: Int {
        tripResults.filter { $0.status == .shrinkflation }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if environment.activeTrip == nil {
                    tripCard
                } else {
                    radarTripContext
                    radarSurface
                    manualEntryButton
                    if let latest = tripResults.first { latestResult(latest) }
                }
            }
            .frame(maxWidth: 680)
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(AppLocalization.text("tab.scan"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel(AppLocalization.text("Settings"))
            }
        }
        .sheet(isPresented: $showingSettings) { NavigationStack { SettingsView() } }
        .sheet(isPresented: $showingStorePicker) {
            StorePickerView { store in
                environment.startTrip(at: store)
                showingStorePicker = false
            }
        }
        .fullScreenCover(isPresented: $showingScanner) {
            NavigationStack {
                BarcodeScannerView { barcode, kind in
                    guard let normalized = BarcodeNormalizer.normalizeWithMetadata(barcode, kind: kind) else {
                        scanMessage = AppLocalization.text("scanner.invalid_barcode")
                        showingScanner = false
                        return
                    }
                    guard let trip = environment.activeTrip else { return }
                    let product = environment.product(for: normalized.gtin14)
                    guard environment.errorMessage == nil else {
                        showingScanner = false
                        return
                    }
                    let next = ObservationDraft(
                        barcode: normalized.gtin14,
                        sourceBarcode: normalized.sourceDigits,
                        sourceBarcodeLength: normalized.sourceLength,
                        product: product,
                        trip: trip
                    )
                    draft = next
                    showingScanner = false
                } onError: { scanMessage = $0 } onManual: {
                    showingScanner = false
                    DispatchQueue.main.async { showingManual = true }
                }
                .ignoresSafeArea()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(AppLocalization.text("Cancel")) { showingScanner = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showingManual) {
            ManualStartView { barcode, barcodeKind in
                guard let trip = environment.activeTrip else { return }
                let normalized = barcode.flatMap { BarcodeNormalizer.normalizeWithMetadata($0, kind: barcodeKind) }
                let product = normalized.flatMap { environment.product(for: $0.gtin14) }
                guard environment.errorMessage == nil else { return }
                let next = ObservationDraft(
                    barcode: normalized?.gtin14 ?? "manual:\(UUID().uuidString)",
                    sourceBarcode: normalized?.sourceDigits,
                    sourceBarcodeLength: normalized?.sourceLength,
                    product: product,
                    trip: trip
                )
                draft = next
                showingManual = false
            }
        }
        .sheet(item: $draft) { value in
            ProductEntryView(initialDraft: value) { completed in
                guard let saved = environment.save(completed) else { return false }
                result = saved
                draft = nil
                return true
            }
        }
        .sheet(item: $result) { ComparisonDetailView(result: $0) }
        .alert(AppLocalization.text("scanner.problem"), isPresented: Binding(
            get: { scanMessage != nil },
            set: { if !$0 { scanMessage = nil } }
        )) {
            Button(AppLocalization.text("OK")) { scanMessage = nil }
        } message: {
            Text(scanMessage ?? AppLocalization.text("error.try_again"))
        }
    }

    private var radarTripContext: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.blue.opacity(0.11))
                        .frame(width: 44, height: 44)
                    Image(systemName: "basket.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(environment.activeTrip?.store.name ?? "")
                        .font(.headline)
                        .lineLimit(1)
                    if let date = environment.activeTrip?.startedAt {
                        Text(date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Button(AppLocalization.text("Change")) { showingStorePicker = true }
                    .font(.subheadline.weight(.semibold))
            }
            Divider()
            Button(AppLocalization.text("Finish trip")) { environment.finishTrip() }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var radarSurface: some View {
        PremiumSurface {
            VStack(spacing: 14) {
                Button { showingScanner = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.title2.weight(.semibold))
                        Text(AppLocalization.text("Scan product"))
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityLabel(AppLocalization.text("Scan product"))

                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.blue)
                    Text(AppLocalization.text("radar.caught_today_format", caughtThisTrip))
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var manualEntryButton: some View {
        Button { showingManual = true } label: {
            Label(AppLocalization.text("Enter manually"), systemImage: "square.and.pencil")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func latestResult(_ latest: ComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(AppLocalization.text("radar.latest_result"))
                    .font(.headline)
                Spacer()
                Text(latest.status.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(latest.status == .shrinkflation ? Color.red : Color.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(latest.status == .shrinkflation ? Color.red.opacity(0.09) : Color.secondary.opacity(0.08), in: Capsule())
            }
            Button { result = latest } label: { ComparisonRow(result: latest) }
                .buttonStyle(.plain)
                .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.top, 2)
    }

    private var tripCard: some View {
        PremiumSurface {
            if let trip = environment.activeTrip {
                HStack(spacing: 15) {
                    ZStack {
                        Circle().fill(Color.blue.opacity(0.11)).frame(width: 54, height: 54)
                        Image(systemName: "basket.fill").font(.title2.weight(.semibold)).foregroundStyle(.blue)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(trip.store.name).font(.title3.weight(.bold)).lineLimit(1)
                        Text(trip.startedAt, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(AppLocalization.text("Change")) { showingStorePicker = true }
                        .font(.subheadline.weight(.semibold))
                }
            } else {
                VStack(spacing: 15) {
                    ZStack {
                        Circle().fill(LinearGradient(colors: [.blue.opacity(0.18), .cyan.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 66, height: 66)
                        Image(systemName: "basket.fill").font(.system(size: 28, weight: .semibold)).foregroundStyle(.blue)
                    }
                    Text(AppLocalization.text("home.choose_supermarket")).font(.title2.weight(.bold))
                    Button { showingStorePicker = true } label: {
                        Label(AppLocalization.text("Choose store"), systemImage: "magnifyingglass")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var actionCard: some View {
        PremiumSurface {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppLocalization.text("home.check_product")).font(.headline)
                        Text(AppLocalization.text("home.scan_count", tripResults.count)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "barcode.viewfinder").font(.title2).foregroundStyle(.blue)
                }
                HStack(spacing: 10) {
                    Button { showingScanner = true } label: {
                        Label(AppLocalization.text("Scan barcode"), systemImage: "barcode.viewfinder").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    Button { showingManual = true } label: {
                        Label(AppLocalization.text("Add manually"), systemImage: "square.and.pencil").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                }
                Button(AppLocalization.text("Finish trip")) { environment.finishTrip() }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
    }

    private var currentTripSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.text("This trip")).font(.headline).padding(.horizontal, 2)
            VStack(spacing: 0) {
                ForEach(tripResults.prefix(5)) { row in
                    Button { result = row } label: { ComparisonRow(result: row) }
                        .buttonStyle(.plain)
                    if row.id != tripResults.prefix(5).last?.id { Divider().padding(.leading, 62) }
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

private struct StorePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (StoreOption) -> Void
    @State private var search = ""
    @State private var showingCustomStore = false
    @State private var customStoreName = ""

    private var filtered: [StoreOption] {
        search.isEmpty ? StoreCatalogue.all : StoreCatalogue.all.filter { $0.displayName.localizedStandardContains(search) }
    }
    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { store in
                    Button {
                        if store.name == StoreOption.customSentinel { showingCustomStore = true }
                        else { onSelect(store) }
                    } label: {
                        Text(store.displayName).foregroundStyle(.primary)
                    }
                }
            }
            .searchable(text: $search, prompt: AppLocalization.text("Search stores"))
            .navigationTitle(AppLocalization.text("Choose store"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(AppLocalization.text("Cancel")) { dismiss() } } }
        }
        .alert(AppLocalization.text("Add supermarket"), isPresented: $showingCustomStore) {
            TextField(AppLocalization.text("Supermarket name"), text: $customStoreName)
            Button(AppLocalization.text("Cancel"), role: .cancel) { }
            Button(AppLocalization.text("Save")) {
                let name = customStoreName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                onSelect(StoreOption(name: name, region: .current))
            }.disabled(customStoreName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

private struct ManualStartView: View {
    private enum EightDigitFormat: String, CaseIterable, Identifiable {
        case ean8 = "EAN-8"
        case upce = "UPC-E"

        var id: String { rawValue }
        var barcodeKind: BarcodeNormalizer.Kind { self == .ean8 ? .ean8 : .upce }
    }

    @Environment(\.dismiss) private var dismiss
    let onContinue: (String?, BarcodeNormalizer.Kind?) -> Void
    @State private var barcode = ""
    @State private var eightDigitFormat: EightDigitFormat?
    @State private var validationMessage: String?

    private var trimmedBarcode: String { barcode.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var barcodeDigits: String { trimmedBarcode.filter(\.isNumber) }
    private var requiresEightDigitFormat: Bool {
        barcodeDigits.count == 8
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(AppLocalization.text("UPC, EAN or GTIN"), text: $barcode)
                        .keyboardType(.numberPad)
                        .onChange(of: barcode) { _ in
                            validationMessage = nil
                            if !requiresEightDigitFormat { eightDigitFormat = nil }
                        }
                    if requiresEightDigitFormat {
                        Picker(AppLocalization.text("manual.eight_digit_format"), selection: $eightDigitFormat) {
                            ForEach(EightDigitFormat.allCases) { format in
                                Text(format.rawValue).tag(Optional(format))
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel(AppLocalization.text("manual.eight_digit_format"))
                        .accessibilityHint(AppLocalization.text("manual.eight_digit_required"))
                        Text(AppLocalization.text("manual.eight_digit_required"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let validationMessage {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityLiveRegion(.assertive)
                    }
                }
                footer: { Text(AppLocalization.text("manual.barcode_optional")) }
            }
            .navigationTitle(AppLocalization.text("Enter manually"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppLocalization.text("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.text("Continue")) {
                        let candidate = trimmedBarcode
                        guard !candidate.isEmpty else {
                            onContinue(nil, nil)
                            return
                        }
                        let kind: BarcodeNormalizer.Kind?
                        if requiresEightDigitFormat {
                            guard let eightDigitFormat else {
                                validationMessage = AppLocalization.text("manual.eight_digit_required")
                                return
                            }
                            kind = eightDigitFormat.barcodeKind
                        } else {
                            kind = nil
                        }
                        guard BarcodeNormalizer.normalizeWithMetadata(candidate, kind: kind) != nil else {
                            validationMessage = AppLocalization.text("scanner.invalid_barcode")
                            return
                        }
                        onContinue(candidate, kind)
                    }
                    .disabled(requiresEightDigitFormat && eightDigitFormat == nil)
                }
            }
        }
    }
}

private struct ProductEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment
    @State private var draft: ObservationDraft
    @State private var showsOptional = false
    @State private var showsPricePad = false
    @State private var showsPriceScanner = false
    @State private var showsFamilyLinker = false
    let onSave: (ObservationDraft) -> Bool

    init(initialDraft: ObservationDraft, onSave: @escaping (ObservationDraft) -> Bool) {
        _draft = State(initialValue: initialDraft); self.onSave = onSave
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PremiumSurface {
                        VStack(alignment: .leading, spacing: 14) {
                            Label(draft.store, systemImage: "basket.fill").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            if !draft.isKnownProduct {
                                Label(AppLocalization.text("entry.product_not_found"), systemImage: "questionmark.barcode")
                                    .font(.headline)
                                    .foregroundStyle(.orange)
                                Text(AppLocalization.text("entry.product_not_found_detail"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Text(AppLocalization.text("entry.product_name"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if !draft.isKnownProduct {
                                TextField(AppLocalization.text("entry.product_name"), text: $draft.name)
                                    .font(.title3.weight(.semibold))
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                Text(ProductNameFormatter.compose(brand: draft.brand, name: draft.name, variant: draft.variant)).font(.title3.weight(.bold))
                            }
                            if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                validationText("entry.name_required")
                            }
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(AppLocalization.text("entry.current_quantity"))
                                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    TextField(AppLocalization.text("entry.current_quantity"), value: $draft.quantityValue, format: .number.precision(.fractionLength(0...3)))
                                        .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                                    if draft.quantityValue <= 0 { validationText("entry.quantity_required") }
                                }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(AppLocalization.text("entry.unit"))
                                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    Picker(AppLocalization.text("entry.unit"), selection: $draft.quantityUnit) {
                                        ForEach(QuantityUnit.allCases) { Text($0.localizedSymbol).tag($0) }
                                    }.pickerStyle(.menu).buttonStyle(.bordered)
                                }
                            }
                            Text(AppLocalization.text("entry.shelf_price"))
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Button { showsPricePad = true } label: {
                                HStack {
                                    Text(draft.price.map(MoneyFormatter.string) ?? AppLocalization.text("entry.add_price"))
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption)
                                }
                                .padding(11)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain)
                            if draft.price == nil || draft.price == 0 { validationText("entry.price_required") }
                            if ShelfPriceScannerView.isAvailable {
                                Button { showsPriceScanner = true } label: {
                                    Label(AppLocalization.text("Scan shelf price"), systemImage: "viewfinder")
                                }
                            }
                            Picker(AppLocalization.text("entry.decision"), selection: $draft.decision) {
                                ForEach(PurchaseDecision.allCases) { Text($0.title).tag($0) }
                            }
                            if draft.decision == .none { validationText("entry.decision_required") }
                            if !draft.isKnownProduct && !environment.recentProducts.isEmpty {
                                Button { showsFamilyLinker = true } label: {
                                    Label(AppLocalization.text("Same product, new barcode"), systemImage: "link")
                                }
                            }
                        }
                    }

                    DisclosureGroup(isExpanded: $showsOptional) {
                        VStack(spacing: 14) {
                            Picker(AppLocalization.text("entry.price_type"), selection: $draft.priceType) {
                                ForEach(PriceType.allCases) { Text($0.title).tag($0) }
                            }
                            Stepper(AppLocalization.text("entry.pack_count", draft.packCount), value: $draft.packCount, in: 1...100)
                            Stepper(AppLocalization.text("entry.how_many", draft.purchaseQuantity), value: $draft.purchaseQuantity, in: 1...100)
                            TextField(AppLocalization.text("Brand"), text: $draft.brand).textFieldStyle(.roundedBorder)
                            TextField(AppLocalization.text("entry.category"), text: $draft.category).textFieldStyle(.roundedBorder)
                            TextField(AppLocalization.text("entry.branch_optional"), text: $draft.branch).textFieldStyle(.roundedBorder)
                            Picker(AppLocalization.text("entry.channel"), selection: $draft.channel) {
                                ForEach(SalesChannel.allCases) { Text($0.title).tag($0) }
                            }
                        }
                        .padding(.top, 14)
                    } label: {
                        Label(AppLocalization.text("entry.optional_details"), systemImage: "slider.horizontal.3")
                            .font(.headline).foregroundStyle(.primary)
                    }
                    .padding(18)
                    .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Button {
                        if onSave(draft) { dismiss() }
                    } label: {
                        Text(AppLocalization.text("Add to trip")).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!isReadyToSave)
                }
                .frame(maxWidth: 680)
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(draft.isKnownProduct ? AppLocalization.text("Found") : AppLocalization.text("entry.product_not_found"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(AppLocalization.text("Cancel")) { dismiss() } } }
            .sheet(isPresented: $showsPricePad) { MoneyKeypad(value: $draft.price, currency: draft.currency) }
            .sheet(isPresented: $showsFamilyLinker) {
                FamilyLinkerView(products: environment.recentProducts, excluding: draft.familyID) { product in
                    environment.link(&draft, to: product)
                    showsFamilyLinker = false
                }
            }
            .fullScreenCover(isPresented: $showsPriceScanner) {
                NavigationStack {
                    ShelfPriceScannerView { price in
                        draft.price = price; showsPriceScanner = false
                    } onError: { environment.errorMessage = $0 }
                    .ignoresSafeArea()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button(AppLocalization.text("Cancel")) { showsPriceScanner = false } } }
                }
            }
        }
    }

    private var isReadyToSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.quantityValue > 0
            && (draft.price ?? 0) > 0
            && draft.decision != .none
    }

    private func validationText(_ key: String) -> some View {
        Text(AppLocalization.text(key))
            .font(.caption)
            .foregroundStyle(.red)
            .accessibilityLabel(AppLocalization.text(key))
    }
}

private struct FamilyLinkerView: View {
    @Environment(\.dismiss) private var dismiss
    let products: [ProductRecord]
    let excluding: String
    let onSelect: (ProductRecord) -> Void
    @State private var search = ""

    private var filtered: [ProductRecord] {
        products.filter {
            $0.familyID != excluding && (search.isEmpty || $0.displayName.localizedStandardContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { product in
                Button {
                    onSelect(product)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(product.displayName).foregroundStyle(.primary)
                        if !product.category.isEmpty { Text(product.category).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            .searchable(text: $search, prompt: AppLocalization.text("entry.search_families"))
            .navigationTitle(AppLocalization.text("entry.link_family"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(AppLocalization.text("Cancel")) { dismiss() } } }
        }
    }
}

private struct MoneyKeypad: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var value: Decimal?
    let currency: CurrencyCode
    @State private var digits = ""

    private var cents: Int { Int(digits) ?? 0 }
    private var display: String { MoneyFormatter.string(Decimal(cents) / 100) }
    private let rows = [["1","2","3"],["4","5","6"],["7","8","9"],[".00","0","⌫"]]
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(display).font(.system(size: 44, weight: .bold, design: .rounded)).contentTransition(.numericText())
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 12) {
                        ForEach(row, id: \.self) { key in
                            Button { tap(key) } label: { Text(key).font(.title2.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 54) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                HStack(spacing: 12) {
                    Button(AppLocalization.text("entry.clear")) { digits = "" }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                    Button(".99") { applyCents("99") }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                    Button(AppLocalization.text("Done")) { value = Decimal(cents) / 100; dismiss() }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                }.controlSize(.large)
            }
            .padding(20)
            .navigationTitle(AppLocalization.text("Price each"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let value { digits = String(NSDecimalNumber(decimal: value * 100).intValue) }
            }
        }
        .presentationDetents([.height(540)])
    }
    private func tap(_ key: String) {
        if key == "⌫" { if !digits.isEmpty { digits.removeLast() } }
        else if key == ".00" { applyCents("00") }
        else if digits.count < 9 { digits.append(key) }
    }
    private func applyCents(_ suffix: String) {
        let whole = cents / 100
        digits = String(whole * 100 + (Int(suffix) ?? 0))
    }
}

struct ComparisonRow: View {
    let result: ComparisonResult
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(statusColor.opacity(0.1)).frame(width: 42, height: 42)
                Image(systemName: statusIcon).foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(result.current.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(metadata).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(shortStatus).font(.caption2.weight(.bold)).foregroundStyle(statusColor)
                .padding(.horizontal, 8).padding(.vertical, 5).background(statusColor.opacity(0.1), in: Capsule())
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 11).contentShape(Rectangle())
    }
    private var metadata: String { "\(result.current.packageDescription) · \(result.current.store)" }
    private var shortStatus: String {
        if let change = result.sizeChange, result.status == .shrinkflation || result.status == .packageChange {
            return abs(change).formatted(.percent.precision(.fractionLength(0...1))) + " " + AppLocalization.text("history.less")
        }
        return result.status.title
    }
    private var statusColor: Color {
        switch result.status {
        case .shrinkflation, .packageChange, .moreExpensive: .red
        case .betterValue: .blue
        case .unchanged: .green
        case .baseline, .capturedDraft: .orange
        }
    }
    private var statusIcon: String {
        switch result.status {
        case .shrinkflation, .packageChange, .moreExpensive: "exclamationmark.triangle"
        case .betterValue: "arrow.down.right"
        case .unchanged: "checkmark"
        case .baseline: "clock"
        case .capturedDraft: "square.and.pencil"
        }
    }
}

struct ComparisonDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment
    let result: ComparisonResult
    @State private var decision: PurchaseDecision
    @State private var quantity: Int
    @State private var evidenceOpen = false
    @State private var showingEdit = false

    init(result: ComparisonResult) {
        self.result = result; _decision = State(initialValue: result.current.decision); _quantity = State(initialValue: result.current.purchaseQuantity)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Image(systemName: heroIcon).font(.system(size: 34, weight: .semibold)).foregroundStyle(heroColor)
                        Text(result.status.title).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                        if let size = result.sizeChange, let previous = result.previous {
                            Text("\(previous.packageDescription) → \(result.current.packageDescription)").font(.headline)
                            Text(sizeText(size)).font(.subheadline.weight(.semibold)).foregroundStyle(heroColor)
                        }
                        if let change = result.unitPriceChange { Text(unitPriceText(change)).font(.subheadline).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity).padding(24)
                    .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    if result.status != .baseline && result.status != .capturedDraft {
                        PremiumSurface {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(AppLocalization.text("result.your_choice")).font(.headline)
                                Picker(AppLocalization.text("result.your_choice"), selection: $decision) {
                                    ForEach([PurchaseDecision.skipped, .switched, .bought]) { Text($0.title).tag($0) }
                                }.pickerStyle(.segmented)
                                Stepper(AppLocalization.text("entry.how_many", quantity), value: $quantity, in: 1...100)
                                Button(AppLocalization.text("Save")) {
                                    environment.updateDecision(for: result, decision: decision, quantity: quantity)
                                }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                            }
                        }
                    }

                    DisclosureGroup(isExpanded: $evidenceOpen) {
                        VStack(alignment: .leading, spacing: 10) {
                            evidenceRow(AppLocalization.text("result.current"), result.current.packageDescription, result.current.formattedPrice)
                            if let previous = result.previous { evidenceRow(AppLocalization.text("result.previous"), previous.packageDescription, previous.formattedPrice) }
                            Divider()
                            Label(result.current.store, systemImage: "basket")
                            Label(result.current.observedAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        }.padding(.top, 12)
                    } label: { Text(AppLocalization.text("result.see_evidence")).font(.headline) }
                    .padding(18).background(.background, in: RoundedRectangle(cornerRadius: 18))
                }
                .frame(maxWidth: 680).padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(result.current.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingEdit = true } label: { Image(systemName: "pencil") }
                        .accessibilityLabel(AppLocalization.text("result.edit"))
                }
                ToolbarItem(placement: .confirmationAction) { Button(AppLocalization.text("Done")) { dismiss() } }
            }
            .sheet(isPresented: $showingEdit) {
                ProductEntryView(initialDraft: ObservationDraft(observation: result.current)) { updated in
                    guard environment.save(updated) != nil else { return false }
                    showingEdit = false
                    return true
                }
            }
        }
    }
    private func evidenceRow(_ title: String, _ amount: String, _ price: String?) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text([amount, price].compactMap { $0 }.joined(separator: " · ")).fontWeight(.semibold) }
    }
    private func sizeText(_ value: Double) -> String { value < 0 ? AppLocalization.text("result.less", abs(value).formatted(.percent.precision(.fractionLength(0...1)))) : AppLocalization.text("result.more", value.formatted(.percent.precision(.fractionLength(0...1)))) }
    private func unitPriceText(_ value: Double) -> String { value >= 0 ? AppLocalization.text("result.unit_more", value.formatted(.percent.precision(.fractionLength(0...1)))) : AppLocalization.text("result.unit_less", abs(value).formatted(.percent.precision(.fractionLength(0...1)))) }
    private var heroIcon: String { result.status == .betterValue || result.status == .unchanged ? "checkmark.circle.fill" : result.status == .baseline ? "clock.badge.checkmark" : "exclamationmark.triangle.fill" }
    private var heroColor: Color { result.status == .betterValue ? .blue : result.status == .unchanged ? .green : result.status == .baseline ? .orange : .red }
}

struct HistoryView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var search = ""
    @State private var selected: ComparisonResult?
    @State private var showingFilters = false
    @State private var showingSettings = false
    @State private var undoToken: UUID?

    private var filtered: [ComparisonResult] {
        environment.recentComparisons.filter {
            environment.historyFilter.includes($0) && (search.isEmpty || $0.current.displayName.localizedStandardContains(search) || $0.current.store.localizedStandardContains(search))
        }
    }
    var body: some View {
        List {
            Button { showingFilters = true } label: {
                HStack { Image(systemName: "line.3.horizontal.decrease.circle"); Text(AppLocalization.text("history.filters")); Spacer(); Text(filterSummary).foregroundStyle(.secondary) }
            }
            if filtered.isEmpty {
                ContentUnavailableView(AppLocalization.text("No scans yet"), systemImage: "clock", description: Text(AppLocalization.text("Your saved comparisons will appear here.")))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(filtered) { row in
                    Button { selected = row } label: { ComparisonRow(result: row) }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(AppLocalization.text("Delete"), role: .destructive) { delete(row) }
                        }
                        .accessibilityAction(named: AppLocalization.text("Delete")) { delete(row) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(AppLocalization.text("History"))
        .searchable(text: $search, prompt: AppLocalization.text("history.search"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel(AppLocalization.text("accessibility.settings"))
            }
        }
        .sheet(item: $selected) { ComparisonDetailView(result: $0) }
        .sheet(isPresented: $showingFilters) { FilterView() }
        .sheet(isPresented: $showingSettings) { NavigationStack { SettingsView() } }
        .overlay(alignment: .bottom) {
            if undoToken != nil {
                HStack { Text(AppLocalization.text("history.deleted")); Spacer(); Button(AppLocalization.text("history.undo")) { environment.undoDelete(); undoToken = nil } }
                    .padding().background(.ultraThickMaterial, in: Capsule()).padding()
                    .task(id: undoToken) {
                        guard let token = undoToken else { return }
                        try? await Task.sleep(for: .seconds(8))
                        guard undoToken == token else { return }
                        environment.expireUndo()
                        undoToken = nil
                    }
            }
        }
    }
    private var filterSummary: String { environment.historyFilter.range.title }
    private func delete(_ row: ComparisonResult) {
        if environment.delete(row) { undoToken = UUID() }
    }
}

private struct FilterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment
    private var stores: [String] { Array(Set(environment.recentComparisons.map(\.current.store))).filter { !$0.isEmpty }.sorted() }
    private var categories: [String] { Array(Set(environment.recentComparisons.map(\.current.category))).filter { !$0.isEmpty }.sorted() }
    var body: some View {
        NavigationStack {
            Form {
                Picker(AppLocalization.text("filter.date"), selection: $environment.historyFilter.range) { ForEach(HistoryRange.allCases) { Text($0.title).tag($0) } }
                Picker(AppLocalization.text("filter.status"), selection: $environment.historyFilter.status) {
                    Text(AppLocalization.text("filter.any")).tag(nil as ComparisonStatus?)
                    ForEach(ComparisonStatus.allCases) { Text($0.title).tag(Optional($0)) }
                }
                if !categories.isEmpty { Picker(AppLocalization.text("filter.category"), selection: $environment.historyFilter.category) { Text(AppLocalization.text("filter.any")).tag(""); ForEach(categories, id: \.self) { Text($0).tag($0) } } }
                if !stores.isEmpty { Picker(AppLocalization.text("filter.store"), selection: $environment.historyFilter.store) { Text(AppLocalization.text("filter.any")).tag(""); ForEach(stores, id: \.self) { Text($0).tag($0) } } }
                Button(AppLocalization.text("filter.reset")) { environment.historyFilter = HistoryFilter() }.foregroundStyle(.red)
            }
            .navigationTitle(AppLocalization.text("history.filters")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(AppLocalization.text("Done")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ImpactPoint: Identifiable {
    var id: String { "\(day.timeIntervalSince1970):\(kind)" }
    let day: Date; let kind: String; let value: Double
}

struct ImpactView: View {
    @EnvironmentObject private var environment: AppEnvironment
    private let currency: CurrencyCode = .usd
    @State private var showingFilters = false
    @State private var showingSettings = false

    private var results: [ComparisonResult] { environment.recentComparisons.filter(environment.historyFilter.includes) }
    private var summary: ImpactSummary { environment.impactSummary(currency: currency, results: results) }
    private var points: [ImpactPoint] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: results.filter { $0.current.currency == currency && $0.extraCostPerPack != nil }) { calendar.startOfDay(for: $0.current.observedAt) }
        return grouped.flatMap { day, rows in
            let protectedWeighted = rows.filter { $0.current.decision == .skipped || $0.current.decision == .switched }
                .compactMap { row in row.extraCostPerPack.map { $0 * Decimal(row.current.purchaseQuantity) } }
                .reduce(Decimal.zero, +)
            let cost = rows.filter { $0.current.decision == .bought }
                .compactMap { row in row.extraCostPerPack.map { $0 * Decimal(row.current.purchaseQuantity) } }
                .reduce(Decimal.zero, +)
            return [ImpactPoint(day: day, kind: AppLocalization.text("impact.you"), value: NSDecimalNumber(decimal: protectedWeighted).doubleValue), ImpactPoint(day: day, kind: AppLocalization.text("impact.shrinkflation"), value: NSDecimalNumber(decimal: cost).doubleValue)]
        }.filter { $0.value > 0 }
    }
    private var chartUpperBound: Double { max((points.map(\.value).max() ?? 0) * 1.15, 1) }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PremiumSurface {
                    VStack(spacing: 18) {
                        HStack { Label(AppLocalization.text("impact.scorecard"), systemImage: "sportscourt").font(.headline); Spacer(); Text(AppLocalization.text("impact.scored", summary.scoredBouts)).font(.caption).foregroundStyle(.secondary) }
                        ViewThatFits {
                            HStack(spacing: 0) {
                                scoreColumn(title: AppLocalization.text("impact.you_protected"), value: summary.protected, color: .blue)
                                Rectangle().fill(.quaternary).frame(width: 1, height: 70)
                                scoreColumn(title: AppLocalization.text("impact.it_cost_you"), value: summary.cost, color: .red)
                            }
                            VStack(spacing: 14) {
                                scoreColumn(title: AppLocalization.text("impact.you_protected"), value: summary.protected, color: .blue)
                                Divider()
                                scoreColumn(title: AppLocalization.text("impact.it_cost_you"), value: summary.cost, color: .red)
                            }
                        }
                    }
                }
                HStack(spacing: 12) {
                    metric(title: AppLocalization.text("impact.caught"), value: "\(summary.productsCaught)", icon: "exclamationmark.triangle", color: .red)
                    metric(title: AppLocalization.text("impact.unscored"), value: "\(summary.unscoredEvidence)", icon: "doc.text.magnifyingglass", color: .orange)
                }
                if points.isEmpty {
                    ContentUnavailableView(AppLocalization.text("impact.no_score"), systemImage: "chart.bar", description: Text(AppLocalization.text("impact.no_score_detail"))).padding(.top, 24)
                } else {
                    PremiumSurface {
                        Chart(points) { point in
                            BarMark(
                                x: .value(AppLocalization.text("chart.date"), point.day, unit: .day),
                                y: .value(AppLocalization.text("chart.amount"), point.value)
                            )
                            .foregroundStyle(by: .value(AppLocalization.text("chart.series"), point.kind))
                            .position(by: .value(AppLocalization.text("chart.series"), point.kind))
                        }
                        .chartForegroundStyleScale([AppLocalization.text("impact.you"): Color.blue, AppLocalization.text("impact.shrinkflation"): Color.red])
                        .chartYScale(domain: 0...chartUpperBound)
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisGridLine()
                                AxisTick()
                                AxisValueLabel {
                                    if let amount = value.as(Double.self) {
                                        Text(MoneyFormatter.string(Decimal(amount)))
                                    }
                                }
                            }
                        }
                        .frame(height: 210)
                    }
                }
            }
            .frame(maxWidth: 680).padding(16).padding(.bottom, 28)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(AppLocalization.text("tab.impact"))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showingFilters = true } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                    .accessibilityLabel(AppLocalization.text("accessibility.filters"))
                Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel(AppLocalization.text("accessibility.settings"))
            }
        }
        .sheet(isPresented: $showingFilters) { FilterView() }
        .sheet(isPresented: $showingSettings) { NavigationStack { SettingsView() } }
    }
    private func scoreColumn(title: String, value: Decimal, color: Color) -> some View {
        VStack(spacing: 5) { Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary); Text(MoneyFormatter.string(value)).font(.title2.weight(.bold)).foregroundStyle(color) }.frame(maxWidth: .infinity)
    }
    private func metric(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) { Image(systemName: icon).foregroundStyle(color); Text(value).font(.title2.weight(.bold)); Text(title).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showingDelete = false
    @State private var showingPurchase = false
    var body: some View {
        List {
            Section(AppLocalization.text("Ads")) {
                Button { showingPurchase = true } label: { Label(AppLocalization.text("Remove Ads Forever"), systemImage: "rectangle.slash") }
                    .disabled(environment.purchaseManager.hasRemovedAds)
                Button(AppLocalization.text("Restore Purchase")) { Task { await environment.purchaseManager.restorePurchases() } }
                if environment.adManager.privacyOptionsRequired { Button(AppLocalization.text("Privacy choices")) { Task { await environment.adManager.presentPrivacyOptions() } } }
            }
            Section(AppLocalization.text("Offline data")) {
                Button(AppLocalization.text("Delete all local data"), role: .destructive) { showingDelete = true }
            }
            Section(AppLocalization.text("settings.help")) {
                NavigationLink(AppLocalization.text("settings.how_it_works")) { PolicyTextView(title: AppLocalization.text("settings.how_it_works"), text: AppLocalization.text("policy.how_it_works")) }
                Link(AppLocalization.text("Support"), destination: AppLinks.support)
            }
            Section(AppLocalization.text("settings.legal")) {
                Link(destination: AppLinks.privacyPolicy) {
                    ExternalPolicyLabel(title: AppLocalization.text("settings.privacy_data"))
                }
                Link(destination: AppLinks.termsOfUse) {
                    ExternalPolicyLabel(title: AppLocalization.text("settings.terms"))
                }
            }
            Section { EmptyView() } footer: {
                VStack(spacing: 5) {
                    Text(AppLocalization.text("settings.local_footer"))
                    Text("\(AppLocalization.text("Version")) \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                }.frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }
        }
        .navigationTitle(AppLocalization.text("Settings")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(AppLocalization.text("Done")) { dismiss() } } }
        .alert(AppLocalization.text("Delete every saved scan and learned barcode?"), isPresented: $showingDelete) {
            Button(AppLocalization.text("Delete"), role: .destructive) { environment.deleteAllData() }
            Button(AppLocalization.text("Cancel"), role: .cancel) { }
        }
        .sheet(isPresented: $showingPurchase) { RemoveBannerView() }
        .alert(AppLocalization.text("Something went wrong"), isPresented: Binding(
            get: { environment.purchaseManager.errorMessage != nil },
            set: { if !$0 { environment.purchaseManager.errorMessage = nil } }
        )) {
            Button(AppLocalization.text("OK")) { environment.purchaseManager.errorMessage = nil }
        } message: {
            Text(environment.purchaseManager.errorMessage ?? AppLocalization.text("purchase.failed"))
        }
    }
}

private struct ExternalPolicyLabel: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
    }
}

private struct PolicyTextView: View {
    let title: String; let text: String
    var body: some View { ScrollView { Text(text).frame(maxWidth: 680, alignment: .leading).padding(20) }.navigationTitle(title).navigationBarTitleDisplayMode(.inline) }
}

struct RemoveBannerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment
    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Image(systemName: "rectangle.slash.fill").font(.system(size: 46)).foregroundStyle(.blue)
                Text(AppLocalization.text("banner.remove")).font(.title2.weight(.bold))
                Text(AppLocalization.text("purchase.banner_scope")).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button {
                    Task { await environment.purchaseManager.purchaseRemoveAds(); if environment.purchaseManager.hasRemovedAds { dismiss() } }
                } label: {
                    if environment.purchaseManager.isWorking {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(environment.purchaseManager.product?.displayPrice ?? AppLocalization.text("purchase.one_time"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(environment.purchaseManager.product == nil || environment.purchaseManager.isWorking)
                Button(AppLocalization.text("Restore Purchase")) {
                    Task {
                        await environment.purchaseManager.restorePurchases()
                        if environment.purchaseManager.hasRemovedAds { dismiss() }
                    }
                }
                .disabled(environment.purchaseManager.isWorking)
                Spacer()
            }
            .padding(24)
            .navigationTitle(AppLocalization.text("Remove Ads Forever")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(AppLocalization.text("Cancel")) { dismiss() } } }
        }
        .presentationDetents([.medium])
        .task { await environment.purchaseManager.loadProductMetadata() }
        .alert(AppLocalization.text("Something went wrong"), isPresented: Binding(
            get: { environment.purchaseManager.errorMessage != nil },
            set: { if !$0 { environment.purchaseManager.errorMessage = nil } }
        )) {
            Button(AppLocalization.text("OK")) { environment.purchaseManager.errorMessage = nil }
        } message: {
            Text(environment.purchaseManager.errorMessage ?? AppLocalization.text("purchase.failed"))
        }
    }
}
