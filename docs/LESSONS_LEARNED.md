# Lessons Learned — Mobile TLE Bundle Configurator

Accumulated learnings from building and maintaining the Mobile TLE component on Revenue Cloud Advanced (RCA).

---

## L-005: PeriodBoundary is mandatory for TermDefined products (v2.1)

**Date:** 2026-10-02
**Severity:** Breaking — prevents adding products
**Applies to:** TermDefined selling model products

**Symptom:** Adding a TermDefined product via PlaceQuote fails with:
> "Enter a start proration period with one of these values: AlignToCalendar, Anniversary, DayOfPeriod, or LastDayOfPeriod."

**Root cause:** Recent RCA platform releases made the `PeriodBoundary` field mandatory on `QuoteLineItem` for TermDefined products. Previously it was optional/defaulted by the engine; now it must be explicitly set in the PlaceQuote graph.

**Fix:** Set `PeriodBoundary` and `ProrationPolicyId` on every TermDefined line in the PlaceQuote graph:

```apex
// In the PlaceQuote graph body for TermDefined lines:
body.put('PeriodBoundary', 'Anniversary');      // Default — matches most demo data
body.put('ProrationPolicyId', prorationPolicyId); // Query: SELECT Id FROM ProrationPolicy WHERE Name = 'Default Proration Policy'
```

**Valid PeriodBoundary values:**

| Value | Meaning |
|-------|---------|
| `AlignToCalendar` | Aligns billing period to calendar boundaries |
| `Anniversary` | Period starts on the subscription start date (most common) |
| `DayOfPeriod` | Specific day within each period |
| `LastDayOfPeriod` | Last day of each billing period |

**Key takeaway:** When the RCA platform adds new mandatory fields, PlaceQuote calls that previously worked will start failing. Always check PlaceQuote error messages for field validation hints — they typically list the accepted values.

**Bundle impact:** `PeriodBoundary` and `ProrationPolicyId` must also be propagated to bundle child lines via `applyBundleConfigChanges()`.

---

## L-004: Date fields must be String-serialized (v1.4)

**Date:** 2026-06-15
**Severity:** Silent pricing failure
**Applies to:** All date fields in PlaceQuote graphs

**Symptom:** PlaceQuote returns success but dates are null/wrong on created lines. No error thrown.

**Fix:** Always serialize dates as strings in `yyyy-MM-dd` format:

```apex
body.put('StartDate', String.valueOf(startDate));  // Correct
body.put('StartDate', startDate);                   // WRONG — silent failure
```

**Key takeaway:** PlaceQuote silently ignores Date-typed values. Always use `String.valueOf()` for date fields.

---

## L-003: CurrencyIsoCode fallback chain (v1.3)

**Date:** 2026-06-13
**Severity:** Error on multi-currency orgs

**Symptom:** Component fails to load or price on orgs with multi-currency enabled.

**Fix:** Implemented a 6-step currency resolution fallback chain in `getQuoteCurrency()`.

**Key takeaway:** Never assume a single currency source — multi-currency orgs may have currency at Quote, Opportunity, Account, User, or Org level.

---

## L-002: PlaceQuote PATCH for repricing (v1.2)

**Date:** 2026-06-12
**Severity:** Incorrect prices after inline edit

**Symptom:** Editing quantity/discount doesn't update calculated price fields.

**Fix:** Use PlaceQuote PATCH (not POST) for repricing existing lines. Include `Force` pricing preference and `Skip` configuration.

**Key takeaway:** Repricing existing lines requires PATCH method + Force pricing. POST is only for adding new lines.

---

## L-001: RCA orgs required (v1.4 install failure)

**Date:** 2026-06-24
**Severity:** 176+ compilation errors on install

**Symptom:** Package install fails on standard SDO/trial orgs.

**Root cause:** Component depends on RCA-specific sObjects (`QuoteLineItemAttribute`, `QuoteLineRelationship`, `ProductSellingModel`) and fields (`ParentQuoteLineItemId`, `BillingFrequency`, `ProductSellingModelId`, `NetUnitPrice`) that only exist on RCA-enabled orgs.

**Key takeaway:** Always verify RCA prerequisites before attempting install. See the Pre-Install Checklist in README.
