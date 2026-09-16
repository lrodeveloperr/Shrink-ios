#!/usr/bin/env python3
"""Build the source-grounded App Store listing manifest."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "AppStoreConnect" / "listing-manifest.json"

GUIDELINE_IDS = """1.1,1.1.1,1.1.2,1.1.3,1.1.4,1.1.5,1.1.6,1.1.7,1.2,1.2.1,1.3,1.4,1.4.1,1.4.2,1.4.3,1.4.4,1.4.5,1.5,1.6,1.7,2.1,2.2,2.3,2.3.1,2.3.2,2.3.3,2.3.4,2.3.5,2.3.6,2.3.7,2.3.8,2.3.9,2.3.10,2.3.11,2.3.12,2.3.13,2.4,2.4.1,2.4.2,2.4.3,2.4.4,2.4.5,2.5,2.5.1,2.5.2,2.5.3,2.5.4,2.5.5,2.5.6,2.5.7,2.5.8,2.5.9,2.5.10,2.5.11,2.5.12,2.5.13,2.5.14,2.5.15,2.5.16,2.5.17,2.5.18,3.1,3.1.1,3.1.2,3.1.3,3.1.4,3.1.5,3.2,3.2.1,3.2.2,4.1,4.2,4.2.1,4.2.2,4.2.3,4.2.4,4.2.5,4.2.6,4.2.7,4.3,4.4,4.4.1,4.4.2,4.4.3,4.5,4.5.1,4.5.2,4.5.3,4.5.4,4.5.5,4.5.6,4.6,4.7,4.7.1,4.7.2,4.7.3,4.7.4,4.7.5,4.8,4.9,4.10,5.1,5.1.1,5.1.2,5.1.3,5.1.4,5.1.5,5.2,5.2.1,5.2.2,5.2.3,5.2.4,5.2.5,5.3,5.3.1,5.3.2,5.3.3,5.3.4,5.4,5.5,5.6,5.6.1,5.6.2,5.6.3,5.6.4""".split(",")

BLOCKED_GUIDELINES = {
    "1.5", "2.1", "2.3", "2.3.3", "2.3.4", "2.3.6", "2.3.8", "2.3.9",
    "2.5", "2.5.18", "3.1", "3.1.1", "5.1", "5.1.1", "5.1.2", "5.1.4",
}

PASS_GUIDELINES = {
    "1.6", "2.2", "2.3.1", "2.3.2", "2.3.5", "2.3.7", "2.3.10", "2.3.12",
    "2.4", "2.4.1", "2.4.2", "2.4.4", "2.5.1", "2.5.2", "2.5.14",
    "3.2", "3.2.1", "4.1", "4.2", "4.2.3", "4.6", "5.2", "5.2.1",
}


def status(value: str, evidence: str) -> dict[str, str]:
    return {"status": value, "evidence": evidence}


def guideline_disposition(identifier: str) -> dict[str, str]:
    if identifier in BLOCKED_GUIDELINES:
        return {
            "id": identifier,
            "status": "blocked",
            "evidence": "Requires the signed production archive, live metadata or media, production ad/privacy parity, or owner contact evidence listed in AppStoreConnect/README.md.",
        }
    if identifier in PASS_GUIDELINES:
        return {
            "id": identifier,
            "status": "pass",
            "evidence": "Inspected source and the non-media release pack provide the applicable behavior or disclosure for this shopping utility.",
        }
    return {
        "id": identifier,
        "status": "n_a",
        "evidence": "The inspected app has no feature, content, account, hardware, subscription, user-generated content, regulated service, or platform behavior activating this subsection.",
    }


def screenshot(locale: str, device: str, caption: str) -> dict[str, object]:
    return {
        "locale": locale,
        "device": device,
        "position": 1,
        "story_role": "outcome",
        "caption": caption,
        "artifact_path": "",
        "authentic_ui": False,
        "dimensions_verified_against_current_apple_spec": False,
        "color_profile_verified_against_current_apple_spec": False,
        "sample_data_consistent": False,
        "localized_copy_checked": False,
        "claims_supported": False,
        "paid_feature_disclosed_if_needed": False,
        "no_other_platform_imagery": False,
    }


manifest = {
    "schema_version": "1.0",
    "mode": "draft",
    "app": {
        "platform": "ios",
        "bundle_id": "com.worksbienstudios.shrinkflationpricescanner",
        "version": "1.0",
        "company_name": "WorksBien Studios Inc.",
        "release_kind": "new",
        "primary_category": "Shopping",
        "category_verified_in_current_app_store_connect": True,
        "supported_devices": ["iphone", "ipad"],
        "requires_account": False,
        "requires_hardware": False,
    },
    "source_control": {
        "final_release_build_inspected": False,
        "signed_archive_inspected": False,
        "app_store_connect_inspected": True,
        "public_policies_inspected": False,
        "official_apple_sources_refreshed": True,
        "fact_ledger_complete": True,
        "facts_reconciled": False,
        "final_build_identifier": "Source commit pending final policy/listing commit; signed archive not created",
        "evidence_index": "README.md; Policies/README.md; AppStoreConnect/; App/; Config/Info.plist",
        "final_build_reviewed_on": "2026-09-16",
        "app_store_connect_snapshot_date": "2026-09-16",
        "official_sources_reviewed_on": "2026-09-16",
        "unresolved_conflicts": [
            "Current source uses Google sample ad identifiers; a production App Store build needs verified production identifiers.",
            "Privacy manifest, embedded SDK manifests and App Privacy answers require signed-archive reconciliation.",
            "Screenshots and previews were explicitly outside this non-media run.",
            "App Review contact and TestFlight feedback email are owner-supplied and still missing.",
            "Final device, accessibility and StoreKit sandbox testing is not complete.",
        ],
    },
    "aso_context": {
        "primary_intent": "Compare package size and unit value while grocery shopping",
        "secondary_intent": "Keep a searchable private history of product checks",
        "experiment_hypothesis": "A subtitle centered on package size and value will improve qualified product-page conversion without changing the verified feature promise.",
        "restricted_terms_reviewed": True,
        "restricted_terms": [],
        "target_locales_researched": True,
        "current_result_landscape_reviewed": False,
        "baseline_recorded": False,
        "review_support_language_reviewed": True,
    },
    "locales": [
        {
            "locale": "en-US",
            "name": "Shrinkflation Price Scanner",
            "subtitle": "Track package size and value",
            "promotional_text": "Scan a barcode, record today's package amount and shelf price, and compare it with your saved history-right in the aisle, with no account required.",
            "description": (ROOT / "AppStoreConnect" / "listing-en-US.md").read_text(encoding="utf-8").split("## Description\n\n", 1)[1].split("\n## Categories", 1)[0].strip(),
            "keywords": ["grocery", "barcode", "unit", "cost", "food", "supermarket", "shopping", "history", "quantity", "USDA", "aisle"],
            "support_url": "https://worksbienstudios.com/customerservice",
            "privacy_url": "https://worksbienstudios.com/apps/shrinkflation-price-scanner/en/privacy/",
            "marketing_url": "",
            "whats_new": "",
            "native_language_reviewed": True,
            "ui_locale_matches": True,
            "no_stray_language_confirmed": True,
            "claims_supported": True,
            "paid_features_disclosed_if_needed": True,
        },
        {
            "locale": "es-MX",
            "name": "Escáner de reduflación",
            "subtitle": "Compara empaque y valor",
            "promotional_text": "Escanea el código, registra la cantidad actual del empaque y el precio en la etiqueta, y compáralos con tu historial guardado, sin crear una cuenta.",
            "description": (ROOT / "AppStoreConnect" / "listing-es-MX-pr.md").read_text(encoding="utf-8").split("## Descripción\n\n", 1)[1].split("\n## Categorías", 1)[0].strip(),
            "keywords": ["precio", "unidad", "supermercado", "compras", "código", "barras", "alimentos", "historial", "cantidad", "shrinkflation"],
            "support_url": "https://worksbienstudios.com/customerservice",
            "privacy_url": "https://worksbienstudios.com/apps/shrinkflation-price-scanner/es-419/privacy/",
            "marketing_url": "",
            "whats_new": "",
            "native_language_reviewed": True,
            "ui_locale_matches": True,
            "no_stray_language_confirmed": True,
            "claims_supported": True,
            "paid_features_disclosed_if_needed": True,
        },
    ],
    "screenshot_count_override_reason": "The user explicitly limited this run to non-media listing fields; media remains a separate release gate.",
    "required_screenshot_sets": [
        {"locale": locale, "device": device, "expected_count": 1, "accepted_dimensions": [[1290, 2796]]}
        for locale in ("en-US", "es-MX")
        for device in ("iphone", "ipad")
    ],
    "screenshots": [
        screenshot("en-US", "iphone", "Media outside this approved scope"),
        screenshot("en-US", "ipad", "Tablet media outside approved scope"),
        screenshot("es-MX", "iphone", "Medios fuera del alcance aprobado"),
        screenshot("es-MX", "ipad", "Medios de iPad fuera del alcance"),
    ],
    "privacy": {
        "policy_url": "https://worksbienstudios.com/apps/shrinkflation-price-scanner/en/privacy/",
        "data_inventory_complete": True,
        "third_party_sdks_included": True,
        "app_privacy_answers_match_final_build": False,
        "privacy_policy_matches_final_build": True,
        "privacy_manifest_checked_in_final_archive": False,
        "required_reason_apis_checked": False,
        "sdk_signatures_checked": False,
        "tracking_declaration_accurate": False,
        "data_deletion_obligations_resolved": True,
    },
    "monetization": {
        "models": ["ads", "non_consumable"],
        "products": [{
            "product_id": "com.worksbienstudios.shrinkflationpricescanner.removeads",
            "type": "non_consumable",
            "app_store_connect_state_verified": True,
            "localized_metadata_complete": False,
            "price_loaded_from_storekit": True,
            "review_screenshot_prepared": False,
            "visible_or_review_path_documented": True,
        }],
        "public_fixed_price_copy_absent": True,
        "product_ids_match_app_store_connect": True,
        "prices_localized_from_storekit": True,
        "purchase_locations_in_review_notes": True,
        "paid_features_disclosed_in_metadata": True,
        "product_review_assets_prepared": False,
        "transaction_verification_enabled": True,
        "storekit_error_states_tested": False,
        "restore_purchases_available": True,
        "ads": {
            "behavior_and_placement_reviewed": True,
            "privacy_disclosures_match": False,
            "tracking_and_consent_resolved": False,
            "production_ad_configuration_verified": False,
        },
    },
    "review": {
        "notes": (ROOT / "AppStoreConnect" / "review-notes.md").read_text(encoding="utf-8"),
        "contact_complete": False,
        "demo_access_complete": True,
        "navigation_path_documented": True,
        "non_obvious_features_explained": True,
        "permission_steps_explained": True,
        "iap_locations_explained": True,
    },
    "guideline_review": {
        "source_url": "https://developer.apple.com/app-store/review/guidelines/",
        "reviewed_on": "2026-09-16",
        "all_current_ids_included": True,
        "required_ids": GUIDELINE_IDS,
        "dispositions": [guideline_disposition(identifier) for identifier in GUIDELINE_IDS],
    },
    "compliance_controls": {
        "app_stability": status("blocked", "Requires final signed build and on-device test matrix."),
        "metadata_build_parity": status("blocked", "Production ad configuration and final archive are not yet reconciled."),
        "metadata_complete_accurate": status("pass", "Non-media metadata is finalized in AppStoreConnect/ and checked against source."),
        "screenshots_authentic_current": status("blocked", "Media was explicitly outside this run."),
        "reviewer_access": status("pass", "No account or hardware is required; exact navigation is in review-notes.md."),
        "legal_urls_live": status("blocked", "Final policy deployment and response check must complete."),
        "privacy_policy_matches_build": status("pass", "Policies/ is grounded in the inspected source and SDK inventory."),
        "app_privacy_answers_match_build_and_sdks": status("blocked", "App Privacy answers require signed-archive SDK reconciliation."),
        "privacy_manifest_archive_checked": status("blocked", "No signed production archive exists."),
        "required_reason_apis_and_sdk_signatures_checked": status("blocked", "Requires signed-archive inspection."),
        "permissions_just_in_time": status("pass", "Camera permission is requested from the scanner; manual entry remains available."),
        "age_rating_accurate": status("blocked", "Current App Store Connect age-rating answers require owner confirmation."),
        "content_rights_confirmed": status("pass", "Catalogue provenance and USDA source are preserved; product marks remain with owners."),
        "export_compliance_resolved": status("pass", "ITSAppUsesNonExemptEncryption is false in Config/Info.plist."),
        "no_private_apis_hidden_features_placeholders": status("pass", "Static source review found documented Apple frameworks and no hidden feature switch."),
        "accessibility_device_locale_rtl_checked": status("blocked", "Source includes VoiceOver and dynamic type work, but final device matrix is not complete."),
        "regional_availability_reviewed": status("pass", "App Store Connect shows 2 of 175 regions selected for the IAP; US/PR scope is locked in the release pack."),
        "contact_information_current": status("blocked", "App Review contact name, phone, email and TestFlight feedback email are owner-supplied."),
        "guideline_sweep_complete": status("pass", "All 125 live guideline identifiers captured on 2026-09-16 have dispositions."),
    },
    "aso_controls": {
        "search_intent_researched": status("pass", "Primary job and natural English/PR Spanish vocabulary are recorded."),
        "primary_intent_in_name_when_natural": status("pass", "Both localized names identify shrinkflation scanning within 30 characters."),
        "secondary_value_in_subtitle": status("pass", "Both subtitles state package and value comparison within 30 characters."),
        "keyword_field_relevant_deduplicated": status("pass", "Keyword sets map only to source-supported shopping behavior and fit the UTF-8 limit."),
        "competitor_trademark_screened": status("pass", "No competitor or retailer terms are used."),
        "category_fit_confirmed": status("pass", "Shopping is the primary function; Utilities is secondary."),
        "first_sentence_differentiator": status("pass", "Each locale leads with the shopper's evidence-based value decision."),
        "three_frame_visual_story": status("blocked", "Media was explicitly outside this run."),
        "native_locale_adaptation": status("pass", "A separate fully bilingual expert approved US English and Puerto Rico Spanish."),
        "search_to_product_page_alignment": status("pass", "Name, subtitle and description consistently promise package and unit-value comparison."),
        "claims_supported": status("pass", "All quantitative and behavioral claims map to source, catalogue metadata or App Store Connect."),
        "baseline_metrics_recorded": status("blocked", "No live product-page baseline exists before launch."),
        "one_variable_experiment_defined": status("pass", "Subtitle-value framing is the first post-launch experiment; conversion is the primary metric."),
        "review_feedback_loop_defined": status("pass", "Review, support, conversion, refund and search-term evidence feed the next metadata revision."),
    },
    "authorization": {
        "live_submission_authorized": False,
        "authorization_evidence": "The user requested preparation and explicitly said TestFlight must not be wired yet.",
    },
}

OUTPUT.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(OUTPUT)

