# Recipe: Mobile LWC Architecture for RCA

> **Product**: Salesforce Revenue Cloud Advanced (RCA), Lightning Web Components
> **Complexity**: Advanced

---

## Overview

This recipe documents the component hierarchy, event patterns, and architectural decisions for building a mobile-first LWC that integrates with Revenue Cloud Advanced. Based on the Mobile TLE (Transaction Line Editor) — a 13-component, production-grade implementation.

---

## Component Hierarchy

```
mobileTransactionLineEditor (Parent Container)
 │
 │── Header: title, Add Product button, Refresh button
 │── Quote Summary: subtotal, discount, grand total
 │
 ├── mobileTleLineList (Line List Manager)
 │    │
 │    └── mobileTleLineCard (×N — one per QuoteLineItem)
 │         ├── Product image, name, charge type
 │         ├── Pricing: list price, quantity, discount, net price
 │         ├── Bundle badge: "8 items" child count
 │         ├── Inline editors: qty stepper, discount input
 │         └── Action menu trigger
 │
 ├── mobileTleBottomSheet (Action Sheet — iOS style)
 │    ├── View detail
 │    ├── Clone line
 │    ├── Configure (bundles only)
 │    └── Delete
 │
 ├── mobileTleProductBrowser (Product Search & Add)
 │    ├── Search bar + category filter
 │    ├── Catalog selector
 │    │
 │    └── mobileTleProductCard (×N — one per product)
 │         ├── Product image, name, code, price
 │         ├── Selling model selector
 │         ├── Bundle indicator + child count
 │         └── Add button
 │
 └── mobileTleConfigurator (Bundle Configurator)
      │
      ├── mobileTleConfigGroup (×N — one per ProductComponentGroup)
      │    ├── Group name, selection counter, cardinality hint
      │    ├── Collapse/expand toggle
      │    ├── Validation error display
      │    │
      │    └── mobileTleConfigOption (×N — one per option)
      │         ├── Checkbox toggle (select/deselect)
      │         ├── Quantity stepper (min/max)
      │         ├── Required/nested-bundle badges
      │         │
      │         ├── mobileTleConfigAttributes (collapsible)
      │         │    └── Picklist, Number, Text inputs
      │         │
      │         └── mobileTleConfigGroup (recursive — nested bundle)
      │              └── (up to 3 levels deep)
      │
      └── Save / Cancel buttons

Shared utilities:
 └── mobileTleUtils (formatters, constants, shared functions)
```

---

## Event Flow Patterns

### Pattern 1: Inline Edit → Reprice → Refresh

```
mobileTleLineCard                mobileTransactionLineEditor         Apex Controller
     │                                    │                              │
     │ ── handleQuantityChange ──────────>│                              │
     │    (CustomEvent: 'inlineedit')     │                              │
     │                                    │── updateLineSingleField ────>│
     │                                    │   (imperative Apex call)     │── updateFieldViaPlaceQuote()
     │                                    │                              │   (PlaceQuote PATCH)
     │                                    │<── success ─────────────────│
     │                                    │                              │
     │                                    │── fetchLines() ────────────>│
     │                                    │   (refresh all lines)        │── SOQL query
     │                                    │<── updated lines ──────────│
     │<── re-render with new data ────────│                              │
```

### Pattern 2: Add Product → PlaceQuote → Refresh

```
mobileTleProductCard             mobileTleProductBrowser          mobileTransactionLineEditor     Apex
     │                                 │                                  │                        │
     │── 'addproduct' event ─────────>│                                  │                        │
     │                                 │── 'productselected' event ─────>│                        │
     │                                 │                                  │── addQuoteLineWithModel ──>│
     │                                 │                                  │                        │── addLineViaPlaceQuote()
     │                                 │                                  │<── newLineId ─────────│
     │                                 │                                  │── fetchLines() ──────>│
     │                                 │<── close browser ───────────────│                        │
```

### Pattern 3: Configure Bundle → Save → Refresh

```
mobileTleConfigurator            mobileTransactionLineEditor         Apex Controller
     │                                    │                              │
     │── loadBundleConfiguration ────────────────────────────────────────>│
     │<── BundleConfigState ─────────────────────────────────────────────│
     │                                    │                              │
     │ (user selects/deselects options)   │                              │
     │                                    │                              │
     │── saveBundleConfiguration ────────────────────────────────────────>│
     │   (List<ConfigChange>)             │                              │── PlaceQuote (adds/updates)
     │                                    │                              │── DML (deletes)
     │                                    │                              │── DML (QuoteLineRelationship)
     │                                    │                              │── DML (QuoteLineItemAttribute)
     │<── updated BundleConfigState ─────────────────────────────────────│
     │                                    │                              │
     │── 'configurationsaved' event ─────>│                              │
     │                                    │── fetchLines() ──────────────>│
```

---

## Design Decisions

### 1. PlaceQuote-Only for Writes

**Decision**: ALL pricing-sensitive mutations route through the PlaceQuote API. Never use raw DML for Quantity, Discount, or UnitPrice.

**Why**: Raw DML (`Database.update`) persists field values but does NOT trigger the RCA pricing engine. This causes NetUnitPrice, NetTotalPrice, TotalPrice, and Quote Summary to become stale. This was the root cause of BUG-CDO-001.

### 2. SOQL-Only for Reads

**Decision**: All data retrieval uses direct SOQL queries, not API calls.

**Why**: SOQL is faster and more governor-limit-friendly than API round-trips. Since reads don't affect pricing, there's no need for the PlaceQuote overhead.

### 3. Card-Based Layout (Not Tables)

**Decision**: Each QuoteLineItem is rendered as a card, not a table row.

**Why**: Mobile form factors need touch-friendly, vertically scrollable UI. Cards adapt naturally to varying screen widths and support rich content (images, badges, action menus).

### 4. Bottom Sheet for Actions (Not Context Menu)

**Decision**: Line-level actions use an iOS-style bottom sheet, not a right-click context menu or dropdown.

**Why**: Bottom sheets are the standard mobile pattern — they're thumb-friendly, dismissible with swipe, and provide a clear modal context.

### 5. Custom Labels for All UI Strings

**Decision**: Every user-visible string uses Custom Labels, not hardcoded text.

**Why**: Enables multi-language support. The component ships with Spanish labels out of the box and can be extended to any language via Translation Workbench.

### 6. Recursive Nesting with a Hard Cap

**Decision**: Bundle configurator supports up to 3 levels of nesting, enforced by a counter.

**Why**: Deeper nesting hits governor limits (SOQL queries compound per level) and creates unusable UIs on mobile. Three levels covers the vast majority of real-world bundle hierarchies.

---

## LWC Component Contracts

### mobileTransactionLineEditor (Parent)

**API Properties:**
| Property | Type | Description |
|----------|------|-------------|
| `recordId` | `Id` | Quote record Id (set automatically from record page context) |

**Public Methods:** None — communicates via @wire and imperative Apex.

**Events Handled:**
| Event | Source | Action |
|-------|--------|--------|
| `inlineedit` | mobileTleLineCard | Call `updateLineSingleField` → PlaceQuote → refresh |
| `lineaction` | mobileTleLineCard | Open bottom sheet with action options |
| `productselected` | mobileTleProductBrowser | Call `addQuoteLineWithModel` → PlaceQuote → refresh |
| `configurationsaved` | mobileTleConfigurator | Refresh lines |

---

### mobileTleLineCard

**API Properties:**
| Property | Type | Description |
|----------|------|-------------|
| `line` | `MobileLineRow` | The line data to display |
| `currencyCode` | `String` | Currency ISO code for formatting |

**Events Dispatched:**
| Event | Detail | When |
|-------|--------|------|
| `inlineedit` | `{ lineId, fieldName, value }` | User saves an inline edit |
| `lineaction` | `{ lineId, action }` | User selects an action from the menu |

---

### mobileTleConfigurator

**API Properties:**
| Property | Type | Description |
|----------|------|-------------|
| `quoteId` | `Id` | Quote record Id |
| `lineId` | `Id` | QuoteLineItem Id of the bundle parent |

**Events Dispatched:**
| Event | Detail | When |
|-------|--------|------|
| `configurationsaved` | `{}` | Bundle config saved successfully |
| `close` | `{}` | User cancels or closes the configurator |

---

### mobileTleConfigGroup

**API Properties:**
| Property | Type | Description |
|----------|------|-------------|
| `group` | `ConfigGroup` | Group data with options |
| `level` | `Integer` | Nesting level (0, 1, 2) |

**Public Methods:**
| Method | Returns | Description |
|--------|---------|-------------|
| `validate()` | `{ valid, message }` | Validates cardinality (min/max selection count) |

---

## File Structure

```
force-app/main/default/
├── classes/
│   ├── MobileTleController.cls          # Main Apex controller (~2400 lines)
│   ├── MobileTleController.cls-meta.xml
│   ├── QuoteLineEditorController.cls    # Desktop editor (FieldSet-based)
│   └── QuoteLineEditorController.cls-meta.xml
│
├── lwc/
│   ├── mobileTransactionLineEditor/     # Parent container
│   ├── mobileTleLineList/               # Line list manager
│   ├── mobileTleLineCard/               # Line item card
│   ├── mobileTleBottomSheet/            # Action sheet
│   ├── mobileTleProductBrowser/         # Product search/add
│   ├── mobileTleProductCard/            # Product card in browser
│   ├── mobileTleConfigurator/           # Bundle configurator
│   ├── mobileTleConfigGroup/            # Config group renderer
│   ├── mobileTleConfigOption/           # Config option card
│   ├── mobileTleConfigAttributes/       # Attribute editor
│   ├── mobileTleUtils/                  # Shared utilities
│   ├── quoteLineBundleEditor/           # Desktop bundle editor
│   └── dealDeskOptimizer/               # Deal desk component
│
├── labels/
│   └── CustomLabels.labels-meta.xml     # 16 custom labels (ES/EN)
│
└── objects/QuoteLineItem/
    └── fieldSets/
        └── Quote_Line_Editor_Columns.fieldSet-meta.xml
```

---

## Responsive Design Tips

1. **Use CSS custom properties** for breakpoints — test on 375px (iPhone SE), 768px (iPad), 1024px (desktop)
2. **Touch targets** minimum 44×44px per Apple HIG
3. **Bottom sheet height** — cap at 60vh to keep context visible
4. **Card padding** — 12-16px on mobile, 16-24px on tablet
5. **Font sizes** — minimum 14px for body text on mobile
6. **Inline editors** — use `<lightning-input>` with `type="number"` for native mobile keyboard

---

*Based on the Mobile TLE Bundle Configurator project (v1.2, June 2026). 13 LWC bundles, 3 Apex classes, 16 Custom Labels.*
