# Recipe: Bundle Configuration in RCA

> **Org Compatibility:** This recipe requires an org with **Revenue Cloud Advanced (RCA)** enabled. Bundle configuration depends on RCA sObjects (`QuoteLineItemAttribute`, `QuoteLineRelationship`) and the `PlaceQuote` namespace. Standard SDO/trial orgs are **not compatible** — use an RCA-enabled sandbox or CDO org with Revenue Cloud provisioned.

---

## Overview

Bundle configuration in RCA is handled through the PlaceQuote engine. When adding or modifying bundles, the engine validates cardinality rules, auto-creates required child components, and calculates rollup pricing.

## Key Concepts

| Concept | Description |
|---------|-------------|
| **Bundle Parent** | A `QuoteLineItem` representing the top-level bundle product |
| **Bundle Child** | A `QuoteLineItem` linked to the parent via `ParentQuoteLineItemId` |
| **Attributes** | Stored in `QuoteLineItemAttribute` — configuration choices (color, size, options) |
| **Relationships** | `QuoteLineRelationship` links parent and child lines with metadata |
| **Configuration Validation** | The PlaceQuote engine checks required children, min/max cardinality, attribute rules |

## Adding a Bundle — Do NOT Skip Configuration

When adding a bundle parent, the PlaceQuote engine must run configuration to:
1. Validate the bundle structure against product rules
2. Auto-create required child components
3. Set default attribute values
4. Calculate the bundle rollup price

```apex
// For bundles: use Force pricing, DO NOT skip configuration
PlaceQuote.ConfigurationOptionsInput configOptions =
    new PlaceQuote.ConfigurationOptionsInput();
configOptions.pricingPreference = PlaceQuote.PricingPreferenceEnum.Force;
// configOptions.configurationInput is left at default (runs full validation)
```

## Cloning Bundle Attributes

When cloning a quote with bundles, attribute values must be explicitly preserved:

```apex
// Query source attributes
List<QuoteLineItemAttribute> sourceAttrs = [
    SELECT Id, QuoteLineItemId, Name, Value__c, AttributeDefinitionId
    FROM QuoteLineItemAttribute
    WHERE QuoteLineItemId IN :sourceLineIds
];

// After PlaceQuote creates the cloned lines, map attributes to new line IDs
// and create new QuoteLineItemAttribute records
```

## Known Limitations

- Bundle child auto-creation may not fire in all scenarios — verify children exist after PlaceQuote execution and create missing ones explicitly.
- Attribute cloning is not automatic — you must query source attributes and recreate them on the target lines.
- Deeply nested bundles (3+ levels) may hit governor limits in a single PlaceQuote call — consider splitting into multiple calls.

## Compatible Org Types

| Org Type | Compatible? |
|----------|:-----------:|
| RCA-enabled sandbox | **Yes** |
| CDO org with RCA provisioned | **Yes** |
| Standard SDO / trial org | **No** |
| Scratch org with RCA features | **Yes** |

---

*See also: [PlaceQuote Patterns](./placequote-patterns.md) | [PlaceQuote in RCA Super Reference](../references/PlaceQuote%20in%20RCA%20Super%20Reference.md)*
