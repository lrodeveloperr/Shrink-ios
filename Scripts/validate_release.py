#!/usr/bin/env python3
"""Static release guards that run without Xcode or Swift execution."""

import argparse
from pathlib import Path
import re
import sqlite3

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "App"


def require(source: str, needle: str, message: str) -> None:
    if needle not in source:
        raise SystemExit(f"Release check failed: {message}")


def forbid(source: str, needle: str, message: str) -> None:
    if needle.lower() in source.lower():
        raise SystemExit(f"Release check failed: {message}")


parser = argparse.ArgumentParser()
parser.add_argument("--sample-ads", action="store_true")
arguments = parser.parse_args()

content = (APP / "Features" / "ContentView.swift").read_text(encoding="utf-8")
models = (APP / "Models" / "Models.swift").read_text(encoding="utf-8")
scanner = (APP / "Features" / "ScannerViews.swift").read_text(encoding="utf-8")
database = (APP / "Data" / "Database.swift").read_text(encoding="utf-8")
monetization = (APP / "Monetization" / "Monetization.swift").read_text(encoding="utf-8")
app = (APP / "ShrinkflationPriceScannerApp.swift").read_text(encoding="utf-8")
project = (ROOT / "ShrinkflationPriceScanner.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")
workflow = (ROOT / ".github" / "workflows" / "testflight.yml").read_text(encoding="utf-8")
all_text = "\n".join([content, models, scanner, database, monetization, app, project])

for needle, message in [
    ("VStack(spacing: 0)", "TabView/banner sibling layout is missing"),
    ("Color.clear.frame(height: 8)", "the required navigation/banner separation is missing"),
    (".buttonStyle(.borderedProminent)", "the native primary scan button is missing"),
    ("entry.product_not_found", "the deterministic unknown-product state is missing"),
    ("FamilyLinkerView", "the searchable saved-family linker is missing"),
    ("Task.sleep(for: .seconds(8))", "the eight-second undo window is missing"),
    ("chartYScale(domain:", "adaptive chart scaling is missing"),
    ("manual.eight_digit_required", "manual 8-digit barcode disambiguation is missing"),
]:
    require(content, needle, message)

for needle, message in [
    ("guard let upca = expandUPCE(digits), isValidGTIN(upca)", "UPC-E is not validated after UPC-A expansion"),
    ("guard v.count == 8, v[0] == 0 || v[0] == 1", "UPC-E number-system validation is missing"),
]:
    require(models, needle, message)

for needle, message in [
    (".gs1DataBar", "GS1 DataBar scanning is missing"),
    (".gs1DataBarExpanded", "GS1 DataBar Expanded scanning is missing"),
    (".gs1DataBarLimited", "GS1 DataBar Limited scanning is missing"),
    (".continuousAutoFocus", "continuous autofocus is missing"),
    (".continuousAutoExposure", "continuous auto-exposure is missing"),
    ("metadataOutputRectConverted", "central scan region conversion is missing"),
    ("deadline: .now() + 18", "18-second scanner timeout is missing"),
]:
    require(scanner, needle, message)

for needle, message in [
    ("source_description", "USDA raw-source provenance is missing"),
    ("original_gtin_length", "original GTIN length is missing"),
    ("DELETE FROM observations WHERE currency <> 'USD'", "retired-currency migration is missing"),
    ("recentProducts()", "uncapped saved-family retrieval is missing"),
]:
    require(database, needle, message)

for needle, message in [
    ("case googleSampleTest", "sample-ad state is missing"),
    ("case production", "production-ad state is missing"),
    ("case invalid", "invalid-ad state is missing"),
    ("await refreshEntitlements()", "pre-interface entitlement resolution is missing"),
    ("if !adLoaded || !adManager.canRequestAds", "the house banner does not cover every no-ad state"),
    ("if !canRequestAds { adLoaded = false }", "stale ad-loaded state is not reset when permission changes"),
    (".accessibilityHidden(!adLoaded)", "the unloaded Google banner remains exposed to accessibility"),
    ("dynamicTypeSize.isAccessibilitySize", "the house banner has no accessibility-size layout"),
    (".accessibilityValue(Text(verbatim:", "the house-banner price is missing from its accessibility value"),
]:
    require(monetization, needle, message)

for source, needle, message in [
    (all_text, "canada", "Canadian runtime/configuration text remains"),
    (all_text, "case cad", "CAD runtime support remains"),
    (project, "fr-CA", "French locale remains in the Xcode project"),
    (database, "URLSession", "runtime product networking remains"),
]:
    forbid(source, needle, message)

require(project, "CURRENT_PROJECT_VERSION = 8;", "build number is not 8")
require(project, "MARKETING_VERSION = 1.0;", "version is not 1.0")
require(workflow, "[upload-shrink-testflight]", "deliberate upload marker gate is missing")
require(workflow, "workflow_dispatch", "manual TestFlight confirmation path is missing")

if arguments.sample_ads:
    require(monetization, "googleSampleAppID", "Google sample app identifier guard is missing")
    require(monetization, "googleSampleBannerID", "Google sample banner identifier guard is missing")
    sample_branch = re.search(r"case \.googleSampleTest:(.*?)(?:case \.invalid:)", monetization, re.S)
    if sample_branch is None or "Consent" in sample_branch.group(1):
        raise SystemExit("Release check failed: sample-ad mode must bypass UMP")

catalogue = APP / "Resources" / "catalogue.sqlite3"
with sqlite3.connect(f"file:{catalogue}?mode=ro", uri=True) as connection:
    if connection.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
        raise SystemExit("Release check failed: bundled catalogue is corrupt")
    columns = {row[1] for row in connection.execute("PRAGMA table_info(products)")}
    required = {"gtin14", "original_gtin", "original_gtin_length", "usda_fdc_id", "source_description", "product_name", "family_id", "market_country"}
    if not required.issubset(columns):
        raise SystemExit(f"Release check failed: catalogue is missing {sorted(required - columns)}")
    semantic_columns = {row[1] for row in connection.execute("PRAGMA table_info(semantic_masks)")}
    semantic_required = {"gtin14", "reason", "source_sha256", "product_name"}
    if not semantic_required.issubset(semantic_columns):
        raise SystemExit(f"Release check failed: semantic audit is missing {sorted(semantic_required - semantic_columns)}")
    if connection.execute("SELECT COUNT(*) FROM semantic_masks").fetchone()[0] != 152:
        raise SystemExit("Release check failed: semantic audit does not contain 152 identities")

print("Static release checks passed.")
