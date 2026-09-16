import XCTest
@testable import ShrinkflationPriceScanner

final class CoreLogicTests: XCTestCase {
    func testNormalizesUPCAAndEAN13ToGTIN14() {
        XCTAssertEqual(BarcodeNormalizer.normalize("036000291452"), "00036000291452")
        XCTAssertEqual(BarcodeNormalizer.normalize("4006381333931"), "04006381333931")
    }

    func testExpandsUPCEBeforeNormalizing() {
        XCTAssertEqual(BarcodeNormalizer.normalize("04252614"), "00042100005264")
        XCTAssertEqual(BarcodeNormalizer.normalize("10102817", kind: .upce), "00101100000287")
        XCTAssertEqual(BarcodeNormalizer.normalize("10102817", kind: .ean8), "00000010102817")
        XCTAssertNil(BarcodeNormalizer.normalize("20102816", kind: .upce))
    }

    func testExtractsGS1ApplicationIdentifier() {
        XCTAssertEqual(BarcodeNormalizer.normalize("(01)00036000291452(10)ABC"), "00036000291452")
    }

    func testRejectsInvalidCheckDigit() {
        XCTAssertNil(BarcodeNormalizer.normalize("036000291453"))
        XCTAssertNil(BarcodeNormalizer.normalize("not a barcode"))
    }

    func testShrinkflationCalculation() {
        let old = observation(quantity: 1_000, price: 10)
        let current = observation(quantity: 850, price: 10.8, date: .now)
        let result = ComparisonEngine.compare(current: current, previous: old)

        XCTAssertEqual(result.sizeChange ?? 0, -0.15, accuracy: 0.0001)
        XCTAssertEqual(result.priceChange ?? 0, 0.08, accuracy: 0.0001)
        XCTAssertEqual(result.unitPriceChange ?? 0, 0.270588, accuracy: 0.0001)
        XCTAssertEqual(result.status, .shrinkflation)
    }

    func testDifferentQuantityDimensionsAreNotCompared() {
        let old = observation(quantity: 100, unit: .gram, price: 5)
        let current = observation(quantity: 10, unit: .item, price: 5, date: .now)
        let result = ComparisonEngine.compare(current: current, previous: old)
        XCTAssertNil(result.unitPriceChange)
    }

    func testDifferentSupermarketsStillRevealPackageChangeButDoNotScorePrice() {
        var old = observation(quantity: 100, price: 5)
        old.store = "Walmart"
        var current = observation(quantity: 90, price: 5, date: .now)
        current.store = "Target"

        let result = ComparisonEngine.compare(current: current, previous: old)

        XCTAssertEqual(result.sizeChange ?? 0, -0.10, accuracy: 0.0001)
        XCTAssertNil(result.unitPriceChange)
        XCTAssertFalse(result.priceIsComparable)
        XCTAssertEqual(result.status, .packageChange)
    }

    func testOptionalPriceStillCreatesPackageEvidence() {
        let old = observation(quantity: 100, price: nil)
        let current = observation(quantity: 90, price: nil, date: .now)
        let result = ComparisonEngine.compare(current: current, previous: old)
        XCTAssertEqual(result.sizeChange ?? 0, -0.10, accuracy: 0.0001)
        XCTAssertEqual(result.status, .packageChange)
        XCTAssertNil(result.extraCostPerPack)
    }

    func testShelfPriceExtractionPrefersCurrencyValue() {
        XCTAssertEqual(ShelfPriceScannerView.extractPrice(from: "SAVE 10%  $4.99"), Decimal(string: "4.99"))
        XCTAssertEqual(ShelfPriceScannerView.extractPrice(from: "US$ 12,49"), Decimal(string: "12.49"))
    }

    func testMoneyKeypadNinetyNineCentShortcutKeepsEnteredDollars() {
        var input = MoneyKeypadInput()
        input.appendDigit("2")
        input.applyCents(99)
        XCTAssertEqual(input.value, Decimal(string: "2.99")!)
    }

    func testMoneyKeypadZeroCentShortcutKeepsEnteredDollars() {
        var input = MoneyKeypadInput()
        input.appendDigit("2")
        input.applyCents(0)
        XCTAssertEqual(input.value, Decimal(string: "2.00")!)
    }

    func testMoneyKeypadNormalDigitEntryStillUsesCents() {
        var input = MoneyKeypadInput()
        input.appendDigit("2")
        input.appendDigit("9")
        input.appendDigit("9")
        XCTAssertEqual(input.value, Decimal(string: "2.99")!)
    }

    private func observation(
        quantity: Double,
        unit: QuantityUnit = .gram,
        price: Decimal?,
        date: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Observation {
        Observation(
            id: UUID(), tripID: UUID(), familyID: "test-family", barcode: "00036000291452",
            name: "Test Product", brand: "", variant: "", category: "Food",
            quantityValue: quantity, quantityUnit: unit, packCount: 1,
            price: price, currency: .usd, store: "Test Supermarket", branch: "",
            channel: .inStore, priceType: .regular, source: .user, matchConfidence: 1,
            decision: .none, purchaseQuantity: 1, observedAt: date, isDraft: false
        )
    }
}
