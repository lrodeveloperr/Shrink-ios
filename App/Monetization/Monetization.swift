import AppTrackingTransparency
import StoreKit
import SwiftUI
import UIKit
import GoogleMobileAds
import UserMessagingPlatform

enum AdMode: Equatable {
    case googleSampleTest
    case production
    case invalid
}

enum AdConfiguration {
    static let googleSampleAppID = "ca-app-pub-3940256099942544~1458002511"
    static let googleSampleBannerID = "ca-app-pub-3940256099942544/2435281174"

    static func mode(in bundle: Bundle = .main) -> AdMode {
        guard let appID = bundle.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String,
              let bannerID = bundle.object(forInfoDictionaryKey: "GADBannerAdUnitID") as? String else { return .invalid }
        if appID == googleSampleAppID && bannerID == googleSampleBannerID { return .googleSampleTest }
        if appID == googleSampleAppID || bannerID == googleSampleBannerID
            || appID.contains("3940256099942544") || bannerID.contains("3940256099942544") {
            return .invalid
        }

        let appPattern = #"^ca-app-pub-(\d{16})~\d{10}$"#
        let bannerPattern = #"^ca-app-pub-(\d{16})/\d{10}$"#
        guard let appMatch = appID.range(of: appPattern, options: .regularExpression),
              let bannerMatch = bannerID.range(of: bannerPattern, options: .regularExpression) else { return .invalid }
        let appPublisher = String(appID[appMatch]).split(whereSeparator: { $0 == "-" || $0 == "~" })[3]
        let bannerPublisher = String(bannerID[bannerMatch]).split(whereSeparator: { $0 == "-" || $0 == "/" })[3]
        return appPublisher == bannerPublisher ? .production : .invalid
    }
}

@MainActor
final class PurchaseManager: ObservableObject {
    static let removeAdsProductID = "com.worksbienstudios.shrinkflationpricescanner.removeads"

    @Published private(set) var hasRemovedAds = false
    @Published private(set) var product: Product?
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    private var updatesTask: Task<Void, Never>?

    deinit { updatesTask?.cancel() }

    func resolveEntitlement() async {
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
        await refreshEntitlements()
    }

    func loadProductMetadata() async {
        errorMessage = nil
        do {
            product = try await Product.products(for: [Self.removeAdsProductID]).first
            if product == nil {
                errorMessage = AppLocalization.text("purchase.unavailable")
            }
        } catch {
            errorMessage = AppLocalization.text("purchase.load_failed")
        }
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
    @Published private(set) var mode: AdMode = .invalid
    private var didStartAds = false

    func prepareAds() async {
        mode = AdConfiguration.mode()
        switch mode {
        case .googleSampleTest:
            privacyOptionsRequired = false
            await startAdsIfNeeded()
            canRequestAds = true
            return
        case .invalid:
            privacyOptionsRequired = false
            canRequestAds = false
            return
        case .production:
            break
        }

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
        guard canRequestAds else { return }

        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
        await startAdsIfNeeded()
    }

    func presentPrivacyOptions() async {
        guard mode == .production else { return }
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: nil)
            canRequestAds = ConsentInformation.shared.canRequestAds
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startAdsIfNeeded() async {
        guard !didStartAds else { return }
        await MobileAds.shared.start()
        didStartAds = true
    }
}

struct PersistentAdStrip: View {
    @ObservedObject var adManager: AdManager
    @State private var loadState: BannerLoadState = .loading
    @State private var reservedHeight: CGFloat = 64

    var body: some View {
        Group {
            if adManager.canRequestAds && loadState != .failed {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 8)
                    GeometryReader { proxy in
                        let width = max(proxy.size.width, 320)
                        let size = currentOrientationAnchoredAdaptiveBanner(width: width)
                        BannerViewContainer(adSize: size) { loaded in
                            loadState = loaded ? .loaded : .failed
                        }
                        .id(Int(size.size.width.rounded()))
                        .frame(width: size.size.width, height: size.size.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .opacity(loadState == .loaded ? 1 : 0)
                        .allowsHitTesting(loadState == .loaded)
                        .accessibilityHidden(loadState != .loaded)
                        .onAppear { reserveBannerHeight(size.size.height) }
                        .onChange(of: proxy.size.width) { _, newWidth in
                            loadState = .loading
                            reserveBannerHeight(currentOrientationAnchoredAdaptiveBanner(width: max(newWidth, 320)).size.height)
                        }
                    }
                    .frame(height: reservedHeight)
                    .background(.regularMaterial)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .onChange(of: adManager.canRequestAds) { _, canRequestAds in
            loadState = canRequestAds ? .loading : .failed
        }
    }

    private func reserveBannerHeight(_ adHeight: CGFloat) {
        reservedHeight = max(64, adHeight.rounded(.up))
    }
}

private enum BannerLoadState: Equatable { case loading, loaded, failed }

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
