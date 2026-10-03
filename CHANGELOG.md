# Changelog

All notable changes to the Mobile TLE Bundle Configurator are documented in this file.

---

## [2.1] — 2026-10-02

### Fixed

- **PeriodBoundary mandatory for TermDefined products** — Recent RCA releases made the `PeriodBoundary` field mandatory on `QuoteLineItem` for TermDefined selling model products. Without it, adding products fails with: _"Enter a start proration period with one of these values: AlignToCalendar, Anniversary, DayOfPeriod, or LastDayOfPeriod."_ The controller now sets `PeriodBoundary` and `ProrationPolicyId` automatically.

### Changed

- **SubscriptionTermInfo DTO** — Added `periodBoundary` (String) and `prorationPolicyId` (Id) fields.
- **resolveSubscriptionTermInfo()** — Sets default `PeriodBoundary = 'Anniversary'` and queries the org's `ProrationPolicy` for TermDefined products.
- **addLineViaPlaceQuote()** — Includes `PeriodBoundary` and `ProrationPolicyId` in the PlaceQuote graph when adding products.
- **applyBundleConfigChanges()** — Propagates `PeriodBoundary` and `ProrationPolicyId` to bundle child lines.

---

## [2.0.1] — 2026-06-30

### Fixed

- Attribute persistence via PlaceQuote (10 bug fixes total)
- Bundle child line handling improvements
- UAT passed after 7 rounds of testing

---

## [2.0] — 2026-06-30

### Added

- Bundle attribute configuration UI (`mobileTleBundleConfigurator`)
- Attribute selection and persistence through PlaceQuote engine
- Full bundle cardinality validation

---

## [1.5] — 2026-06-26

### Fixed

- Bundle detection for Configure button on newly added products
- Currency handling improvements for multi-currency orgs
- Roig Arena org compatibility fixes (4 bugs resolved)

---

## [1.4] — 2026-06-15

### Fixed

- Date serialization — all date fields now serialize as `yyyy-MM-dd` strings for PlaceQuote
- TermDefined selling model support (SubscriptionTermUnit, BillingFrequency)

---

## [1.3] — 2026-06-13

### Fixed

- CurrencyIsoCode fallback chain for multi-currency orgs

---

## [1.2] — 2026-06-12

### Fixed

- Repricing fix — PlaceQuote PATCH for inline edits
- Clone attributes on bundle duplication

---

## [1.1] — 2026-06-11

### Fixed

- Quote_Line_Editor_Columns FieldSet missing from package

---

## [1.0] — 2026-06-10

### Added

- Initial release — mobile-first quote line editor
- Product catalog search and add-to-quote
- Inline field editing with PlaceQuote repricing
- PlaceQuote-Only + SOQL-Only architecture
