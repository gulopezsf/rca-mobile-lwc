# Mobile TLE Bundle Configurator for Revenue Cloud Advanced

A **mobile-first Lightning Web Component** for managing Quotes in Salesforce Revenue Cloud Advanced (RCA). Replaces the desktop-oriented standard Quote workspace with a touch-optimized, card-based interface designed for field sales and Solution Engineer demos.

---

## Features

- **Card-based quote line display** — Each line item rendered as a mobile-friendly card with product image, pricing, and actions
- **Inline editing** — Tap-to-edit for Quantity, Discount, and Unit Price with immediate repricing via PlaceQuote API
- **Bundle configuration** — Full 3-level nested bundle configurator with group cardinality validation and attribute editing
- **Product browser** — Add products to quotes with search, category filtering, and selling model selection
- **Multi-language support** — Custom Labels for all UI strings (Spanish included out of the box)
- **Quote summary** — Real-time subtotal, discount, and grand total display

---

## Prerequisites

- **Revenue Cloud Advanced (RCA)** must be enabled on the target org
- PlaceQuote API access (comes with RCA license)
- API version 66.0+

---

## Installation

### Method 1: 1GP Unmanaged Package (Recommended)

**Production / Demo orgs:**
```
https://login.salesforce.com/packaging/installPackage.apexp?p0=04tJ9000000xheZ
```

**Sandbox orgs:**
```
https://test.salesforce.com/packaging/installPackage.apexp?p0=04tJ9000000xheZ
```

### Method 2: Metadata Deploy via SF CLI

```bash
cd Atlas
sf project deploy start --manifest manifest/package.xml --target-org <YOUR_ORG_ALIAS>
```

---

## Post-Install Setup

1. **Verify RCA is enabled** on the target org
2. **Add `mobileTransactionLineEditor`** to a Quote Lightning Record Page via Lightning App Builder
3. **Assign permissions** — users need Read/Edit on Quote and QuoteLineItem, plus PlaceQuote API access
4. **Test with a bundle product** — Open a Quote with a bundle, tap a line's action menu, select "Configure"

---

## Architecture

```
PlaceQuote-Only + SOQL-Only

Reads  → Direct SOQL queries (fast, no API overhead)
Writes → PlaceQuote API exclusively (triggers RCA pricing engine)
```

All pricing-sensitive mutations (Quantity, Discount, UnitPrice) route through the PlaceQuote API via `PlaceQuote.PlaceQuoteRLMApexProcessor.execute()`. Raw DML is **never** used for pricing fields — it bypasses the RCA pricing engine.

### Component Hierarchy

| Component | Purpose |
|-----------|---------|
| `mobileTransactionLineEditor` | Parent container — orchestrates the full TLE experience |
| `mobileTleLineList` | Scrollable list of quote line cards |
| `mobileTleLineCard` | Individual quote line card with pricing and actions |
| `mobileTleBottomSheet` | iOS-style action sheet for line operations |
| `mobileTleProductBrowser` | Product search and add-to-quote interface |
| `mobileTleProductCard` | Product card within the browser |
| `mobileTleConfigurator` | Bundle configurator main component |
| `mobileTleConfigGroup` | Product Component Group renderer with cardinality validation |
| `mobileTleConfigOption` | Individual option card with checkbox and quantity |
| `mobileTleConfigAttributes` | Attribute editing panel (Picklist, Number, Text) |
| `mobileTleUtils` | Shared utility functions |
| `quoteLineBundleEditor` | Desktop-oriented bundle editor |
| `dealDeskOptimizer` | Deal desk optimization component |

### Apex Classes

| Class | Purpose |
|-------|---------|
| `MobileTleController` | Main controller — line fetching, PlaceQuote repricing, bundle config |
| `QuoteLineEditorController` | Desktop editor controller (FieldSet-based) |

---

## Project Structure

```
Atlas/
├── force-app/main/default/
│   ├── classes/          # 3 Apex classes
│   ├── lwc/              # 13 LWC bundles
│   ├── labels/           # 16 Custom Labels (ES/EN)
│   └── objects/          # FieldSet: Quote_Line_Editor_Columns
├── manifest/
│   └── package.xml       # 114 components
├── docs/
│   ├── recipes/          # Implementation recipes
│   │   ├── placequote-patterns.md
│   │   ├── bundle-configuration.md
│   │   └── mobile-lwc-architecture.md
│   └── references/
│       └── placequote-super-reference.md
└── README.md
```

---

## Documentation

### Recipes

| Recipe | Description |
|--------|-------------|
| [PlaceQuote Patterns](docs/recipes/placequote-patterns.md) | All PlaceQuote API patterns: add, update, clone, delete, ParentQuoteLineItemId workaround |
| [Bundle Configuration](docs/recipes/bundle-configuration.md) | Data model chain, loading config, saving config, nested bundles, attribute handling |
| [Mobile LWC Architecture](docs/recipes/mobile-lwc-architecture.md) | Component hierarchy, event patterns, design decisions |

### References

| Reference | Description |
|-----------|-------------|
| [PlaceQuote Super Reference](docs/references/placequote-super-reference.md) | Complete API reference for the PlaceQuote namespace — classes, enums, code examples, best practices |

---

## Changelog

### v1.2 (June 13, 2026) — Current

- **Fix: Repricing bug (BUG-CDO-001)** — Quantity/Discount/UnitPrice inline edits now route through PlaceQuote API instead of raw DML, correctly triggering the RCA pricing engine
- **Fix: Missing FieldSet** — Added `Quote_Line_Editor_Columns` FieldSet on QuoteLineItem

### v1.1 (June 12, 2026)

- Added FieldSet metadata for `Quote_Line_Editor_Columns`
- Updated `package.xml` with FieldSet type entry

### v1.0 (June 11, 2026)

- Initial release: 13 LWC bundles, 3 Apex classes, 16 Custom Labels
- Full Mobile TLE with bundle configurator
- PlaceQuote-based repricing and product addition
- Multi-language support (ES/EN)

---

## License

This project is provided as an unmanaged package for Salesforce Solution Engineers. It is not an official Salesforce product.
