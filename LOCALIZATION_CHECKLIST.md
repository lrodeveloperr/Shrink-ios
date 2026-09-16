# Localization and release checklist

Locales: English (`en`) and Puerto Rico-aware Latin American Spanish (`es-419`). Region and language are independent. The supported regions are the United States and Puerto Rico; all visible money uses `$`.

## Automated code-only checks

- [ ] Exactly 198 strings and one plural key exist in each locale.
- [ ] English and Spanish keys, format placeholders, and plural forms match.
- [ ] No unsupported locale, country selector, or alternate currency resource remains.
- [ ] Localized VoiceOver labels cover scan, torch, retry, manual entry, history deletion, undo, and purchase actions.
- [ ] Python scripts compile and static release validation passes in sample-ad mode.
- [ ] SQLite integrity, row-count, uniqueness, provenance, barcode, correction, and semantic-expression audits pass.
- [ ] `git diff --check` passes.

## Independent approvals

- [ ] Shopper/product reviewer approves every locked behavior and both languages from the exact final commit.
- [ ] Expert iOS/data reviewer approves architecture, accessibility, StoreKit, advertising, barcode normalization, USDA provenance, workflow safeguards, and the exact final commit.
- [ ] Any reviewer finding is remediated and both reviewers re-approve the resulting commit.

## External release tasks

- [ ] Configure the non-consumable in App Store Connect.
- [ ] Replace Google sample ad identifiers only for an approved production archive.
- [ ] Run Xcode build, Swift tests, simulator/device, camera, purchase, and accessibility checks on Apple hardware.
- [ ] Upload to TestFlight only through explicit manual confirmation or a deliberate upload-marker commit.
