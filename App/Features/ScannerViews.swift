import AVFoundation
import Foundation
import SwiftUI
import UIKit
import VisionKit

struct BarcodeScannerView: UIViewControllerRepresentable {
    let onScan: (String, BarcodeNormalizer.Kind) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let controller = BarcodeScannerViewController()
        controller.onScan = onScan
        controller.onError = onError
        return controller
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}
}

final class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String, BarcodeNormalizer.Kind) -> Void)?
    var onError: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let sessionQueue = DispatchQueue(label: "com.worksbienstudios.shrinkflation.camera")
    private var configured = false
    private var hasScanned = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        let guide = UIView()
        guide.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        guide.layer.borderWidth = 2
        guide.layer.cornerRadius = 18
        guide.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(guide)

        let instruction = UILabel()
        instruction.text = AppLocalization.text("scanner.place_barcode")
        instruction.textColor = .white
        instruction.font = .preferredFont(forTextStyle: .headline)
        instruction.textAlignment = .center
        instruction.numberOfLines = 2
        instruction.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(instruction)

        NSLayoutConstraint.activate([
            guide.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            guide.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            guide.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.82),
            guide.heightAnchor.constraint(equalToConstant: 170),
            instruction.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            instruction.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            instruction.bottomAnchor.constraint(equalTo: guide.topAnchor, constant: -24)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        requestAccessAndStart()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in self?.session.stopRunning() }
    }

    private func requestAccessAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureAndStart()
                    } else {
                        self?.onError?(AppLocalization.text("scanner.camera_needed"))
                    }
                }
            }
        default:
            onError?(AppLocalization.text("scanner.camera_disabled"))
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !configured {
                do {
                    guard let device = AVCaptureDevice.default(for: .video) else {
                        throw ScannerError.noCamera
                    }
                    let input = try AVCaptureDeviceInput(device: device)
                    guard session.canAddInput(input) else { throw ScannerError.configuration }
                    session.addInput(input)

                    let output = AVCaptureMetadataOutput()
                    guard session.canAddOutput(output) else { throw ScannerError.configuration }
                    session.addOutput(output)
                    output.setMetadataObjectsDelegate(self, queue: .main)
                    output.metadataObjectTypes = [.ean8, .ean13, .upce, .code128, .itf14]
                    configured = true
                } catch {
                    DispatchQueue.main.async { self.onError?(error.localizedDescription) }
                    return
                }
            }
            if !session.isRunning { session.startRunning() }
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasScanned,
              let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = readable.stringValue else { return }
        hasScanned = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        sessionQueue.async { [weak self] in self?.session.stopRunning() }
        let kind: BarcodeNormalizer.Kind
        switch readable.type {
        case .upce: kind = .upce
        case .ean8: kind = .ean8
        default: kind = .other
        }
        onScan?(value, kind)
    }
}

private enum ScannerError: LocalizedError {
    case noCamera
    case configuration

    var errorDescription: String? {
        switch self {
        case .noCamera: AppLocalization.text("scanner.no_camera")
        case .configuration: AppLocalization.text("scanner.start_failed")
        }
    }
}

struct ShelfPriceScannerView: UIViewControllerRepresentable {
    let onPrice: (Decimal) -> Void
    let onError: (String) -> Void

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    static func extractPrice(from text: String) -> Decimal? {
        Coordinator.extractPrice(from: text)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text(languages: ["en-US", "es-US", "fr-CA"])],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        guard !uiViewController.isScanning else { return }
        do { try uiViewController.startScanning() }
        catch { onError(error.localizedDescription) }
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: ShelfPriceScannerView
        init(parent: ShelfPriceScannerView) { self.parent = parent }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            guard case .text(let text) = item,
                  let price = Self.extractPrice(from: text.transcript) else {
                parent.onError(AppLocalization.text("scanner.tap_shelf_price"))
                return
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            parent.onPrice(price)
        }

        static func extractPrice(from text: String) -> Decimal? {
            let normalized = text.replacingOccurrences(of: ",", with: ".")
            let patterns = [
                #"(?:US\$|CA\$|CAD|USD|\$)\s*([0-9]{1,4}(?:\.[0-9]{1,2})?)"#,
                #"\b([0-9]{1,3}\.[0-9]{2})\b"#
            ]
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                      let match = regex.firstMatch(
                        in: normalized,
                        range: NSRange(normalized.startIndex..., in: normalized)
                      ),
                      match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: normalized),
                      let value = Decimal(string: String(normalized[range]), locale: Locale(identifier: "en_US_POSIX")),
                      value >= 0 else { continue }
                return value
            }
            return nil
        }
    }
}
