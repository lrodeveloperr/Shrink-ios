#!/usr/bin/env python3
"""Static release guards that can run without Xcode."""

from pathlib import Path
import sqlite3

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "App"


def require(source: str, needle: str, message: str) -> None:
    if needle not in source:
        raise SystemExit(f"Release check failed: {message}")


def forbid(source: str, needle: str, message: str) -> None:
    if needle in source:
        raise SystemExit(f"Release check failed: {message}")


content = (APP / "Features" / "ContentView.swift").read_text(encoding="utf-8")
models = (APP / "Models" / "Models.swift").read_text(encoding="utf-8")
database = (APP / "Data" / "Database.swift").read_text(encoding="utf-8")
monetization = (APP / "Monetization" / "Monetization.swift").read_text(encoding="utf-8")
project = (ROOT / "ShrinkflationPriceScanner.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")

for needle, message in [
    ("TabView(selection:", "native Scan/History/Impact tabs are missing"),
    ("barcode.viewfinder", "the native barcode scanner symbol is missing"),
    ("DisclosureGroup", "optional entry details are not folded"),
    ("MoneyKeypad", "the full in-app price keypad is missing"),
    ("Chart(points)", "the native Swift Charts Scorecard chart is missing"),
    ("maxWidth: 680", "the centered iPad reading width is missing"),
    ("StorePickerView", "the supermarket-scoped trip start is missing"),
]:
    require(content, needle, message)

for needle, message in [
    ("priceIsComparable", "retail-context price gating is missing"),
    ("PurchaseDecision", "Bought/Skipped/Switched decisions are missing"),
    ("HistoryFilter", "shared History/Impact filters are missing"),
]:
    require(models, needle, message)

for needle, message in [
    ("trip_id", "trip persistence is missing"),
    ("price_type", "price-type evidence is missing"),
    ("is_draft", "successful captured drafts are missing"),
    ("PRAGMA user_version=2", "database migration version is missing"),
]:
    require(database, needle, message)

require(monetization, "didFailToReceiveAdWithError", "the no-fill house-banner fallback is not wired")
require(project, "productName = GoogleUserMessagingPlatform;", "the Google UMP Swift package product is misconfigured")
forbid(monetization, "purchaseRemoval()", "obsolete StoreKit purchase method remains")
forbid(content, "Basket Guard", "retired Basket Guard copy remains")
forbid(content, "Product catalogue", "removed standalone Product Data settings row remains")
forbid(content, "Report Product", "removed product-report workflow remains")

catalogue = APP / "Resources" / "catalogue.sqlite3"
with sqlite3.connect(catalogue) as connection:
    if connection.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
        raise SystemExit("Release check failed: bundled catalogue is corrupt")
    columns = {row[1] for row in connection.execute("PRAGMA table_info(products)")}
    required = {"gtin14", "family_id", "product_name", "product_name_es", "product_name_fr", "quantity_value", "quantity_unit"}
    if not required.issubset(columns):
        raise SystemExit(f"Release check failed: catalogue is missing {sorted(required - columns)}")

print("Static release checks passed.")
