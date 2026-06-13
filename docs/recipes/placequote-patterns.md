# Recipe: PlaceQuote Patterns for RCA

> **Product**: Salesforce Revenue Cloud Advanced (RCA)
> **API**: `PlaceQuote.PlaceQuoteRLMApexProcessor`
> **Complexity**: Advanced

---

## Overview

This recipe documents the proven PlaceQuote API patterns extracted from the Mobile TLE Bundle Configurator project. Every pattern here has been tested and deployed in production across multiple RCA orgs.

The PlaceQuote API is the **only** correct way to modify pricing-sensitive fields on Quote records in RCA. Raw DML (`Database.update`) will persist field values but **will not trigger the RCA pricing engine**, leaving derived fields (NetUnitPrice, NetTotalPrice, TotalPrice) and Quote Summary stale.

---

## Core Concepts

### Request Hierarchy

```
PlaceQuote.GraphRequest
 ├─ graphId: String (unique identifier)
 └─ records: List<RecordWithReferenceRequest>
     ├─ referenceId: String (developer-defined ref)
     └─ records: List<RecordResource>
         ├─ SObjectType
         ├─ method: 'GET' | 'POST' | 'PATCH'
         ├─ recordId (for PATCH/GET, optional for POST)
         └─ fieldValues: Map<String, Object>
```

### HTTP-Style Methods

| Method | Use Case |
|--------|----------|
| `GET` | Read a record into the graph context (e.g., the Quote itself) |
| `POST` | Create a new record (e.g., add a QuoteLineItem) |
| `PATCH` | Update an existing record (e.g., change quantity, reprice) |

### Configuration Options

```apex
PlaceQuote.ConfigurationOptionsInput cInput = new PlaceQuote.ConfigurationOptionsInput();

// Auto-create default bundle children when adding a bundle product
cInput.addDefaultConfiguration = true;  // or false for manual control

// Pricing preference
PlaceQuote.PricingPreferenceEnum.System  // Recommended — lets RCA decide
PlaceQuote.PricingPreferenceEnum.Force   // Forces full reprice

// Configuration input
PlaceQuote.ConfigurationInputEnum.RunAndAllowErrors  // Run config rules, don't fail on warnings
PlaceQuote.ConfigurationInputEnum.Skip               // Skip config validation entirely
```

### Execution

```apex
PlaceQuote.PlaceQuoteResponse resp =
    PlaceQuote.PlaceQuoteRLMApexProcessor.execute(
        pricingPref,       // PricingPreferenceEnum
        graphList,         // List<GraphRequest>
        configPref,        // ConfigurationInputEnum
        cInput             // ConfigurationOptionsInput
    );
```

---

## Pattern 1: Add a Standalone Product

**Use case**: Add a single non-bundle product to a Quote.

```apex
// 1. Quote reference — PATCH existing Quote
PlaceQuote.RecordResource quoteRecord =
    new PlaceQuote.RecordResource(Quote.getSobjectType(), 'PATCH', quoteId);
PlaceQuote.RecordWithReferenceRequest quoteRef =
    new PlaceQuote.RecordWithReferenceRequest('refQuote', quoteRecord);

// 2. New QuoteLineItem — POST
PlaceQuote.RecordResource qliRecord =
    new PlaceQuote.RecordResource(QuoteLineItem.getSobjectType(), 'POST');
Map<String, Object> fields = new Map<String, Object>();
fields.put('QuoteId', '@{refQuote.id}');           // Graph reference to the Quote
fields.put('Product2Id', product2Id);
fields.put('PricebookEntryId', pricebookEntryId);
fields.put('Quantity', 1);
fields.put('ProductSellingModelId', sellingModelId); // Required for RCA
qliRecord.fieldValues = fields;

PlaceQuote.RecordWithReferenceRequest qliRef =
    new PlaceQuote.RecordWithReferenceRequest('refQLI', qliRecord);

// 3. Build the graph
List<PlaceQuote.RecordWithReferenceRequest> records =
    new List<PlaceQuote.RecordWithReferenceRequest>();
records.add(quoteRef);
records.add(qliRef);

PlaceQuote.GraphRequest graph = new PlaceQuote.GraphRequest('addLine', records);

// 4. Configure — addDefaultConfiguration = true handles bundles automatically
PlaceQuote.ConfigurationOptionsInput cInput = new PlaceQuote.ConfigurationOptionsInput();
cInput.addDefaultConfiguration = true;

// 5. Execute
PlaceQuote.PlaceQuoteResponse resp =
    PlaceQuote.PlaceQuoteRLMApexProcessor.execute(
        PlaceQuote.PricingPreferenceEnum.System,
        new List<PlaceQuote.GraphRequest>{ graph },
        PlaceQuote.ConfigurationInputEnum.RunAndAllowErrors,
        cInput
    );
```

**Key points:**
- `@{refQuote.id}` is a **graph reference** — PlaceQuote resolves it at execution time
- `ProductSellingModelId` is required for RCA pricing to work
- `addDefaultConfiguration = true` tells the engine to auto-create bundle children if the product is a bundle

---

## Pattern 2: Add a Bundle Product

**Use case**: Add a bundle product and let PlaceQuote auto-create its default children.

The pattern is **identical to Pattern 1** — the magic is in `addDefaultConfiguration = true`. When the Product2Id refers to a bundle product, the RCA engine will:

1. Create the parent QuoteLineItem
2. Auto-create child QuoteLineItems for each default ProductRelatedComponent
3. Create QuoteLineRelationship records linking children to the parent
4. Auto-populate `ParentQuoteLineItemId` on child lines
5. Calculate pricing for the entire bundle hierarchy

```apex
// Same as Pattern 1 — just ensure the Product2Id is a bundle product
// and addDefaultConfiguration = true
cInput.addDefaultConfiguration = true;
```

**Post-execution**: Query the new lines to get the full bundle hierarchy:

```apex
List<QuoteLineItem> allLines = [
    SELECT Id, Product2Id, ParentQuoteLineItemId, Quantity
    FROM QuoteLineItem
    WHERE QuoteId = :quoteId
    ORDER BY CreatedDate DESC
];
```

---

## Pattern 3: Inline Edit (Quantity / Price / Discount Update)

**Use case**: Update a pricing-sensitive field on an existing QuoteLineItem and trigger repricing.

```apex
// 1. Query the existing line for its QuoteId
QuoteLineItem existingQli = [
    SELECT Id, QuoteId FROM QuoteLineItem WHERE Id = :quoteLineItemId LIMIT 1
];

// 2. Quote reference — PATCH
PlaceQuote.RecordResource quoteRecord =
    new PlaceQuote.RecordResource(Quote.getSobjectType(), 'PATCH', existingQli.QuoteId);
PlaceQuote.RecordWithReferenceRequest quoteRef =
    new PlaceQuote.RecordWithReferenceRequest('refQuote', quoteRecord);

// 3. QLI update — PATCH with the changed field
PlaceQuote.RecordResource qliRecord = new PlaceQuote.RecordResource(
    QuoteLineItem.getSobjectType(), 'PATCH', quoteLineItemId
);
Map<String, Object> qliFields = new Map<String, Object>();
qliFields.put('Quantity', newQuantityValue);  // or 'Discount', 'UnitPrice'
qliRecord.fieldValues = qliFields;

PlaceQuote.RecordWithReferenceRequest qliRef =
    new PlaceQuote.RecordWithReferenceRequest('refQLI', qliRecord);

// 4. Build graph and execute
List<PlaceQuote.RecordWithReferenceRequest> records =
    new List<PlaceQuote.RecordWithReferenceRequest>();
records.add(quoteRef);
records.add(qliRef);

PlaceQuote.GraphRequest graph = new PlaceQuote.GraphRequest('inlineEdit', records);

PlaceQuote.ConfigurationOptionsInput cInput = new PlaceQuote.ConfigurationOptionsInput();
cInput.addDefaultConfiguration = false;  // No bundle auto-creation needed

PlaceQuote.PlaceQuoteResponse resp =
    PlaceQuote.PlaceQuoteRLMApexProcessor.execute(
        PlaceQuote.PricingPreferenceEnum.System,
        new List<PlaceQuote.GraphRequest>{ graph },
        PlaceQuote.ConfigurationInputEnum.RunAndAllowErrors,
        cInput
    );
```

> **CRITICAL**: Never use `Database.update(qli)` for Quantity, Discount, or UnitPrice. This was the root cause of BUG-CDO-001 — the field saved but pricing never recalculated.

---

## Pattern 4: Clone a Line (Including Bundles)

**Use case**: Duplicate an existing QuoteLineItem (and its children if it's a bundle).

```apex
// 1. Quote reference — GET (read context)
PlaceQuote.RecordResource quoteRecord =
    new PlaceQuote.RecordResource(Quote.getSobjectType(), 'GET', source.QuoteId);
PlaceQuote.RecordWithReferenceRequest quoteRef =
    new PlaceQuote.RecordWithReferenceRequest('refQuote', quoteRecord);

// 2. POST the cloned parent line
PlaceQuote.RecordResource qliRecord =
    new PlaceQuote.RecordResource(QuoteLineItem.getSobjectType(), 'POST');
Map<String, Object> parentFields = new Map<String, Object>();
parentFields.put('QuoteId', '@{refQuote.id}');
parentFields.put('Product2Id', source.Product2Id);
parentFields.put('PricebookEntryId', source.PricebookEntryId);
parentFields.put('Quantity', source.Quantity);
parentFields.put('Discount', source.Discount);
parentFields.put('ProductSellingModelId', source.ProductSellingModelId);
qliRecord.fieldValues = parentFields;

PlaceQuote.RecordWithReferenceRequest qliRef =
    new PlaceQuote.RecordWithReferenceRequest('refNewQLI', qliRecord);

List<PlaceQuote.RecordWithReferenceRequest> records =
    new List<PlaceQuote.RecordWithReferenceRequest>();
records.add(quoteRef);
records.add(qliRef);

// 3. POST children with graph references to the new parent
Integer childIdx = 0;
for (QuoteLineItem child : sourceChildren) {
    PlaceQuote.RecordResource childRecord =
        new PlaceQuote.RecordResource(QuoteLineItem.getSobjectType(), 'POST');
    Map<String, Object> childFields = new Map<String, Object>();
    childFields.put('QuoteId', '@{refQuote.id}');
    childFields.put('ParentQuoteLineItemId', '@{refNewQLI.id}');  // ← Graph reference
    childFields.put('Product2Id', child.Product2Id);
    childFields.put('PricebookEntryId', child.PricebookEntryId);
    childFields.put('Quantity', child.Quantity);
    childRecord.fieldValues = childFields;
    records.add(new PlaceQuote.RecordWithReferenceRequest(
        'refChild' + childIdx++, childRecord
    ));
}

// 4. Execute
PlaceQuote.GraphRequest graph = new PlaceQuote.GraphRequest('cloneLine', records);
PlaceQuote.ConfigurationOptionsInput cInput = new PlaceQuote.ConfigurationOptionsInput();
cInput.addDefaultConfiguration = true;

PlaceQuote.PlaceQuoteResponse resp =
    PlaceQuote.PlaceQuoteRLMApexProcessor.execute(
        PlaceQuote.PricingPreferenceEnum.System,
        new List<PlaceQuote.GraphRequest>{ graph },
        PlaceQuote.ConfigurationInputEnum.RunAndAllowErrors,
        cInput
    );
```

**Key insight**: The `@{refNewQLI.id}` syntax lets you reference a record that **hasn't been created yet** within the same graph. PlaceQuote resolves these references at execution time.

---

## Pattern 5: Delete Lines + Reprice

**Use case**: Remove lines from a Quote and trigger repricing of remaining lines.

PlaceQuote does not support a `DELETE` method directly. Use standard DML for deletion, then trigger a reprice via PlaceQuote PATCH on the Quote.

```apex
// Step 1: Delete via DML
delete [SELECT Id FROM QuoteLineItem WHERE Id IN :lineIdsToDelete AND QuoteId = :quoteId];

// Step 2: Reprice via PlaceQuote PATCH on the Quote
PlaceQuote.RecordResource quoteRecord =
    new PlaceQuote.RecordResource(Quote.getSobjectType(), 'PATCH', quoteId);
PlaceQuote.RecordWithReferenceRequest quoteRef =
    new PlaceQuote.RecordWithReferenceRequest('refQuote', quoteRecord);

PlaceQuote.GraphRequest graph = new PlaceQuote.GraphRequest(
    'reprice',
    new List<PlaceQuote.RecordWithReferenceRequest>{ quoteRef }
);

PlaceQuote.ConfigurationOptionsInput cInput = new PlaceQuote.ConfigurationOptionsInput();
cInput.addDefaultConfiguration = false;

PlaceQuote.PlaceQuoteRLMApexProcessor.execute(
    PlaceQuote.PricingPreferenceEnum.System,
    new List<PlaceQuote.GraphRequest>{ graph },
    PlaceQuote.ConfigurationInputEnum.RunAndAllowErrors,
    cInput
);
```

---

## Pattern 6: ParentQuoteLineItemId FLS Workaround (Critical)

**The problem**: `ParentQuoteLineItemId` on QuoteLineItem is a **system-managed field** — it has `IsCreatable = false` and `IsUpdatable = false`. You cannot set it via DML or PlaceQuote field assignment. If you try to pass it in a PlaceQuote `POST`, the operation fails with an FLS error.

**The workaround**: Create child lines **without** `ParentQuoteLineItemId`, then establish the bundle link via `QuoteLineRelationship` records. The platform auto-populates `ParentQuoteLineItemId` when a QuoteLineRelationship exists.

### Step-by-Step

```apex
// ─── Step 1: POST child lines WITHOUT ParentQuoteLineItemId ───
PlaceQuote.RecordResource childRec =
    new PlaceQuote.RecordResource(QuoteLineItem.getSobjectType(), 'POST');
Map<String, Object> childFields = new Map<String, Object>();
childFields.put('QuoteId', '@{refQuote.id}');
// ParentQuoteLineItemId intentionally omitted — system-managed field
childFields.put('PricebookEntryId', pricebookEntryId);
childFields.put('Product2Id', childProduct2Id);
childFields.put('Quantity', 1);
childRec.fieldValues = childFields;

// Execute PlaceQuote... (creates the child as a standalone line)

// ─── Step 2: Create QuoteLineRelationship via DML ───

// 2a. Find the ProductRelationshipType
Id bundleRelTypeId = [
    SELECT Id FROM ProductRelationshipType
    WHERE Name = 'Bundle to Bundle Component Relationship'
    LIMIT 1
].Id;

// 2b. Find the ProductRelatedComponentId (links catalog to the specific child)
Id productRelatedComponentId = [
    SELECT Id FROM ProductRelatedComponent
    WHERE ParentProductId = :parentProduct2Id
      AND ChildProductId = :childProduct2Id
    LIMIT 1
].Id;

// 2c. Find the newly-created child QLI
Id newChildId = [
    SELECT Id FROM QuoteLineItem
    WHERE QuoteId = :quoteId
      AND Product2Id = :childProduct2Id
      AND Id NOT IN :preExistingLineIds
    ORDER BY CreatedDate DESC LIMIT 1
].Id;

// 2d. Check if a QuoteLineRelationship already exists (idempotency)
Integer existingCount = [
    SELECT COUNT() FROM QuoteLineRelationship
    WHERE AssociatedQuoteLineId = :newChildId
];

// 2e. Create the relationship if missing
if (existingCount == 0) {
    QuoteLineRelationship rel = new QuoteLineRelationship();
    rel.MainQuoteLineId = parentLineId;                // Bundle parent QLI Id
    rel.AssociatedQuoteLineId = newChildId;             // New child QLI Id
    rel.ProductRelationshipTypeId = bundleRelTypeId;    // "Bundle to Bundle Component"
    rel.AssociatedQuoteLinePricing = 'IncludedInBundlePrice';
    rel.ProductRelatedComponentId = productRelatedComponentId;  // Catalog link
    insert rel;
}

// After insert, the platform auto-populates ParentQuoteLineItemId on the child QLI.
```

### QuoteLineRelationship Fields

| Field | Type | Description |
|-------|------|-------------|
| `MainQuoteLineId` | `Id` | The parent bundle's QuoteLineItem Id |
| `AssociatedQuoteLineId` | `Id` | The child component's QuoteLineItem Id |
| `ProductRelationshipTypeId` | `Id` | Reference to ProductRelationshipType (lookup "Bundle to Bundle Component Relationship") |
| `AssociatedQuoteLinePricing` | `String` | Pricing treatment — use `'IncludedInBundlePrice'` |
| `ProductRelatedComponentId` | `Id` | Optional — links to the catalog ProductRelatedComponent record |

### Why This Works

1. PlaceQuote creates the child line as a standalone QuoteLineItem (no parent)
2. You insert a `QuoteLineRelationship` record that declares "this child belongs to this parent"
3. The platform recognizes the relationship and auto-populates `ParentQuoteLineItemId` on the child
4. Subsequent queries show the child under the parent in the bundle hierarchy

---

## Error Handling

```apex
if (resp.isSuccess != true) {
    String errDetail = '';
    if (resp.responseError != null) {
        for (ConnectApi.PlaceQuoteErrorResponse er : resp.responseError) {
            errDetail += er.message + '; ';
        }
    }
    throw new AuraHandledException(
        'PlaceQuote failed' + (String.isNotBlank(errDetail) ? ': ' + errDetail : '.')
    );
}
```

**Best practices:**
- Always check `resp.isSuccess`
- Iterate `resp.responseError` for detailed messages
- Wrap in try-catch for `AuraHandledException` in LWC controllers
- Log errors for debugging but don't expose internal details to the UI

---

## Quick Reference Table

| Operation | Method | addDefaultConfig | PricingPref | ConfigInput |
|-----------|--------|:---:|---|---|
| Add standalone product | POST | true | System | RunAndAllowErrors |
| Add bundle product | POST | true | System | RunAndAllowErrors |
| Update Qty/Price/Discount | PATCH | false | System | RunAndAllowErrors |
| Clone line (with children) | POST + graph refs | true | System | RunAndAllowErrors |
| Delete lines | DML + PATCH reprice | false | System | RunAndAllowErrors |
| Add bundle child (workaround) | POST + DML relationship | false | System | RunAndAllowErrors |

---

*Based on patterns from the Mobile TLE Bundle Configurator project (v1.2, June 2026).*
