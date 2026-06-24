# Recipe: Mobile LWC Architecture for RCA

> **Org Compatibility:** This architecture requires an org with **Revenue Cloud Advanced (RCA)** enabled. The component depends on RCA sObjects (`QuoteLineItemAttribute`, `QuoteLineRelationship`, `ProductSellingModel`), RCA fields on `QuoteLineItem` (`ParentQuoteLineItemId`, `BillingFrequency`, `ProductSellingModelId`, `NetUnitPrice`), and the `PlaceQuote` Apex API. Standard SDO/trial orgs are **not compatible** — use an RCA-enabled sandbox or CDO org.

---

## Overview

The Mobile TLE (Table Line Editor) is a mobile-first LWC for quoting in Revenue Cloud Advanced. It follows the **PlaceQuote-Only + SOQL-Only** architecture pattern.

## Architecture Principles

### PlaceQuote-Only
All pricing and configuration operations route through the PlaceQuote Apex API. No raw DML is performed on `QuoteLineItem` records — this ensures the RCA engine always validates pricing, configuration, and calculated fields.

### SOQL-Only
All data reads use direct SOQL queries in Apex. No UI API, no `getRecord` wire adapters for RCA data. This gives full control over query shape, related records, and field access.

## Component Structure

```
mobileTleMain (orchestrator)
├── mobileTleLineEditor (inline editing + repricing)
├── mobileTleBundleConfigurator (attribute selection)
└── mobileTleProductSearch (catalog search + add)
```

### Apex Layer

| Class | Responsibility |
|-------|---------------|
| `MobileTleController` | SOQL queries, response shaping, orchestration |
| `MobileTlePlaceQuoteService` | Graph construction, Force/Skip config, PlaceQuote execution |
| `MobileTleTestFactory` | Test data generation for unit tests |

## Key Integration Points

### Inline Edit → Reprice Flow

1. User edits a field (quantity, discount) in `mobileTleLineEditor`
2. LWC calls `MobileTleController.repriceQuoteLine(quoteId, lineId, changedFields)`
3. Controller delegates to `MobileTlePlaceQuoteService.reprice()` which builds a PATCH graph
4. PlaceQuote executes with `Force` pricing, `Skip` configuration
5. Controller re-queries the quote lines and returns fresh data to the LWC

### Add Product → PlaceQuote Flow

1. User selects a product in `mobileTleProductSearch`
2. LWC calls `MobileTleController.addProduct(quoteId, productId, quantity)`
3. Controller builds a POST graph for the new `QuoteLineItem` + PATCH for the parent Quote
4. For bundles: configuration is NOT skipped (engine must validate and auto-create children)
5. Controller re-queries and returns updated line list

## Date Serialization

All date fields passed to PlaceQuote must be serialized as `String` in `yyyy-MM-dd` format:

```apex
body.put('StartDate', String.valueOf(startDate));  // ✅ Correct
body.put('StartDate', startDate);                   // ❌ Silent failure
```

## Prerequisites

Before deploying this component, verify the [Pre-Install Checklist](../../README.md#pre-install-checklist) in the README.

## Compatible Org Types

| Org Type | Compatible? | Notes |
|----------|:-----------:|-------|
| RCA-enabled sandbox | **Yes** | Recommended for development |
| CDO org with RCA provisioned | **Yes** | Best for SE demos |
| Standard SDO / trial org | **No** | 176+ compilation errors |
| Scratch org with RCA features | **Yes** | Enable Revenue Cloud in org definition |

---

*See also: [PlaceQuote Patterns](./placequote-patterns.md) | [Bundle Configuration](./bundle-configuration.md) | [PlaceQuote Super Reference](../references/PlaceQuote%20in%20RCA%20Super%20Reference.md)*
