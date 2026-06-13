# PlaceQuote in Revenue Cloud Advanced — Super Reference

> **Audience**: Developers, Solution Engineers, and Architects working with Salesforce Revenue Cloud Advanced (RCA).
> **Last Updated**: June 2026

---

## Table of Contents

1. [What is PlaceQuote?](#1-what-is-placequote)
2. [Core Apex Classes & Enums](#2-core-apex-classes--enums)
3. [Canonical Apex Code Example](#3-canonical-apex-code-example)
4. [Common Use Cases](#4-common-use-cases)
5. [PlaceQuote vs. Place Sales Transaction (PST) API](#5-placequote-vs-place-sales-transaction-pst-api)
6. [Known Issues & Caveats](#6-known-issues--caveats)
7. [Best Practices](#7-best-practices)

---

## 1. What is PlaceQuote?

### Purpose

**PlaceQuote** is the Apex-native API within Revenue Cloud Advanced (RCA) that programmatically drives the RCA pricing and configuration engine against a Quote record. It is the developer entry point for triggering repricing, adding or modifying quote lines, applying product configurations, and orchestrating complex quoting workflows — all without requiring user interaction through the UI.

### Role in the RCA Engine

When a user clicks **"Reprice"** or **"Add Products"** in the RCA Quote workspace, the platform internally invokes the same engine that PlaceQuote exposes programmatically. PlaceQuote sits at the **application-service layer** of RCA:

```
┌─────────────────────────────────────┐
│        RCA Quote Workspace UI       │
├─────────────────────────────────────┤
│        PlaceQuote Apex API          │  ← You are here
├─────────────────────────────────────┤
│  Pricing Engine  │  Config Engine   │
├─────────────────────────────────────┤
│     Revenue Cloud Data Model        │
│  (Quote, QuoteLineItem, Price       │
│   Adjustment, Product Config, etc.) │
└─────────────────────────────────────┘
```

### When to Use PlaceQuote

| Scenario | Use PlaceQuote? |
|----------|:-:|
| Reprice a quote after field changes (Apex Trigger, Flow, LWC) | ✅ |
| Programmatically add products/bundles to a quote | ✅ |
| Migrate quote lines from CPQ to RCA | ✅ |
| Clone quote lines with attribute remapping | ✅ |
| Batch process < 250k quote line records | ✅ |
| Batch process 250k+ records at enterprise scale | ❌ Use PST API |
| Simple field update that doesn't need repricing | ❌ Standard DML |

### Namespace

All PlaceQuote classes live under the **`PlaceQuote`** Apex namespace:

```apex
PlaceQuote.PlaceQuoteRLMApexProcessor
PlaceQuote.GraphRequest
PlaceQuote.RecordWithReferenceRequest
PlaceQuote.RecordResource
PlaceQuote.ConfigurationOptionsInput
PlaceQuote.ConfigurationInputEnum
PlaceQuote.PricingPreferenceEnum
PlaceQuote.PlaceQuoteResponse
```

---

## 2. Core Apex Classes & Enums

### 2.1 `PlaceQuote.GraphRequest`

The top-level request object that wraps a graph of record operations.

| Property | Type | Description |
|----------|------|-------------|
| `graphId` | `String` | Unique identifier for this graph request. Used for correlation in the response. |
| `records` | `List<PlaceQuote.RecordWithReferenceRequest>` | Ordered list of record reference requests that define the operations to perform. |

---

### 2.2 `PlaceQuote.RecordWithReferenceRequest`

Groups a set of record operations under a single reference identifier.

| Property | Type | Description |
|----------|------|-------------|
| `records` | `List<PlaceQuote.RecordResource>` | List of individual record resources (the actual operations). |
| `referenceId` | `String` | A developer-defined reference ID to identify this batch of records within the graph. |

---

### 2.3 `PlaceQuote.RecordResource`

Represents a single record operation within the PlaceQuote graph.

| Property | Type | Description |
|----------|------|-------------|
| `attributes` | `Map<String, String>` | Metadata attributes for the record (e.g., SObject type). |
| `body` | `Map<String, Object>` | The field values for the record. Contains the actual data payload — field names as keys, field values as values. |
| `method` | `String` | The HTTP-style verb for the operation. Use `'PATCH'` for updates/repricing. |
| `referenceId` | `String` | Unique reference ID for this individual record within the request. |
| `url` | `String` | The resource URL path for the target record (e.g., the Quote record's composite URL). |

---

### 2.4 `PlaceQuote.ConfigurationOptionsInput`

Controls how the RCA engine handles pricing and product configuration during execution.

| Property | Type | Description |
|----------|------|-------------|
| `configurationInput` | `PlaceQuote.ConfigurationInputEnum` | Controls whether product configuration validation runs. |
| `pricingPreference` | `PlaceQuote.PricingPreferenceEnum` | Controls pricing behavior during execution. |

---

### 2.5 `PlaceQuote.ConfigurationInputEnum`

Enum that governs configuration validation behavior.

| Value | Behavior |
|-------|----------|
| `Skip` | **Skips configuration validation entirely.** Use this when you are repricing or modifying quote lines that are already correctly configured, or when you want to bypass configuration rules for speed. |

---

### 2.6 `PlaceQuote.PricingPreferenceEnum`

Enum that governs how the pricing engine runs.

| Value | Behavior |
|-------|----------|
| `Force` | **Forces a full reprice of all quote lines.** The engine recalculates all pricing from scratch — list prices, adjustments, tiers, and derived values — regardless of whether line-level fields have changed. This is the recommended value for most programmatic operations. |

---

### 2.7 `PlaceQuote.PlaceQuoteRLMApexProcessor`

The **core processor class** that executes PlaceQuote operations.

| Method | Signature | Returns |
|--------|-----------|---------|
| `execute` | `execute(List<PlaceQuote.GraphRequest> graphRequests)` | `PlaceQuote.PlaceQuoteResponse` |

**Key details:**

- Accepts a **list** of `GraphRequest` objects (typically you pass a single-element list).
- Processes the graph synchronously.
- Returns a `PlaceQuoteResponse` containing the results of all operations.

---

### 2.8 `PlaceQuote.PlaceQuoteResponse`

The response object returned by `PlaceQuoteRLMApexProcessor.execute()`. Contains the processed results, including any errors or warnings generated during execution.

---

## 3. Canonical Apex Code Example

Below is a **copy-paste-ready** Apex snippet that demonstrates the standard pattern for repricing an existing Quote using PlaceQuote with **Force** pricing and **Skip** configuration.

```apex
/**
 * Reprice an existing RCA Quote using PlaceQuote.
 *
 * This is the canonical pattern: PATCH the Quote record with
 * Force pricing (full recalculation) and Skip configuration
 * (bypass config validation for speed).
 *
 * @param quoteId  The Id of the Quote record to reprice.
 */
public static PlaceQuote.PlaceQuoteResponse repriceQuote(Id quoteId) {

    // ─── Step 1: Build the RecordResource (the "what") ───
    PlaceQuote.RecordResource resource = new PlaceQuote.RecordResource();

    // Set the SObject type in attributes
    resource.attributes = new Map<String, String>{
        'type' => 'Quote'
    };

    // Set the method to PATCH (update/reprice operation)
    resource.method = 'PATCH';

    // Set a unique reference ID for this record
    resource.referenceId = 'refQuote';

    // Set the resource URL pointing to the specific Quote record
    resource.url = '/services/data/v62.0/sobjects/Quote/' + quoteId;

    // Set the body with configuration options
    // Force = full reprice | Skip = bypass configuration validation
    PlaceQuote.ConfigurationOptionsInput configOptions = new PlaceQuote.ConfigurationOptionsInput();
    configOptions.pricingPreference = PlaceQuote.PricingPreferenceEnum.Force;
    configOptions.configurationInput = PlaceQuote.ConfigurationInputEnum.Skip;

    resource.body = new Map<String, Object>{
        'configurationOptions' => configOptions
    };

    // ─── Step 2: Wrap in RecordWithReferenceRequest ───
    PlaceQuote.RecordWithReferenceRequest refRequest = new PlaceQuote.RecordWithReferenceRequest();
    refRequest.referenceId = 'refQuoteRequest';
    refRequest.records = new List<PlaceQuote.RecordResource>{ resource };

    // ─── Step 3: Wrap in GraphRequest ───
    PlaceQuote.GraphRequest graphReq = new PlaceQuote.GraphRequest();
    graphReq.graphId = 'graph1';
    graphReq.records = new List<PlaceQuote.RecordWithReferenceRequest>{ refRequest };

    // ─── Step 4: Execute via the processor ───
    PlaceQuote.PlaceQuoteRLMApexProcessor processor = new PlaceQuote.PlaceQuoteRLMApexProcessor();
    PlaceQuote.PlaceQuoteResponse response = processor.execute(
        new List<PlaceQuote.GraphRequest>{ graphReq }
    );

    // ─── Step 5: Handle the response ───
    System.debug('PlaceQuote execution completed. Response: ' + response);
    return response;
}
```

### Anatomy of the Pattern

```
GraphRequest                          ← Container with a graphId
 └─ RecordWithReferenceRequest        ← Groups records under a referenceId
     └─ RecordResource                ← Individual operation
         ├─ attributes: { type }      ← SObject type
         ├─ method: 'PATCH'           ← HTTP-style verb
         ├─ url: '/services/data/...' ← Target record composite URL
         ├─ referenceId               ← Unique record-level reference
         └─ body: { configOptions }   ← Payload with pricing + config prefs
```

---

## 4. Common Use Cases

### 4.1 Reprice on Demand

**Scenario**: A custom LWC button, Apex trigger, or Flow needs to recalculate all pricing on a Quote after field values change (e.g., discount override, term change, approval-driven adjustment).

**Approach**: Use the canonical pattern (Section 3) with `PricingPreferenceEnum.Force` and `ConfigurationInputEnum.Skip`. This forces the engine to recalculate everything without re-running configuration validation.

**When to use**: After any programmatic field change that affects pricing but doesn't alter product configuration (quantity changes, discount adjustments, custom field updates that feed pricing rules).

---

### 4.2 Add Products or Bundles to a Quote

**Scenario**: Programmatically add one or more products (including bundles with child components) to an existing Quote.

**Approach**: Build `RecordResource` entries for the new QuoteLineItem records. Set the `method` to an appropriate verb and include the product/pricebook entry references in the `body`. The RCA engine will resolve bundles, apply pricing, and create the full line hierarchy.

**Key consideration**: When adding bundles, the engine should auto-create child components based on the bundle's product configuration rules. See Section 6.1 for known limitations around bundle child auto-creation.

---

### 4.3 CPQ-to-RCA Migration

**Scenario**: Migrating existing SBQQ (Salesforce CPQ) quote line data into Revenue Cloud Advanced. A migration script reads CPQ quote lines and reconstructs them as RCA quote lines via PlaceQuote.

**Approach**:
1. Query source CPQ quote lines with all relevant fields.
2. Map CPQ fields to RCA equivalents.
3. Build `RecordResource` entries with the mapped data.
4. Execute via PlaceQuote with `Force` pricing to ensure all RCA pricing rules apply to migrated data.
5. Process in batches to stay within governor limits (see Section 7.4 for large-scale patterns).

**Key consideration**: For migrations exceeding ~250k records, consider the Place Sales Transaction (PST) API instead (see Section 5).

---

### 4.4 Clone Quote Lines with Attribute Mapping

**Scenario**: Clone an existing quote (or a subset of its lines) into a new quote, remapping product attributes, adjusting quantities, or applying different pricing tiers.

**Approach**:
1. Query source quote lines and their attributes.
2. Transform/remap attributes as needed for the target context.
3. Build `RecordResource` entries for the cloned lines on the target Quote.
4. Execute PlaceQuote against the target Quote with `Force` pricing.

**Key consideration**: Ensure that attribute mappings are complete — missing attributes on bundle components can cause configuration validation failures if `Skip` is not set.

---

## 5. PlaceQuote vs. Place Sales Transaction (PST) API

### Overview

Salesforce provides **two** programmatic APIs for driving the RCA engine:

| Dimension | PlaceQuote | Place Sales Transaction (PST) |
|-----------|------------|-------------------------------|
| **Primary Object** | Quote | Sales Transaction |
| **Invocation** | `PlaceQuote.PlaceQuoteRLMApexProcessor.execute()` | PST-specific API classes |
| **Best For** | Standard quoting workflows, CPQ migration, ad-hoc repricing | High-volume operations, enterprise-scale batch processing |
| **Scale Threshold** | Performs well up to ~250k quote line records | Designed for **250k+ records** |
| **Complexity** | Graph-based request model (GraphRequest → RecordWithReferenceRequest → RecordResource) | Simplified request model designed for bulk operations |
| **Configuration Control** | Full control via `ConfigurationInputEnum` and `PricingPreferenceEnum` | Streamlined configuration options for bulk scenarios |

### When to Use Each

```
                         ┌─────────────────────┐
                         │  Need to price/     │
                         │  configure records? │
                         └────────┬────────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
              Record count               Record count
              < 250k lines               ≥ 250k lines
                    │                           │
                    ▼                           ▼
            ┌──────────────┐          ┌─────────────────┐
            │  PlaceQuote  │          │    PST API      │
            │  API         │          │                 │
            └──────────────┘          └─────────────────┘
```

### Key Differences

1. **Scale**: PlaceQuote is optimized for interactive and moderate-batch scenarios. PST is built for enterprise-scale data operations where record volumes exceed 250k.

2. **Request Model**: PlaceQuote uses a nested graph model (`GraphRequest` → `RecordWithReferenceRequest` → `RecordResource`). PST simplifies the request structure for bulk throughput.

3. **Object Focus**: PlaceQuote operates against **Quote** records. PST operates against **Sales Transaction** records, which are the order-side counterpart in RCA.

4. **Use in Migration**: For CPQ-to-RCA migrations, start with PlaceQuote for smaller datasets. Graduate to PST when volumes demand it.

---

## 6. Known Issues & Caveats

### 6.1 Bundle Child Auto-Creation Gaps

**Issue**: When programmatically adding a bundle product via PlaceQuote, the engine may not always auto-create all expected child components (options, features) under certain conditions — particularly when the bundle's configuration rules rely on UI-driven selection flows.

**Workaround**: Explicitly create child `RecordResource` entries for each expected bundle component rather than relying on engine auto-creation. Validate the output line hierarchy after execution.

---

### 6.2 Namespace Visibility Errors

**Issue**: Apex classes that reference PlaceQuote types may encounter `Type is not visible` or `Invalid type: PlaceQuote.GraphRequest` compilation errors, especially in managed package contexts or when the Revenue Cloud Advanced feature is not fully enabled.

**Workaround**:
- Ensure the **Revenue Lifecycle Management** license and permission sets are assigned to the running user.
- Verify that the `PlaceQuote` namespace is available in the org by checking via Developer Console or Anonymous Apex.
- In managed package scenarios, ensure proper namespace resolution and dependency declarations.

---

### 6.3 Context Hydration & Derived Table Failures

**Issue**: PlaceQuote execution may fail with errors related to context hydration or derived/computed table resolution. This typically occurs when:
- The Quote record is missing required parent-level fields (e.g., Pricebook, Account).
- Derived pricing fields depend on data that hasn't been committed to the database yet.
- The execution context (running user, sharing rules) doesn't have visibility to related records.

**Workaround**:
- Ensure all parent-level required fields are populated **before** invoking PlaceQuote.
- Commit (insert/update via DML) any prerequisite records before building the PlaceQuote request.
- Run PlaceQuote in a context with full record access (System mode where appropriate).

---

### 6.4 Raw DML Bypasses the Pricing Engine (Critical)

**Issue**: Using standard Apex DML (`Database.update`) to change pricing-sensitive fields (Quantity, Discount, UnitPrice) on QuoteLineItem records **does not trigger the RCA pricing engine**. The field value persists to the database, but derived fields (NetUnitPrice, NetTotalPrice, TotalPrice) and the Quote Summary remain stale.

This is the single most common mistake when integrating with RCA. It was the root cause of BUG-CDO-001 in the Mobile TLE project, where quantity edits appeared to save but totals never updated.

**Root cause**: RCA pricing is only triggered through the PlaceQuote API (or the equivalent UI action). Standard DML writes directly to the database without invoking the pricing engine.

**Fix**: **Always route pricing-sensitive field changes through the PlaceQuote API.** Build a `RecordResource` with `method: 'PATCH'`, set `PricingPreference` to `Force` (or `System`), and execute via `PlaceQuoteRLMApexProcessor.execute()`.

```apex
// ❌ WRONG — Pricing will NOT recalculate
quoteLineItem.Quantity = 5;
Database.update(quoteLineItem);

// ✅ CORRECT — Pricing recalculates via PlaceQuote
// (see Section 3 for the full canonical pattern)
PlaceQuote.RecordResource resource = new PlaceQuote.RecordResource();
resource.method = 'PATCH';
// ... build the full request and execute via PlaceQuoteRLMApexProcessor
```

---

### 6.5 Quote-to-Opportunity Sync Behavior

**Issue**: After PlaceQuote reprices a Quote, the sync between Quote and its parent Opportunity may not fire automatically in all scenarios. Fields that are expected to roll up from Quote lines to the Opportunity (e.g., total amount) may appear stale.

**Workaround**:
- Explicitly trigger the Quote-to-Opportunity sync after PlaceQuote execution if downstream processes depend on Opportunity-level totals.
- Use a platform event or `@future` callout to handle the sync asynchronously after the PlaceQuote transaction completes.

---

## 7. Best Practices

### 7.1 Force vs. Default Pricing

| Approach | When to Use |
|----------|-------------|
| **`PricingPreferenceEnum.Force`** | **Recommended default.** Use whenever you need deterministic, fully recalculated pricing. Ensures all pricing rules, adjustments, tiers, and derived values are recomputed. Slightly more compute-intensive but eliminates stale-price bugs. |
| Default (no Force) | Only when you are certain that no pricing-relevant fields have changed and you want to preserve the existing calculated prices. Rare in programmatic scenarios. |

**Rule of thumb**: If in doubt, use `Force`. The compute cost is negligible compared to debugging a stale-price issue in production.

---

### 7.2 Skipping Configuration

| Approach | When to Use |
|----------|-------------|
| **`ConfigurationInputEnum.Skip`** | Use when repricing existing, already-configured lines. Skipping configuration validation significantly improves performance and avoids false-negative validation errors on lines that haven't changed structurally. |
| Default (run configuration) | Use when adding **new** products that require configuration rules to fire (e.g., bundle assembly, required option enforcement, attribute defaulting). |

**Rule of thumb**: For reprice-only operations, always `Skip`. For add-product operations, let configuration run unless you're explicitly building out all child records yourself.

---

### 7.3 Error Handling

```apex
try {
    PlaceQuote.PlaceQuoteRLMApexProcessor processor =
        new PlaceQuote.PlaceQuoteRLMApexProcessor();
    PlaceQuote.PlaceQuoteResponse response = processor.execute(
        new List<PlaceQuote.GraphRequest>{ graphReq }
    );

    // Inspect the response for warnings or partial failures
    System.debug('PlaceQuote Response: ' + JSON.serializePretty(response));

} catch (PlaceQuote.PlaceQuoteException e) {
    // Handle PlaceQuote-specific errors
    System.debug(LoggingLevel.ERROR, 'PlaceQuote failed: ' + e.getMessage());
    // Consider: retry logic, user notification, or fallback path

} catch (Exception e) {
    // Handle unexpected errors (governor limits, null pointers, etc.)
    System.debug(LoggingLevel.ERROR, 'Unexpected error: ' + e.getMessage());
    throw e;
}
```

**Key practices:**
- Always wrap PlaceQuote calls in try-catch blocks.
- Inspect the `PlaceQuoteResponse` — it may contain partial success results even when some lines fail.
- Log the full response in debug scenarios to aid troubleshooting.
- Consider implementing retry logic for transient errors (lock contention, timeout).

---

### 7.4 Large-Scale Migration Patterns

When migrating large datasets (e.g., CPQ-to-RCA), follow this tiered approach:

```
┌─────────────────────────────────────────────────────────┐
│                  Migration Decision Tree                 │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Volume < 10k lines                                     │
│  → Single PlaceQuote call with Force + Skip             │
│                                                         │
│  Volume 10k – 250k lines                                │
│  → Batch Apex with PlaceQuote in execute()              │
│    • Process 100–200 quote lines per batch              │
│    • Use Force + Skip                                   │
│    • Log failures per batch for retry                   │
│                                                         │
│  Volume > 250k lines                                    │
│  → Place Sales Transaction (PST) API                    │
│    • Designed for this scale                            │
│    • Simplified request model                           │
│    • See Section 5                                      │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Batch Apex pattern tips:**
- Keep batch sizes conservative (100–200 lines) to avoid governor limits.
- Use `Force` pricing in every batch to ensure consistency.
- Use `Skip` configuration unless the migration includes new bundle assembly.
- Implement a failure log (custom object or platform event) to capture and retry failed batches.
- Run in a dedicated integration user context with full object/field access.

---

### 7.5 General Guidelines

1. **Always pass `graphId`**: Use meaningful graph IDs (e.g., `'repriceQuote_' + quoteId`) for traceability in logs and debugging.

2. **Use unique `referenceId` values**: Each `RecordResource` and `RecordWithReferenceRequest` should have a unique `referenceId` within the graph. This enables precise error correlation in the response.

3. **Minimize the graph payload**: Only include the records that need processing. Don't send the entire quote line inventory if only a subset needs repricing.

4. **Test in sandbox first**: PlaceQuote interacts deeply with the RCA engine. Always validate in a sandbox with representative data before production deployment.

5. **Monitor governor limits**: PlaceQuote operations consume SOQL queries, DML operations, and CPU time. Profile your implementation in the Developer Console or via Apex debug logs to ensure headroom.

6. **API version alignment**: Ensure the `url` in `RecordResource` matches your org's API version. Mismatched versions may cause unexpected field availability issues.

---

## Quick Reference Card

```
┌────────────────────────────────────────────────────────────┐
│                PlaceQuote Quick Reference                   │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  NAMESPACE:  PlaceQuote                                    │
│  PROCESSOR:  PlaceQuote.PlaceQuoteRLMApexProcessor         │
│  METHOD:     execute(List<GraphRequest>) → PlaceQuoteResponse │
│                                                            │
│  REQUEST HIERARCHY:                                        │
│    GraphRequest                                            │
│     └─ RecordWithReferenceRequest                          │
│         └─ RecordResource                                  │
│             ├─ attributes  (Map<String,String>)            │
│             ├─ body        (Map<String,Object>)            │
│             ├─ method      (String: 'PATCH')               │
│             ├─ referenceId (String)                         │
│             └─ url         (String)                         │
│                                                            │
│  CONFIG OPTIONS (in body):                                 │
│    ConfigurationOptionsInput                               │
│     ├─ pricingPreference:  Force  (full reprice)           │
│     └─ configurationInput: Skip   (bypass validation)      │
│                                                            │
│  SCALE GUIDANCE:                                           │
│    < 250k records  → PlaceQuote                            │
│    ≥ 250k records  → Place Sales Transaction (PST) API     │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

---

*This reference is synthesized from the Revenue Lifecycle Management Developer Guide and Salesforce Revenue Cloud Advanced product documentation. For the latest updates, consult official Salesforce documentation.*
