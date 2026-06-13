# Recipe: Bundle Configuration in RCA

> **Product**: Salesforce Revenue Cloud Advanced (RCA)
> **Components**: ProductComponentGroup, ProductRelatedComponent, QuoteLineRelationship, QuoteLineItemAttribute
> **Complexity**: Advanced

---

## Overview

This recipe documents the data model chain and Apex patterns for building a bundle configurator in Revenue Cloud Advanced. It covers loading catalog data, merging with the current quote state, saving configuration changes, and handling nested bundles up to 3 levels deep.

Based on the Mobile TLE Bundle Configurator — a production-grade implementation tested across multiple RCA orgs.

---

## The Bundle Data Model Chain

```
Product2 (Bundle Parent)
 │
 ├── ProductComponentGroup (Group of options)
 │    ├─ Name: "Processors"
 │    ├─ MinBundleComponents: 1
 │    ├─ MaxBundleComponents: 3
 │    ├─ Sequence: 1
 │    │
 │    ├── ProductRelatedComponent (Option within group)
 │    │    ├─ ChildProductId → Product2 (component product)
 │    │    ├─ IsDefaultComponent: true/false
 │    │    ├─ IsComponentRequired: true/false
 │    │    ├─ MinQuantity / MaxQuantity
 │    │    ├─ IsQuantityEditable: true/false
 │    │    └─ Sequence: 1
 │    │
 │    └── ProductRelatedComponent (another option)
 │
 └── ProductComponentGroup (another group)
      └── ProductRelatedComponent
           └─ ChildProductId → Product2 (which is ALSO a bundle!)
              └── ProductComponentGroup (nested bundle - level 2)
                   └── ProductRelatedComponent (level 2 options)
```

### Quote-Side Data Model

```
QuoteLineItem (Bundle Parent)
 │
 ├── QuoteLineItem (Child component)
 │    ├─ ParentQuoteLineItemId → parent QLI (system-managed)
 │    ├─ Product2Id → component product
 │    │
 │    └── QuoteLineItemAttribute (attribute values)
 │         ├─ AttributeDefinitionId
 │         ├─ AttributeValue
 │         └─ AttributePicklistValueId
 │
 └── QuoteLineRelationship (bundle link)
      ├─ MainQuoteLineId → parent QLI
      ├─ AssociatedQuoteLineId → child QLI
      ├─ ProductRelationshipTypeId → "Bundle to Bundle Component"
      ├─ AssociatedQuoteLinePricing → "IncludedInBundlePrice"
      └─ ProductRelatedComponentId → catalog link
```

---

## Loading Bundle Configuration

The loading process joins **catalog data** (what's available) with **quote state** (what's selected).

### Step 1: Query the Parent QuoteLineItem

```apex
QuoteLineItem parentQli = [
    SELECT Id, Product2Id, Product2.Name, Quantity, UnitPrice
    FROM QuoteLineItem
    WHERE Id = :quoteLineItemId AND QuoteId = :quoteId
    WITH SECURITY_ENFORCED
    LIMIT 1
];
```

### Step 2: Query ProductComponentGroups

```apex
List<ProductComponentGroup> groups = [
    SELECT Id, Name, MinBundleComponents, MaxBundleComponents, Sequence
    FROM ProductComponentGroup
    WHERE ParentProductId = :parentQli.Product2Id
    WITH SECURITY_ENFORCED
    ORDER BY Sequence NULLS LAST, Name
];
```

### Step 3: Query ProductRelatedComponents (Options)

```apex
List<ProductRelatedComponent> options = [
    SELECT Id, ChildProductId, ChildProduct.Name, ChildProduct.ProductCode,
           ProductComponentGroupId, IsDefaultComponent, IsComponentRequired,
           MinQuantity, MaxQuantity, Quantity, IsQuantityEditable, Sequence
    FROM ProductRelatedComponent
    WHERE ParentProductId = :parentQli.Product2Id
      AND ProductComponentGroupId IN :groupIds
    WITH SECURITY_ENFORCED
    ORDER BY Sequence NULLS LAST, ChildProduct.Name
];
```

### Step 4: Query Existing Child QuoteLineItems

```apex
Map<Id, QuoteLineItem> existingChildByProduct = new Map<Id, QuoteLineItem>();
for (QuoteLineItem childQli : [
    SELECT Id, Product2Id, Quantity, UnitPrice, TotalPrice
    FROM QuoteLineItem
    WHERE ParentQuoteLineItemId = :parentQuoteLineItemId
      AND QuoteId = :quoteId
    WITH SECURITY_ENFORCED
]) {
    existingChildByProduct.put(childQli.Product2Id, childQli);
}
```

### Step 5: Query QuoteLineItemAttributes

```apex
for (QuoteLineItemAttribute qlia : [
    SELECT Id, QuoteLineItemId, AttributeDefinitionId,
           AttributeDefinition.Name, AttributeDefinition.DataType,
           AttributeValue, AttributePicklistValueId
    FROM QuoteLineItemAttribute
    WHERE QuoteLineItemId IN :childLineIds
    WITH SECURITY_ENFORCED
]) {
    // Group by QuoteLineItemId for easy lookup
}
```

### Step 6: Detect Nested Bundles

```apex
Set<Id> nestedBundleProductIds = new Set<Id>();
for (ProductComponentGroup nestedPcg : [
    SELECT ParentProductId
    FROM ProductComponentGroup
    WHERE ParentProductId IN :childProductIds
    WITH SECURITY_ENFORCED
]) {
    nestedBundleProductIds.add(nestedPcg.ParentProductId);
}
```

### Step 7: Merge Catalog + Quote State

For each option in each group:
1. Check if a child QuoteLineItem exists for that product (`existingChildByProduct`)
2. If it does → mark as **selected**, populate quantity/price from the QLI
3. If it doesn't → mark as **available** (unselected)
4. If the child product is in `nestedBundleProductIds` → mark as **nested bundle** and recurse

### Step 8: Recurse for Nested Bundles (Up to 3 Levels)

```apex
// nestingLevel starts at 0, stops at 2 (3 levels: 0, 1, 2)
if (nestingLevel > 2) return new List<ConfigGroup>();

// For each option that is a nested bundle AND is selected:
if (nestedBundleProductIds.contains(childProductId) && isSelected) {
    option.nestedGroups = loadConfigGroupsForProduct(
        childProductId, quoteId, childQuoteLineItemId, nestingLevel + 1
    );
}
```

---

## Saving Bundle Configuration

Saving processes three types of changes: **removes**, **adds**, and **updates**.

### Step 1: Delete Removed Lines

```apex
// DML delete — PlaceQuote doesn't support DELETE method
delete [
    SELECT Id FROM QuoteLineItem
    WHERE Id IN :removeIds AND QuoteId = :quoteId
];
```

### Step 2a: Add New Children via PlaceQuote

POST new child QuoteLineItems **without** `ParentQuoteLineItemId` (it's system-managed and not writable).

```apex
PlaceQuote.RecordResource childRec =
    new PlaceQuote.RecordResource(QuoteLineItem.getSobjectType(), 'POST');
Map<String, Object> childFields = new Map<String, Object>();
childFields.put('QuoteId', '@{refQuote.id}');
// ParentQuoteLineItemId intentionally omitted
childFields.put('PricebookEntryId', pricebookEntryId);
childFields.put('Product2Id', childProduct2Id);
childFields.put('Quantity', quantity);
childRec.fieldValues = childFields;
```

Set `addDefaultConfiguration = false` (you're manually managing the bundle structure).

### Step 2b: Create QuoteLineRelationship Records

After PlaceQuote creates the standalone children, establish the bundle link:

```apex
QuoteLineRelationship rel = new QuoteLineRelationship();
rel.MainQuoteLineId = parentLineId;
rel.AssociatedQuoteLineId = newChildId;
rel.ProductRelationshipTypeId = bundleRelTypeId;  // "Bundle to Bundle Component"
rel.AssociatedQuoteLinePricing = 'IncludedInBundlePrice';
rel.ProductRelatedComponentId = productRelatedComponentId;  // Catalog link
insert rel;
```

**Important**: Check for existing relationships first to avoid duplicates.

### Step 3: Handle QuoteLineItemAttribute Changes

Attributes are managed via DML (not PlaceQuote):

```apex
QuoteLineItemAttribute qlia = new QuoteLineItemAttribute();
qlia.QuoteLineItemId = targetLineId;
qlia.AttributeDefinitionId = attributeDefinitionId;
qlia.AttributeValue = newValue;
if (String.isNotBlank(picklistValueId)) {
    qlia.AttributePicklistValueId = picklistValueId;
}
upsert qlia;
```

### Step 4: Reload and Return

After all changes, re-run `loadBundleConfiguration()` to return the fresh state to the UI.

---

## DTO Pattern

Use inner classes to pass structured data between Apex and LWC:

```apex
public class BundleConfigState {
    @AuraEnabled public Id quoteLineItemId;
    @AuraEnabled public Id product2Id;
    @AuraEnabled public String productName;
    @AuraEnabled public Decimal quantity;
    @AuraEnabled public Decimal unitPrice;
    @AuraEnabled public String currencyIsoCode;
    @AuraEnabled public List<ConfigGroup> groups;
    @AuraEnabled public List<ConfigAttribute> attributes;
}

public class ConfigGroup {
    @AuraEnabled public Id groupId;
    @AuraEnabled public String groupName;
    @AuraEnabled public Integer minComponents;
    @AuraEnabled public Integer maxComponents;
    @AuraEnabled public Integer selectedCount;
    @AuraEnabled public List<ConfigOption> options;
}

public class ConfigOption {
    @AuraEnabled public Id productRelatedComponentId;
    @AuraEnabled public Id childProduct2Id;
    @AuraEnabled public String childProductName;
    @AuraEnabled public Boolean isSelected;
    @AuraEnabled public Boolean isRequired;
    @AuraEnabled public Boolean isDefault;
    @AuraEnabled public Decimal quantity;
    @AuraEnabled public Decimal minQuantity;
    @AuraEnabled public Decimal maxQuantity;
    @AuraEnabled public Boolean isQuantityEditable;
    @AuraEnabled public Boolean isNestedBundle;
    @AuraEnabled public List<ConfigGroup> nestedGroups;
    @AuraEnabled public List<ConfigAttribute> attributes;
}

public class ConfigAttribute {
    @AuraEnabled public Id attributeDefinitionId;
    @AuraEnabled public String name;
    @AuraEnabled public String dataType;  // Picklist, Number, Text
    @AuraEnabled public String value;
    @AuraEnabled public String picklistValueId;
}

public class ConfigChange {
    @AuraEnabled public String action;  // ADD, REMOVE, UPDATE
    @AuraEnabled public String quoteLineItemId;
    @AuraEnabled public String childProduct2Id;
    @AuraEnabled public String pricebookEntryId;
    @AuraEnabled public Decimal quantity;
    @AuraEnabled public Decimal unitPrice;
    @AuraEnabled public List<AttributeChange> attributes;
}
```

---

## Cardinality Validation

Each `ProductComponentGroup` defines `MinBundleComponents` and `MaxBundleComponents`. Validate on the LWC side before saving:

```javascript
validate() {
    const selectedCount = this.options.filter(o => o.isSelected).length;
    if (selectedCount < this.minComponents) {
        return { valid: false, message: `Select at least ${this.minComponents}` };
    }
    if (this.maxComponents && selectedCount > this.maxComponents) {
        return { valid: false, message: `Select at most ${this.maxComponents}` };
    }
    return { valid: true };
}
```

---

## Key Pitfalls

1. **ParentQuoteLineItemId is not writable** — You cannot set it via DML or PlaceQuote. Use QuoteLineRelationship instead (see PlaceQuote Patterns recipe, Pattern 6).

2. **QuoteLineItemAttribute may not be queryable** — Wrap attribute queries in try-catch. Some orgs have this object disabled or restricted.

3. **PricebookEntry resolution** — Each child product needs a PricebookEntry in the Quote's Pricebook. Resolve this before building PlaceQuote requests.

4. **Nesting limit** — Cap recursion at 3 levels (0, 1, 2) to avoid hitting governor limits and overly complex UIs.

5. **Duplicate QuoteLineRelationship** — Always check for existing relationships before inserting new ones. The engine may auto-create some via `executeConfigurationRules`.

---

*Based on the Mobile TLE Bundle Configurator project (v1.2, June 2026).*
