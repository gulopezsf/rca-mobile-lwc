# Mobile TLE Bundle Configurator

> A mobile-first Lightning Web Component (LWC) for quoting, pricing, and bundle configuration in **Revenue Cloud Advanced (RCA)**.

**Version:** 1.4
**API Version:** 66.0
**Package Id:** `04tJ9000000xhee`

---

## Prerequisites

> **Revenue Cloud Advanced (RCA) is required.** This component depends on RCA-specific sObjects, fields, and Apex APIs that do not exist in standard Salesforce orgs. Installation on an org without RCA will fail with compilation errors (176+ errors reported on standard SDO trial orgs).

### Required Org Capabilities

| Requirement | Details |
|-------------|---------|
| **Revenue Cloud Advanced license** | The org must have RCA (also known as Agentforce Revenue Management) enabled and provisioned. Standard Sales Cloud / SDO trial orgs do **not** include RCA. |
| **PlaceQuote Apex API** | The `PlaceQuote` namespace must be accessible. This provides `PlaceQuote.PlaceQuoteRLMApexProcessor`, `PlaceQuote.GraphRequest`, and all related classes used for pricing and configuration. |
| **RCA sObjects** | `QuoteLineItemAttribute` — stores bundle attribute values per quote line. `QuoteLineRelationship` — links parent/child bundle quote lines. `ProductSellingModel` — defines selling model (one-time, evergreen, term-defined). |
| **RCA fields on QuoteLineItem** | `ParentQuoteLineItemId` — parent reference for bundle child lines. `BillingFrequency` — billing cadence for term-based products. `ProductSellingModelId` — link to the selling model. `NetUnitPrice` — calculated net price per unit. |

### Compatible Org Types

| Org Type | Compatible? | Notes |
|----------|:-----------:|-------|
| RCA-enabled sandbox | **Yes** | Recommended for development and testing |
| CDO org with RCA provisioned | **Yes** | Demo org with RCA package installed |
| Partner Developer org with RCA | **Yes** | Must have RCA trial or license |
| Standard SDO / trial org | **No** | Missing RCA sObjects and PlaceQuote namespace — 176+ compilation errors |
| Production org with RCA license | **Yes** | Full support |
| Scratch org with RCA features | **Yes** | Must enable Revenue Cloud features in scratch org definition |

---

## Pre-Install Checklist

Run through this checklist **before** attempting installation:

- [ ] Org has **Revenue Cloud Advanced** license enabled (Setup → Company Information → check for RCA/Revenue Lifecycle Management feature)
- [ ] **PlaceQuote API** is accessible (`PlaceQuote` namespace visible — test by opening Developer Console and typing `PlaceQuote.GraphRequest g;`)
- [ ] **QuoteLineItem** has RCA-specific fields: `ParentQuoteLineItemId`, `BillingFrequency`, `ProductSellingModelId`, `NetUnitPrice` (check in Object Manager → QuoteLineItem → Fields)
- [ ] **QuoteLineItemAttribute** object exists (Object Manager → search for "QuoteLineItemAttribute")
- [ ] **QuoteLineRelationship** object exists (Object Manager → search for "QuoteLineRelationship")
- [ ] **ProductSellingModel** object exists (Object Manager → search for "ProductSellingModel")

> **Quick validation:** If any of the above items fail, the org does **not** have RCA and this package cannot be installed. Contact your Salesforce account team to enable Revenue Cloud Advanced, or use an RCA-provisioned demo/sandbox org.

---

## Installation

### Option 1: 1GP Unmanaged Package (Recommended)

**Production / Demo orgs:**
```
https://login.salesforce.com/packaging/installPackage.apexp?p0=04tJ9000000xhee
```

**Sandbox orgs:**
```
https://test.salesforce.com/packaging/installPackage.apexp?p0=04tJ9000000xhee
```

### Option 2: Metadata Deploy

```bash
sf project deploy start --manifest manifest/package.xml --target-org <YOUR_ORG_ALIAS>
```

### Post-Install Steps

1. Assign the **Mobile TLE** permission set to users who need access.
2. Verify the **Quote_Line_Editor_Columns** FieldSet exists on `QuoteLineItem` (should be included in the package).
3. Open a Quote record and launch the Mobile TLE component from the action menu.

---

## Architecture

The component follows a **PlaceQuote-Only + SOQL-Only** architecture:

- **All pricing** flows through the PlaceQuote Apex API — no raw DML on QuoteLineItems.
- **All data reads** use SOQL queries — no UI API, no wire adapters for RCA data.
- **Bundle configuration** uses PlaceQuote with full configuration validation (no `Skip`).
- **Inline edits** trigger PlaceQuote PATCH repricing for real-time price updates.

```
┌─────────────────┐     ┌──────────────────┐     ┌───────────────┐
│  Mobile LWC     │────▶│  Apex Controller  │────▶│  PlaceQuote   │
│  (UI Layer)     │◀────│  (SOQL + DML)     │◀────│  Engine (RCA) │
└─────────────────┘     └──────────────────┘     └───────────────┘
```

## Component Inventory

| Component | Type | Purpose |
|-----------|------|---------|
| `mobileTleMain` | LWC | Main container — orchestrates quote line editor |
| `mobileTleLineEditor` | LWC | Inline line editing with PlaceQuote repricing |
| `mobileTleBundleConfigurator` | LWC | Bundle attribute selection and configuration |
| `mobileTleProductSearch` | LWC | Product catalog search and add-to-quote |
| `MobileTleController` | Apex | Server-side controller — SOQL queries, PlaceQuote calls |
| `MobileTlePlaceQuoteService` | Apex | PlaceQuote request builder — graph construction, Force/Skip logic |
| `MobileTleTestFactory` | Apex | Test data factory for unit tests |

## Documentation

| File | Description |
|------|-------------|
| `docs/recipes/placequote-patterns.md` | PlaceQuote usage patterns for RCA |
| `docs/recipes/bundle-configuration.md` | Bundle configuration patterns |
| `docs/recipes/mobile-lwc-architecture.md` | Mobile LWC architecture guide |
| `docs/references/PlaceQuote in RCA Super Reference.md` | Complete PlaceQuote API reference |

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-06-10 | Initial release — quote line editor, product search |
| 1.1 | 2026-06-11 | FieldSet fix (Quote_Line_Editor_Columns) |
| 1.2 | 2026-06-12 | Repricing fix (PlaceQuote PATCH), clone attributes |
| 1.3 | 2026-06-13 | CurrencyIsoCode fallback for multi-currency orgs |
| 1.4 | 2026-06-15 | Date serialization fix (yyyy-MM-dd), TermDefined selling model support |

---

## GitHub Repository

```
https://git.soma.salesforce.com/glopez/rca-mobile-lwc
```

---

*Built with the PlaceQuote-Only + SOQL-Only architecture pattern for Revenue Cloud Advanced.*
