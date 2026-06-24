# Recipe: PlaceQuote Patterns for RCA

> **Org Compatibility:** This recipe requires an org with **Revenue Cloud Advanced (RCA)** enabled. The `PlaceQuote` namespace and RCA sObjects (`QuoteLineItemAttribute`, `QuoteLineRelationship`, `ProductSellingModel`) must be present. Standard SDO/trial orgs are **not compatible** — use an RCA-enabled sandbox or CDO org.

---

## Overview

PlaceQuote is the single Apex entry point for pricing and configuration in Revenue Cloud Advanced. This recipe covers the essential patterns for working with the PlaceQuote API programmatically.

## Pattern 1: Reprice Existing Quote (Force + Skip)

The most common operation — force-reprice all lines on an existing quote.

```apex
public static void repriceQuote(Id quoteId) {
    // Build record resource for the Quote
    PlaceQuote.RecordResource quoteResource = new PlaceQuote.RecordResource();
    quoteResource.attributes = new Map<String, Object>{ 'type' => 'Quote' };
    quoteResource.body = new Map<String, Object>{ 'Id' => quoteId };
    quoteResource.method = 'PATCH';
    quoteResource.referenceId = 'refQuote';
    quoteResource.url = 'Quote/' + quoteId;

    // Wrap in RecordWithReferenceRequest
    PlaceQuote.RecordWithReferenceRequest recordRequest =
        new PlaceQuote.RecordWithReferenceRequest();
    recordRequest.record = quoteResource;
    recordRequest.referenceId = 'refQuote';

    // Build graph with Force pricing, Skip configuration
    PlaceQuote.GraphRequest graphRequest = new PlaceQuote.GraphRequest();
    graphRequest.graphId = 'graph1';
    graphRequest.records = new List<PlaceQuote.RecordWithReferenceRequest>{ recordRequest };

    PlaceQuote.ConfigurationOptionsInput configOptions =
        new PlaceQuote.ConfigurationOptionsInput();
    configOptions.pricingPreference = PlaceQuote.PricingPreferenceEnum.Force;
    configOptions.configurationInput = PlaceQuote.ConfigurationInputEnum.Skip;

    // Execute
    List<PlaceQuote.PlaceQuoteResponse> responses =
        PlaceQuote.PlaceQuoteRLMApexProcessor.execute(
            new List<PlaceQuote.GraphRequest>{ graphRequest }
        );

    // Check result
    for (PlaceQuote.PlaceQuoteResponse resp : responses) {
        if (!resp.isSuccess) {
            System.debug(LoggingLevel.ERROR,
                'Reprice failed: ' + JSON.serialize(resp.graphResponse));
        }
    }
}
```

**When to use:** After price book changes, during migration, for SE demos, anytime you need guaranteed-fresh prices.

## Pattern 2: Add Product Line to Quote

```apex
public static void addProductToQuote(Id quoteId, Id productId, Decimal quantity) {
    // Quote record (PATCH — update to trigger engine)
    PlaceQuote.RecordResource quoteResource = new PlaceQuote.RecordResource();
    quoteResource.attributes = new Map<String, Object>{ 'type' => 'Quote' };
    quoteResource.body = new Map<String, Object>{ 'Id' => quoteId };
    quoteResource.method = 'PATCH';
    quoteResource.referenceId = 'refQuote';
    quoteResource.url = 'Quote/' + quoteId;

    // New line item (POST — create new)
    PlaceQuote.RecordResource lineResource = new PlaceQuote.RecordResource();
    lineResource.attributes = new Map<String, Object>{ 'type' => 'QuoteLineItem' };
    lineResource.body = new Map<String, Object>{
        'Product2Id' => productId,
        'Quantity' => quantity,
        'QuoteId' => quoteId
    };
    lineResource.method = 'POST';
    lineResource.referenceId = 'refNewLine';

    // Wrap both
    PlaceQuote.RecordWithReferenceRequest quoteReq =
        new PlaceQuote.RecordWithReferenceRequest();
    quoteReq.record = quoteResource;
    quoteReq.referenceId = 'refQuote';

    PlaceQuote.RecordWithReferenceRequest lineReq =
        new PlaceQuote.RecordWithReferenceRequest();
    lineReq.record = lineResource;
    lineReq.referenceId = 'refNewLine';

    // Graph
    PlaceQuote.GraphRequest graphRequest = new PlaceQuote.GraphRequest();
    graphRequest.graphId = 'addProduct';
    graphRequest.records = new List<PlaceQuote.RecordWithReferenceRequest>{
        quoteReq, lineReq
    };

    // Execute with Force pricing (new line needs pricing)
    List<PlaceQuote.PlaceQuoteResponse> responses =
        PlaceQuote.PlaceQuoteRLMApexProcessor.execute(
            new List<PlaceQuote.GraphRequest>{ graphRequest }
        );
}
```

**When to use:** Programmatically adding products from LWC, Flow, or integration.

## Pattern 3: Date Fields — Always String Serialize

```apex
// CRITICAL: Date fields must be String, not Date
// ❌ WRONG — causes silent pricing failures
body.put('StartDate', Date.today());

// ✅ CORRECT
body.put('StartDate', String.valueOf(Date.today()));
body.put('EndDate', String.valueOf(Date.today().addMonths(12)));
```

**Applies to:** `StartDate`, `EndDate`, `EffectiveDate`, `ExpirationDate`, and all custom date fields.

## Pattern 4: Error Handling

```apex
List<PlaceQuote.PlaceQuoteResponse> responses =
    PlaceQuote.PlaceQuoteRLMApexProcessor.execute(graphRequests);

List<String> failures = new List<String>();
for (PlaceQuote.PlaceQuoteResponse resp : responses) {
    if (!resp.isSuccess) {
        failures.add('Graph ' + resp.graphId + ': ' +
            JSON.serialize(resp.graphResponse));
    }
}

if (!failures.isEmpty()) {
    // In LWC context: return error to UI
    // In batch context: log and continue
    System.debug(LoggingLevel.ERROR,
        'PlaceQuote failures: ' + String.join(failures, '\n'));
}
```

## Key Rules

1. **Never raw-DML** on `QuoteLineItem` in an RCA org — always use PlaceQuote.
2. **Serialize dates as strings** in `yyyy-MM-dd` format.
3. **Force pricing** unless you have a specific performance reason to use default.
4. **Skip configuration** only when quote structure isn't changing.
5. **Check `isSuccess`** on every response before proceeding.

---

*See also: [PlaceQuote in RCA Super Reference](../references/PlaceQuote%20in%20RCA%20Super%20Reference.md) for the complete API reference.*
