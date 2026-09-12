import AppTrackingTransparency
import StoreKit
import SwiftUI
import UIKit
import GoogleMobileAds
import UserMessagingPlatform

@MainActor
final class PurchaseManager: ObservableObject {
    static let removeAdsProductID = "com.worksbienstudios.shrinkflationpricescanner.removeads"

    @Published private(set) var hasRemovedAds = false
    @Published private(set) var product: Product?
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    private var updatesTask: Task<Void, Never>?

    deinit { updatesTask?.cancel() }

    func start() async {
        if updatesTask == nil {
            updatesTask = Task { [weak self] in
                for await update in StoreKit.Transaction.updates {
                    guard let self else { return }
                    if case .verified(let transaction) = update {
                        await transaction.finish()
                        await self.refreshEntitlements()
                    }
                }
            }
        }

        errorMessage = nil
        do {
            product = try await Product.products(for: [Self.removeAdsProductID]).first
            if product == nil {
                errorMessage = AppLocalization.text("purchase.unavailable")
            }
        } catch {
            errorMessage = AppLocalization.text("purchase.load_failed")
        }
        await refreshEntitlements()
    }

    func purchaseRemoveAds() async {
        errorMessage = nil
        guard let product else {
            errorMessage = AppLocalization.text("purchase.unavailable")
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification,
                      transaction.productID == Self.removeAdsProductID else {
                    errorMessage = AppLocalization.text("purchase.verify_failed")
                    return
                }
                await transaction.finish()
                await refreshEntitlements()
            case .pending:
                errorMessage = AppLocalization.text("purchase.pending")
            case .userCancelled:
                break
            @unknown default:
                errorMessage = AppLocalization.text("purchase.failed")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshEntitlements() async {
        var entitled = false
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.removeAdsProductID,
               transaction.revocationDate == nil {
                entitled = true
            }
        }
        hasRemovedAds = entitled
    }
}

@MainActor
final class AdManager: ObservableObject {
    @Published private(set) var canRequestAds = false
    @Published private(set) var privacyOptionsRequired = false
    @Published var errorMessage: String?
    private var didStartAds = false

    func prepareAds() async {
        let parameters = RequestParameters()
        let consentError: Error? = await withCheckedContinuation { continuation in
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { error in
                continuation.resume(returning: error)
            }
        }
        if let consentError { errorMessage = consentError.localizedDescription }

        do {
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
        } catch {
            errorMessage = error.localizedDescription
        }

        privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        canRequestAds = ConsentInformation.shared.canRequestAds
        guard canRequestAds, !didStartAds else { return }

        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
        await MobileAds.shared.start()
        didStartAds = true
    }

    func presentPrivacyOptions() async {
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: nil)
            canRequestAds = ConsentInformation.shared.canRequestAds
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PersistentAdStrip: View {
    @ObservedObject var purchaseManager: PurchaseManager
    @ObservedObject var adManager: AdManager
    @State private var adLoaded = false
    @State private var showingPurchase = false
    @State private var reservedHeight: CGFloat = 64

    var body: some View {
        Group {
            if !purchaseManager.hasRemovedAds {
                GeometryReader { proxy in
                    ZStack {
                        HouseBanner(purchaseManager: purchaseManager) { showingPurchase = true }
                        if adManager.canRequestAds {
                            let width = max(proxy.size.width, 320)
                            let size = currentOrientationAnchoredAdaptiveBanner(width: width)
                            BannerViewContainer(adSize: size) { loaded in
                                withAnimation(.easeInOut(duration: 0.2)) { adLoaded = loaded }
                            }
                                .id(Int(size.size.width.rounded()))
                                .frame(width: size.size.width, height: size.size.height)
                                .opacity(adLoaded ? 1 : 0)
                                .allowsHitTesting(adLoaded)
                                .onAppear { reserveBannerHeight(size.size.height) }
                                .onChange(of: proxy.size.width) { _, newWidth in
                                    adLoaded = false
                                    reserveBannerHeight(currentOrientationAnchoredAdaptiveBanner(width: max(newWidth, 320)).size.height)
                                }
                        }
                    }
                }
                .frame(height: reservedHeight)
                .background(.regularMaterial)
                .accessibilityElement(children: .contain)
                .sheet(isPresented: $showingPurchase) { RemoveBannerView() }
            }
        }
        .onChange(of: purchaseManager.hasRemovedAds) { _, hasRemovedAds in
            guard !hasRemovedAds else { return }
            Task { await adManager.prepareAds() }
        }
    }

    private func reserveBannerHeight(_ adHeight: CGFloat) {
        reservedHeight = max(64, adHeight.rounded(.up))
    }
}

private struct HouseBanner: View {
    @ObservedObject var purchaseManager: PurchaseManager
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(Color.blue.opacity(0.1)).frame(width: 30, height: 30)
                    Image(systemName: "rectangle.slash").font(.caption.weight(.bold)).foregroundStyle(.blue)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("banner.remove")
                        .font(.caption.weight(.semibold))
                    Text("banner.one_time")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(purchaseManager.product?.displayPrice ?? AppLocalization.text("banner.action"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(Color.blue, in: Capsule())
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("banner.accessibility"))
    }
}

private struct BannerViewContainer: UIViewRepresentable {
    let adSize: AdSize
    let onLoadChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLoadChange: onLoadChange) }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = Bundle.main.object(forInfoDictionaryKey: "GADBannerAdUnitID") as? String
            ?? "ca-app-pub-3940256099942544/2435281174"
        banner.backgroundColor = .clear
        banner.delegate = context.coordinator
        context.coordinator.loadIfPossible(banner)
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        context.coordinator.loadIfPossible(banner)
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        let onLoadChange: (Bool) -> Void
        private var didRequestAd = false

        init(onLoadChange: @escaping (Bool) -> Void) { self.onLoadChange = onLoadChange }

        func loadIfPossible(_ banner: BannerView) {
            if banner.rootViewController == nil {
                banner.rootViewController = UIApplication.shared.topViewController
            }
            guard banner.rootViewController != nil, !didRequestAd else { return }
            didRequestAd = true
            banner.load(Request())
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) { onLoadChange(true) }
        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) { onLoadChange(false) }
    }
}

private extension UIApplication {
    var topViewController: UIViewController? {
        let window = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        var current = window?.rootViewController
        while let presented = current?.presentedViewController { current = presented }
        return current
    }
}
