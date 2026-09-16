import AVFoundation
import Foundation
import SwiftUI
import UIKit
import VisionKit

struct BarcodeScannerView: UIViewControllerRepresentable {
    let onScan: (String, BarcodeNormalizer.Kind) -> Void
    let onError: (String) -> Void
    let onManual: () -> Void

    init(
        onScan: @escaping (String, BarcodeNormalizer.Kind) -> Void,
        onError: @escaping (String) -> Void,
        onManual: @escaping () -> Void = {}
    ) {
        self.onScan = onScan
        self.onError = onError
        self.onManual = onManual
    }

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let controller = BarcodeScannerViewController()
        controller.onScan = onScan
        controller.onError = onError
        controller.onManual = onManual
        return controller
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}
}

final class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String, BarcodeNormalizer.Kind) -> Void)?
    var onError: ((String) -> Void)?
    var onManual: (() -> Void)?

    private let session = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let metadataOutput = AVCaptureMetadataOutput()
    private let guide = UIView()
    private let statusLabel = UILabel()
    private let torchButton = UIButton(type: .system)
    private let retryButton = UIButton(type: .system)
    private let manualButton = UIButton(type: .system)
    private let sessionQueue = DispatchQueue(label: "com.worksbienstudios.shrinkflation.camera")
    private var configured = false
    private var hasScanned = false
    private var captureDevice: AVCaptureDevice?
    private var timeoutWorkItem: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        guide.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        guide.layer.borderWidth = 2
        guide.layer.cornerRadius = 18
        guide.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(guide)

        statusLabel.text = AppLocalization.text("scanner.place_barcode")
        statusLabel.textColor = .white
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.accessibilityLabel = AppLocalization.text("scanner.place_barcode")
        view.addSubview(statusLabel)

        configureButton(torchButton, title: AppLocalization.text("scanner.torch"), image: "flashlight.off.fill", action: #selector(toggleTorch))
        configureButton(retryButton, title: AppLocalization.text("scanner.retry"), image: "arrow.clockwise", action: #selector(retryScan))
        configureButton(manualButton, title: AppLocalization.text("scanner.manual"), image: "square.and.pencil", action: #selector(openManual))
        let controls = UIStackView(arrangedSubviews: [torchButton, retryButton, manualButton])
        controls.axis = .horizontal
        controls.distribution = .fillEqually
        controls.spacing = 12
        controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)

        NSLayoutConstraint.activate([
            guide.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            guide.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            guide.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.82),
            guide.heightAnchor.constraint(equalToConstant: 170),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            statusLabel.bottomAnchor.constraint(equalTo: guide.topAnchor, constant: -24),
            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            controls.topAnchor.constraint(equalTo: guide.bottomAnchor, constant: 28),
            controls.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        updateVideoOrientation()
        if configured {
            metadataOutput.rectOfInterest = previewLayer.metadataOutputRectConverted(fromLayerRect: guide.frame)
        }
    }

    private func updateVideoOrientation() {
        guard let interfaceOrientation = view.window?.windowScene?.interfaceOrientation else { return }
        let orientation: AVCaptureVideoOrientation
        switch interfaceOrientation {
        case .landscapeLeft: orientation = .landscapeLeft
        case .landscapeRight: orientation = .landscapeRight
        case .portraitUpsideDown: orientation = .portraitUpsideDown
        default: orientation = .portrait
        }
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = orientation
        }
        if let connection = metadataOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = orientation
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        requestAccessAndStart()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timeoutWorkItem?.cancel()
        setTorch(enabled: false)
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
                    captureDevice = device
                    try configureCamera(device)
                    let input = try AVCaptureDeviceInput(device: device)
                    guard session.canAddInput(input) else { throw ScannerError.configuration }
                    session.addInput(input)

                    guard session.canAddOutput(metadataOutput) else { throw ScannerError.configuration }
                    session.addOutput(metadataOutput)
                    metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
                    metadataOutput.metadataObjectTypes = [
                        .ean8, .ean13, .upce, .code128, .itf14,
                        .gs1DataBar, .gs1DataBarExpanded, .gs1DataBarLimited
                    ]
                    configured = true
                } catch {
                    DispatchQueue.main.async { self.onError?(error.localizedDescription) }
                    return
                }
            }
            if !session.isRunning { session.startRunning() }
            DispatchQueue.main.async {
                self.updateVideoOrientation()
                self.metadataOutput.rectOfInterest = self.previewLayer.metadataOutputRectConverted(fromLayerRect: self.guide.frame)
                self.startTimeout()
            }
        }
    }

    private func configureCamera(_ device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
    }

    private func configureButton(_ button: UIButton, title: String, image: String, action: Selector) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: image)
        configuration.imagePadding = 7
        configuration.baseBackgroundColor = UIColor.systemBlue.withAlphaComponent(0.9)
        button.configuration = configuration
        button.addTarget(self, action: action, for: .touchUpInside)
        button.accessibilityLabel = title
    }

    private func startTimeout() {
        timeoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.hasScanned else { return }
            self.statusLabel.text = AppLocalization.text("scanner.timeout")
            self.retryButton.isHidden = false
            self.onError?(AppLocalization.text("scanner.timeout"))
        }
        timeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 18, execute: work)
    }

    @objc private func retryScan() {
        hasScanned = false
        statusLabel.text = AppLocalization.text("scanner.place_barcode")
        retryButton.isHidden = false
        configureAndStart()
    }

    @objc private func openManual() {
        timeoutWorkItem?.cancel()
        onManual?()
    }

    @objc private func toggleTorch() {
        guard let device = captureDevice, device.hasTorch else { return }
        setTorch(enabled: !device.isTorchActive)
    }

    private func setTorch(enabled: Bool) {
        guard let device = captureDevice, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if enabled { try device.setTorchModeOn(level: min(AVCaptureDevice.maxAvailableTorchLevel, 0.5)) }
            else { device.torchMode = .off }
            device.unlockForConfiguration()
            torchButton.configuration?.image = UIImage(systemName: enabled ? "flashlight.on.fill" : "flashlight.off.fill")
        } catch {
            onError?(AppLocalization.text("scanner.torch_failed"))
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
        timeoutWorkItem?.cancel()
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
            recognizedDataTypes: [.text(languages: ["en-US", "es-US"])],
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
                #"(?:US\$|USD|\$)\s*([0-9]{1,4}(?:\.[0-9]{1,2})?)"#,
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
