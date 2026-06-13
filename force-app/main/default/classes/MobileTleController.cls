/**
 * Apex controller for the mobileTransactionLineEditor LWC.
 *
 * Uses the standard RCA PlaceQuote Apex API as the sole mechanism for
 * adding products to quotes (both standalone and bundles).
 *
 * Key patterns:
 *   - PlaceQuote-only add strategy (no Flow or DML fallback)
 *   - addDefaultConfiguration=true for automatic bundle child creation
 *   - ProductSellingModel passed in the PlaceQuote graph
 *   - Product images via Product2.DisplayUrl
 *   - Per-product selling model options (ProductSellingModelOption)
 *   - Pagination via pageToken / OFFSET
 *   - Dynamic default catalog from Product Discovery Settings
 *   - Clone line via PlaceQuote API
 *   - Single-field inline edit
 */
public with sharing class MobileTleController {

    private static final String DEFAULT_FIELD_SET = 'Quote_Line_Editor_Columns';

    @TestVisible
    private static Boolean USE_SOQL_FALLBACK = Test.isRunningTest();

    // ─── DTOs ────────────────────────────────────────────────────────────────

    public class QuoteContext {
        @AuraEnabled public Id quoteId { get; set; }
        @AuraEnabled public Id pricebook2Id { get; set; }
        @AuraEnabled public String pricebook2Name { get; set; }
        @AuraEnabled public String currencyIsoCode { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Boolean hasPricebook { get; set; }
    }

    public class MobileLineRow {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public Id parentId { get; set; }
        @AuraEnabled public String productName { get; set; }
        @AuraEnabled public String productDescription { get; set; }
        @AuraEnabled public String productImageUrl { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }
        @AuraEnabled public Decimal discount { get; set; }
        @AuraEnabled public Decimal listPrice { get; set; }
        @AuraEnabled public Decimal netUnitPrice { get; set; }
        @AuraEnabled public Decimal netTotalPrice { get; set; }
        @AuraEnabled public Decimal totalPrice { get; set; }
        @AuraEnabled public String sellingModelType { get; set; }
        @AuraEnabled public String currencyIsoCode { get; set; }
        @AuraEnabled public Boolean isBundleParent { get; set; }
        @AuraEnabled public Boolean isConfigurable { get; set; }
        @AuraEnabled public String configFlowApiName { get; set; }
        @AuraEnabled public Integer childCount { get; set; }
        @AuraEnabled public Map<String, Object> fieldValues { get; set; }
    }

    public class ColumnDefinition {
        @AuraEnabled public String apiName { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String type { get; set; }
    }

    public class CatalogOption {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
    }

    public class CategoryOption {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
    }

    public class CatalogSearchContext {
        @AuraEnabled public Id catalogId { get; set; }
        @AuraEnabled public Id categoryId { get; set; }
        @AuraEnabled public String catalogName { get; set; }
        @AuraEnabled public String categoryName { get; set; }
    }

    public class MobileProductCard {
        @AuraEnabled public String product2Id { get; set; }
        @AuraEnabled public String pricebookEntryId { get; set; }
        @AuraEnabled public String productName { get; set; }
        @AuraEnabled public String productDescription { get; set; }
        @AuraEnabled public String productCode { get; set; }
        @AuraEnabled public String productImageUrl { get; set; }
        @AuraEnabled public Decimal unitPrice { get; set; }
        @AuraEnabled public String currencyIsoCode { get; set; }
        @AuraEnabled public String sellingModelName { get; set; }
        @AuraEnabled public List<SellingModelOption> sellingModels { get; set; }
        @AuraEnabled public String defaultSellingModelId { get; set; }
        @AuraEnabled public Boolean isBundle { get; set; }
        @AuraEnabled public Boolean isConfigurable { get; set; }
        @AuraEnabled public Integer bundleChildCount { get; set; }
        @AuraEnabled public List<BundleChildInfo> bundleChildren { get; set; }
    }

    public class BundleChildInfo {
        @AuraEnabled public String product2Id { get; set; }
        @AuraEnabled public String productName { get; set; }
        @AuraEnabled public String productDescription { get; set; }
        @AuraEnabled public String productCode { get; set; }
    }

    // ─── Product Data Translation DTO ─────────────────────────────────
    private class ProductTranslation {
        String name;
        String description;
    }

    public class SellingModelOption {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String sellingModelType { get; set; }
    }

    public class ProductPage {
        @AuraEnabled public List<MobileProductCard> products { get; set; }
        @AuraEnabled public String nextPageToken { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
    }

    public class PricebookOption {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
    }

    // ─── Bundle Configurator DTOs ────────────────────────────────────────────

    public class BundleConfigState {
        @AuraEnabled public String quoteLineItemId { get; set; }
        @AuraEnabled public String product2Id { get; set; }
        @AuraEnabled public String productName { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }
        @AuraEnabled public Decimal unitPrice { get; set; }
        @AuraEnabled public String currencyIsoCode { get; set; }
        @AuraEnabled public List<ConfigGroup> groups { get; set; }
        @AuraEnabled public List<ConfigAttribute> attributes { get; set; }
    }

    public class ConfigGroup {
        @AuraEnabled public String groupId { get; set; }
        @AuraEnabled public String groupName { get; set; }
        @AuraEnabled public Integer minSelections { get; set; }
        @AuraEnabled public Integer maxSelections { get; set; }
        @AuraEnabled public Integer sequence { get; set; }
        @AuraEnabled public List<ConfigOption> options { get; set; }
    }

    public class ConfigOption {
        @AuraEnabled public String productRelatedComponentId { get; set; }
        @AuraEnabled public String childProduct2Id { get; set; }
        @AuraEnabled public String childProductName { get; set; }
        @AuraEnabled public String childProductCode { get; set; }
        @AuraEnabled public String pricebookEntryId { get; set; }
        @AuraEnabled public Boolean isDefault { get; set; }
        @AuraEnabled public Boolean isRequired { get; set; }
        @AuraEnabled public Decimal minQuantity { get; set; }
        @AuraEnabled public Decimal maxQuantity { get; set; }
        @AuraEnabled public Decimal defaultQuantity { get; set; }
        @AuraEnabled public Boolean isQuantityEditable { get; set; }
        @AuraEnabled public Integer sequence { get; set; }
        @AuraEnabled public Decimal currentUnitPrice { get; set; }
        // Current quote state
        @AuraEnabled public String quoteLineItemId { get; set; }
        @AuraEnabled public Boolean isSelected { get; set; }
        @AuraEnabled public Decimal currentQuantity { get; set; }
        // Nested bundle support
        @AuraEnabled public Boolean isNestedBundle { get; set; }
        @AuraEnabled public List<ConfigGroup> childGroups { get; set; }
        // Attributes
        @AuraEnabled public List<ConfigAttribute> attributes { get; set; }
    }

    public class ConfigAttribute {
        @AuraEnabled public String attributeDefinitionId { get; set; }
        @AuraEnabled public String attributeName { get; set; }
        @AuraEnabled public String dataType { get; set; }
        @AuraEnabled public String defaultValue { get; set; }
        @AuraEnabled public Boolean isRequired { get; set; }
        @AuraEnabled public String currentValue { get; set; }
        @AuraEnabled public String quoteLineItemAttributeId { get; set; }
        @AuraEnabled public List<AttributePicklistOption> picklistValues { get; set; }
    }

    public class AttributePicklistOption {
        @AuraEnabled public String value { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String picklistValueId { get; set; }
    }

    public class ConfigChange {
        @AuraEnabled public String action { get; set; }           // ADD, REMOVE, UPDATE
        @AuraEnabled public String productRelatedComponentId { get; set; }
        @AuraEnabled public String childProduct2Id { get; set; }
        @AuraEnabled public String pricebookEntryId { get; set; }
        @AuraEnabled public String quoteLineItemId { get; set; }  // for UPDATE/REMOVE
        @AuraEnabled public Decimal quantity { get; set; }
        @AuraEnabled public Decimal unitPrice { get; set; }
        @AuraEnabled public String sellingModelId { get; set; }
        @AuraEnabled public List<AttributeChange> attributes { get; set; }
    }

    public class AttributeChange {
        @AuraEnabled public String attributeDefinitionId { get; set; }
        @AuraEnabled public String value { get; set; }
        @AuraEnabled public String picklistValueId { get; set; }
    }

    // ─── Quote Context ───────────────────────────────────────────────────────

    @AuraEnabled
    public static QuoteContext getQuoteContext(Id quoteId) {
        if (quoteId == null) {
            throw new AuraHandledException('Quote Id is required.');
        }
        Boolean isMulti = Schema.SObjectType.Quote.fields.getMap().containsKey('CurrencyIsoCode');
        List<String> fields = new List<String>{ 'Id', 'Pricebook2Id', 'Pricebook2.Name', 'Status', 'OpportunityId' };
        if (isMulti) {
            fields.add('CurrencyIsoCode');
            fields.add('Opportunity.CurrencyIsoCode');
            fields.add('Opportunity.Account.CurrencyIsoCode');
        }
        String soql = 'SELECT ' + String.join(fields, ',') +
            ' FROM Quote WHERE Id = :quoteId WITH SECURITY_ENFORCED LIMIT 1';
        List<Quote> rows = (List<Quote>) Database.query(soql);
        if (rows.isEmpty()) {
            throw new AuraHandledException('Quote not found.');
        }
        Quote q = rows[0];
        QuoteContext ctx = new QuoteContext();
        ctx.quoteId = q.Id;
        ctx.pricebook2Id = q.Pricebook2Id;
        ctx.pricebook2Name = q.Pricebook2Id != null ? q.getSObject('Pricebook2')?.get('Name')?.toString() : null;
        ctx.status = q.Status;
        ctx.hasPricebook = q.Pricebook2Id != null;
        if (isMulti) {
            // Use the full resolution chain: Quote → Opp → Account → Org default
            ctx.currencyIsoCode = getQuoteCurrency(q);
        }
        return ctx;
    }

    // ─── Field-set columns (reuse existing pattern) ─────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ColumnDefinition> getFieldSetColumns(String fieldSetName) {
        String fsName = String.isNotBlank(fieldSetName) ? fieldSetName : DEFAULT_FIELD_SET;
        Schema.FieldSet fs = Schema.SObjectType.QuoteLineItem.FieldSets.getMap().get(fsName);
        if (fs == null) {
            throw new AuraHandledException('Field set not found: ' + fsName);
        }
        List<ColumnDefinition> cols = new List<ColumnDefinition>();
        Schema.SObjectField productNameField = Schema.SObjectType.Product2.fields.getMap().get('Name');
        if (productNameField != null && productNameField.getDescribe().isAccessible()) {
            ColumnDefinition nameCol = new ColumnDefinition();
            nameCol.apiName = 'ProductName';
            nameCol.label = productNameField.getDescribe().getLabel();
            nameCol.type = 'STRING';
            cols.add(nameCol);
        }
        for (Schema.FieldSetMember fsm : fs.getFields()) {
            String path = fsm.getFieldPath();
            if (path.contains('.')) {
                continue;
            }
            Schema.SObjectField tok = fsm.getSObjectField();
            Schema.DescribeFieldResult dfr = tok.getDescribe();
            if (!dfr.isAccessible()) {
                continue;
            }
            ColumnDefinition c = new ColumnDefinition();
            c.apiName = path;
            c.label = dfr.getLabel();
            c.type = String.valueOf(dfr.getType());
            cols.add(c);
        }
        return cols;
    }

    // ─── Lines (read) ───────────────────────────────────────────────────────

    @AuraEnabled
    public static List<MobileLineRow> getLines(Id quoteId, String fieldSetName) {
        if (quoteId == null) {
            throw new AuraHandledException('Quote Id is required.');
        }
        String fsName = String.isNotBlank(fieldSetName) ? fieldSetName : DEFAULT_FIELD_SET;
        Schema.FieldSet fs = Schema.SObjectType.QuoteLineItem.FieldSets.getMap().get(fsName);
        if (fs == null) {
            throw new AuraHandledException('Field set not found: ' + fsName);
        }

        Set<String> fieldNames = new Set<String>{
            'Id', 'QuoteId', 'ParentQuoteLineItemId', 'Product2Id',
            'Quantity', 'Discount', 'ListPrice', 'UnitPrice', 'TotalPrice'
        };
        // Add NetUnitPrice and NetTotalPrice if they exist
        Map<String, Schema.SObjectField> qliFields = Schema.SObjectType.QuoteLineItem.fields.getMap();
        if (qliFields.containsKey('NetUnitPrice')) {
            fieldNames.add('NetUnitPrice');
        }
        if (qliFields.containsKey('NetTotalPrice')) {
            fieldNames.add('NetTotalPrice');
        }
        if (qliFields.containsKey('SellingModelType')) {
            fieldNames.add('SellingModelType');
        }
        if (qliFields.containsKey('CurrencyIsoCode')) {
            fieldNames.add('CurrencyIsoCode');
        }

        for (Schema.FieldSetMember fsm : fs.getFields()) {
            String path = fsm.getFieldPath();
            if (!path.contains('.')) {
                fieldNames.add(path);
            }
        }
        List<String> ordered = new List<String>(fieldNames);
        ordered.sort();
        if (!ordered.contains('Product2.Name')) {
            ordered.add('Product2.Name');
        }
        // Add Product2.DisplayUrl for product images
        ordered.add('Product2.DisplayUrl');

        String soql =
            'SELECT ' + String.join(ordered, ',') +
            ' FROM QuoteLineItem WHERE QuoteId = :quoteId ORDER BY LineNumber NULLS LAST, CreatedDate';
        List<QuoteLineItem> rows;
        try {
            rows = Database.query(soql);
        } catch (Exception e) {
            throw new AuraHandledException('Query failed: ' + e.getMessage());
        }

        // Build parent/child maps
        Set<Id> parentLineIds = new Set<Id>();
        Map<Id, Integer> childCountMap = new Map<Id, Integer>();
        Set<Id> productIds = new Set<Id>();
        for (QuoteLineItem qli : rows) {
            if (qli.ParentQuoteLineItemId != null) {
                parentLineIds.add(qli.ParentQuoteLineItemId);
                Integer cnt = childCountMap.containsKey(qli.ParentQuoteLineItemId)
                    ? childCountMap.get(qli.ParentQuoteLineItemId) + 1 : 1;
                childCountMap.put(qli.ParentQuoteLineItemId, cnt);
            }
            if (qli.Product2Id != null) {
                productIds.add(qli.Product2Id);
            }
        }

        // Config flow resolution
        Map<Id, String> configFlowMap = resolveConfigFlowsByProduct(productIds);
        String defaultFlowApi = resolveDefaultConfigFlowApiName();

        List<MobileLineRow> outRows = new List<MobileLineRow>();
        for (QuoteLineItem qli : rows) {
            MobileLineRow lr = new MobileLineRow();
            lr.id = qli.Id;
            lr.parentId = qli.ParentQuoteLineItemId;

            SObject p2 = qli.getSObject('Product2');
            lr.productName = p2 != null ? (String) p2.get('Name') : null;
            lr.productImageUrl = p2 != null ? (String) p2.get('DisplayUrl') : null;

            lr.quantity = qli.Quantity;
            lr.discount = qli.Discount;
            lr.listPrice = qli.ListPrice;
            lr.totalPrice = qli.TotalPrice;
            lr.netUnitPrice = qliFields.containsKey('NetUnitPrice') ? (Decimal) qli.get('NetUnitPrice') : qli.UnitPrice;
            lr.netTotalPrice = qliFields.containsKey('NetTotalPrice') ? (Decimal) qli.get('NetTotalPrice') : qli.TotalPrice;

            if (qliFields.containsKey('SellingModelType')) {
                lr.sellingModelType = (String) qli.get('SellingModelType');
            }
            if (qliFields.containsKey('CurrencyIsoCode')) {
                lr.currencyIsoCode = (String) qli.get('CurrencyIsoCode');
            }

            lr.isBundleParent = parentLineIds.contains(qli.Id);
            lr.childCount = childCountMap.containsKey(qli.Id) ? childCountMap.get(qli.Id) : 0;

            // Config flow
            String flowApi = qli.Product2Id != null ? configFlowMap.get(qli.Product2Id) : null;
            if (String.isBlank(flowApi) && lr.isBundleParent && String.isNotBlank(defaultFlowApi)) {
                flowApi = defaultFlowApi;
            }
            lr.isConfigurable = String.isNotBlank(flowApi);
            lr.configFlowApiName = flowApi;

            // Field values for extra FieldSet fields
            lr.fieldValues = new Map<String, Object>();
            for (String fn : fieldNames) {
                if (fn == 'Id' || fn == 'ParentQuoteLineItemId' || fn == 'QuoteId' || fn == 'Product2Id') {
                    continue;
                }
                lr.fieldValues.put(fn, qli.get(fn));
            }
            lr.fieldValues.put('ProductName', lr.productName);
            outRows.add(lr);
        }

        // Apply translated product names from Product2DataTranslation
        Map<Id, ProductTranslation> txMap = getTranslationMap(productIds);
        if (!txMap.isEmpty()) {
            for (MobileLineRow lr : outRows) {
                // Find the product2Id from the field values or the query
                Id prod2Id = null;
                for (QuoteLineItem qli : rows) {
                    if (qli.Id == lr.id) {
                        prod2Id = qli.Product2Id;
                        break;
                    }
                }
                if (prod2Id != null) {
                    ProductTranslation tx = txMap.get(prod2Id);
                    if (tx != null) {
                        if (String.isNotBlank(tx.name)) {
                            lr.productName = tx.name;
                            lr.fieldValues.put('ProductName', tx.name);
                        }
                        lr.productDescription = tx.description;
                    }
                }
            }
        }

        return outRows;
    }

    // ─── Delete line ────────────────────────────────────────────────────────

    @AuraEnabled
    public static void deleteLine(Id quoteLineItemId) {
        if (quoteLineItemId == null) {
            throw new AuraHandledException('Quote Line Item Id is required.');
        }
        QuoteLineItem qli = [
            SELECT Id FROM QuoteLineItem WHERE Id = :quoteLineItemId WITH SECURITY_ENFORCED LIMIT 1
        ];
        if (!QuoteLineItem.SObjectType.getDescribe().isDeletable()) {
            throw new AuraHandledException('Insufficient access to delete.');
        }
        Database.delete(qli, AccessLevel.USER_MODE);
    }

    // ─── Update single field (inline edit) ──────────────────────────────────

    @AuraEnabled
    public static void updateLineSingleField(Id quoteLineItemId, String fieldName, Object value) {
        if (quoteLineItemId == null || String.isBlank(fieldName)) {
            throw new AuraHandledException('Line Id and field name are required.');
        }
        // Whitelist editable fields for inline edit
        Set<String> allowedInlineFields = new Set<String>{ 'Quantity', 'Discount', 'UnitPrice', 'Description' };
        if (!allowedInlineFields.contains(fieldName)) {
            throw new AuraHandledException('Field not allowed for inline edit: ' + fieldName);
        }
        Schema.SObjectField sf = Schema.SObjectType.QuoteLineItem.fields.getMap().get(fieldName);
        if (sf == null) {
            throw new AuraHandledException('Field does not exist: ' + fieldName);
        }
        Schema.DescribeFieldResult dfr = sf.getDescribe();
        if (!dfr.isUpdateable() || !dfr.isAccessible()) {
            throw new AuraHandledException('Field not editable: ' + fieldName);
        }

        // Pricing-sensitive fields must go through PlaceQuote so the RCA engine
        // recalculates NetUnitPrice, NetTotalPrice, TotalPrice, and Quote totals.
        Set<String> pricingSensitiveFields = new Set<String>{ 'Quantity', 'Discount', 'UnitPrice' };
        if (pricingSensitiveFields.contains(fieldName) && !USE_SOQL_FALLBACK) {
            updateFieldViaPlaceQuote(quoteLineItemId, fieldName, value);
        } else {
            // Non-pricing fields (e.g. Description) or test context — direct DML is fine
            QuoteLineItem qli = new QuoteLineItem(Id = quoteLineItemId);
            qli.put(fieldName, value);
            Database.update(qli, AccessLevel.USER_MODE);
        }
    }

    /**
     * Uses PlaceQuote PATCH to update a single field on a QuoteLineItem,
     * which triggers the RCA pricing engine to recalculate all derived
     * pricing fields (NetUnitPrice, NetTotalPrice, TotalPrice, Quote totals).
     */
    private static void updateFieldViaPlaceQuote(Id quoteLineItemId, String fieldName, Object value) {
        // Look up the QuoteId for the line item
        QuoteLineItem existingQli = [
            SELECT QuoteId FROM QuoteLineItem
            WHERE Id = :quoteLineItemId WITH SECURITY_ENFORCED LIMIT 1
        ];

        // 1. Quote reference — PATCH existing quote
        PlaceQuote.RecordResource quoteRecord =
            new PlaceQuote.RecordResource(Quote.getSobjectType(), 'PATCH', existingQli.QuoteId);
        PlaceQuote.RecordWithReferenceRequest quoteRef =
            new PlaceQuote.RecordWithReferenceRequest('refQuote', quoteRecord);

        // 2. QuoteLineItem — PATCH existing line with the changed field
        PlaceQuote.RecordResource qliRecord = new PlaceQuote.RecordResource(
            QuoteLineItem.getSobjectType(), 'PATCH', quoteLineItemId
        );
        Map<String, Object> fields = new Map<String, Object>();
        fields.put(fieldName, value);
        qliRecord.fieldValues = fields;
        PlaceQuote.RecordWithReferenceRequest qliRef =
            new PlaceQuote.RecordWithReferenceRequest('refQLI', qliRecord);

        // 3. Build graph
        List<PlaceQuote.RecordWithReferenceRequest> records =
            new List<PlaceQuote.RecordWithReferenceRequest>();
        records.add(quoteRef);
        records.add(qliRef);

        PlaceQuote.GraphRequest graph = new PlaceQuote.GraphRequest('inlineEdit', records);

        // 4. Configuration options — no default configuration needed for inline edits
        PlaceQuote.ConfigurationOptionsInput cInput = new PlaceQuote.ConfigurationOptionsInput();
        cInput.addDefaultConfiguration = false;
        cInput.executeConfigurationRules = true;
        cInput.validateAmendRenewCancel = false;
        cInput.validateProductCatalog = false;

        // 5. Execute PlaceQuote with System pricing to trigger reprice
        PlaceQuote.PlaceQuoteResponse resp =
            PlaceQuote.PlaceQuoteRLMApexProcessor.execute(
                PlaceQuote.PricingPreferenceEnum.System,
                graph,
                PlaceQuote.ConfigurationInputEnum.RunAndAllowErrors,
                cInput
            );

        // 6. Check response
        if (resp == null || resp.success != true) {
            String errDetail = '';
            if (resp != null && resp.responseError != null) {
                List<String> msgs = new List<String>();
                for (ConnectApi.PlaceQuoteErrorResponse er : resp.responseError) {
                    msgs.add(er.message);
                }
                errDetail = String.join(msgs, '; ');
            }
            throw new AuraHandledException(
                'Inline edit failed' + (String.isNotBlank(errDetail) ? ': ' + errDetail : '.')
            );
        }
    }

    // ─── Catalogs ───────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<CatalogOption> getProductCatalogs() {
        if (USE_SOQL_FALLBACK) {
            return getCatalogsDirect();
        }
        try {
            return getCatalogsViaDiscovery();
        } catch (Exception e) {
            return getCatalogsDirect();
        }
    }

    private static List<CatalogOption> getCatalogsViaDiscovery() {
        Invocable.Action action = Invocable.Action.createStandardAction('getCatalogs');
        action.setInvocationParameter('recordLimit', 100);
        action.setInvocationParameter('orderBy', new String[]{ 'Name:ASC' });
        List<Invocable.Action.Result> results = action.invoke();
        if (results == null || results.isEmpty() || !results[0].isSuccess()) {
            return new List<CatalogOption>();
        }
        Object raw = results[0].getOutputParameters().get('resultCatalogList');
        return parseCatalogList(raw);
    }

    @TestVisible
    private static List<CatalogOption> getCatalogsDirect() {
        List<CatalogOption> out = new List<CatalogOption>();
        for (ProductCatalog pc : [
            SELECT Id, Name FROM ProductCatalog WITH SECURITY_ENFORCED ORDER BY Name LIMIT 500
        ]) {
            CatalogOption o = new CatalogOption();
            o.id = pc.Id;
            o.name = pc.Name;
            out.add(o);
        }
        return out;
    }

    private static List<CatalogOption> parseCatalogList(Object raw) {
        List<CatalogOption> out = new List<CatalogOption>();
        if (raw == null) {
            return out;
        }
        List<Object> items = (List<Object>) JSON.deserializeUntyped(JSON.serialize(raw));
        for (Object item : items) {
            Map<String, Object> m = (Map<String, Object>) item;
            CatalogOption o = new CatalogOption();
            o.id = (String) m.get('id');
            o.name = (String) m.get('name');
            out.add(o);
        }
        return out;
    }

    // ─── Categories ─────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<CategoryOption> getProductCategoriesForCatalog(Id catalogId) {
        if (catalogId == null) {
            return new List<CategoryOption>();
        }
        if (USE_SOQL_FALLBACK) {
            return getCategoriesForCatalogDirect(catalogId);
        }
        try {
            return getCategoriesViaDiscovery(catalogId);
        } catch (Exception e) {
            return getCategoriesForCatalogDirect(catalogId);
        }
    }

    private static List<CategoryOption> getCategoriesViaDiscovery(Id catalogId) {
        Invocable.Action action = Invocable.Action.createStandardAction('getCategories');
        action.setInvocationParameter('catalogId', String.valueOf(catalogId));
        List<Invocable.Action.Result> results = action.invoke();
        if (results == null || results.isEmpty() || !results[0].isSuccess()) {
            return new List<CategoryOption>();
        }
        Object raw = results[0].getOutputParameters().get('resultCategoryList');
        return parseCategoryList(raw);
    }

    @TestVisible
    private static List<CategoryOption> getCategoriesForCatalogDirect(Id catalogId) {
        List<CategoryOption> out = new List<CategoryOption>();
        for (ProductCategory cat : [
            SELECT Id, Name FROM ProductCategory WHERE CatalogId = :catalogId
            WITH SECURITY_ENFORCED ORDER BY Name LIMIT 2000
        ]) {
            CategoryOption o = new CategoryOption();
            o.id = cat.Id;
            o.name = cat.Name;
            out.add(o);
        }
        return out;
    }

    private static List<CategoryOption> parseCategoryList(Object raw) {
        List<CategoryOption> out = new List<CategoryOption>();
        if (raw == null) {
            return out;
        }
        List<Object> items = (List<Object>) JSON.deserializeUntyped(JSON.serialize(raw));
        for (Object item : items) {
            Map<String, Object> m = (Map<String, Object>) item;
            CategoryOption o = new CategoryOption();
            o.id = (String) m.get('id');
            o.name = (String) m.get('name');
            out.add(o);
        }
        return out;
    }

    // ─── Default catalog context (dynamic, reads org Product Discovery) ─────

    @AuraEnabled(cacheable=true)
    public static CatalogSearchContext getDefaultCatalogContext() {
        CatalogSearchContext ctx = new CatalogSearchContext();
        try {
            // Try to get default catalog via the getCatalogs invocable — the first
            // catalog returned is typically the org default when no explicit setting
            // query is available via standard objects.
            List<CatalogOption> catalogs;
            if (USE_SOQL_FALLBACK) {
                catalogs = getCatalogsDirect();
            } else {
                try {
                    catalogs = getCatalogsViaDiscovery();
                } catch (Exception e) {
                    catalogs = getCatalogsDirect();
                }
            }
            if (catalogs == null || catalogs.isEmpty()) {
                return ctx;
            }
            // Use the first catalog as default
            CatalogOption firstCatalog = catalogs[0];
            ctx.catalogId = (Id) firstCatalog.id;
            ctx.catalogName = firstCatalog.name;

            // Load categories for this default catalog
            List<CategoryOption> categories;
            if (USE_SOQL_FALLBACK) {
                categories = getCategoriesForCatalogDirect(ctx.catalogId);
            } else {
                try {
                    categories = getCategoriesViaDiscovery(ctx.catalogId);
                } catch (Exception e) {
                    categories = getCategoriesForCatalogDirect(ctx.catalogId);
                }
            }
            if (categories != null && !categories.isEmpty()) {
                ctx.categoryId = (Id) categories[0].id;
                ctx.categoryName = categories[0].name;
            }
        } catch (Exception e) {
            // non-fatal; return empty context
        }
        return ctx;
    }

    // ─── List products with pagination ──────────────────────────────────────

    @AuraEnabled
    public static ProductPage getProductsPage(
        Id quoteId, Id catalogId, Id categoryId,
        String pageToken, Integer pageSize
    ) {
        if (quoteId == null) {
            throw new AuraHandledException('Quote Id is required.');
        }
        Integer effectiveSize = (pageSize != null && pageSize > 0 && pageSize <= 50) ? pageSize : 6;
        Quote q = queryQuote(quoteId);

        // SOQL-only strategy: direct SOQL (~200-500 ms) is much faster than the
        // Discovery invocable (~1-2 s).  Categories whose products have no
        // PricebookEntry for the quote currency will correctly return an empty page.
        return listProductsDirectPaged(q, categoryId, pageToken, effectiveSize);
    }

    private static ProductPage listProductsDirectPaged(
        Quote q, Id categoryId, String pageToken, Integer pageSize
    ) {
        ProductPage page = new ProductPage();
        page.products = new List<MobileProductCard>();
        if (categoryId == null || q.Pricebook2Id == null) {
            page.totalCount = 0;
            return page;
        }
        Integer offset = 0;
        if (String.isNotBlank(pageToken)) {
            try {
                offset = Integer.valueOf(pageToken);
            } catch (Exception e) {
                offset = 0;
            }
        }
        Id pbId = q.Pricebook2Id;
        Id productCategoryId = categoryId;
        String quoteCurrency = getQuoteCurrency(q);

        List<String> selectFields = new List<String>{
            'Id', 'Product2Id', 'UnitPrice',
            'Product2.Name', 'Product2.ProductCode', 'Product2.DisplayUrl'
        };
        Map<String, Schema.SObjectField> pbeMap = Schema.SObjectType.PricebookEntry.fields.getMap();
        if (pbeMap.containsKey('CurrencyIsoCode')) {
            selectFields.add('CurrencyIsoCode');
        }
        if (pbeMap.containsKey('ProductSellingModelId')) {
            selectFields.add('ProductSellingModelId');
        }

        String countSoql =
            'SELECT COUNT() FROM PricebookEntry WHERE Pricebook2Id = :pbId' +
            ' AND IsActive = TRUE AND Product2.IsActive = TRUE' +
            ' AND Product2Id IN (SELECT ProductId FROM ProductCategoryProduct WHERE ProductCategoryId = :productCategoryId)';
        if (pbeMap.containsKey('CurrencyIsoCode') && String.isNotBlank(quoteCurrency)) {
            countSoql += ' AND CurrencyIsoCode = :quoteCurrency';
        }
        Integer totalCount = Database.countQuery(countSoql);

        String soql =
            'SELECT ' + String.join(selectFields, ',') +
            ' FROM PricebookEntry WHERE Pricebook2Id = :pbId' +
            ' AND IsActive = TRUE AND Product2.IsActive = TRUE' +
            ' AND Product2Id IN (SELECT ProductId FROM ProductCategoryProduct WHERE ProductCategoryId = :productCategoryId)';
        if (pbeMap.containsKey('CurrencyIsoCode') && String.isNotBlank(quoteCurrency)) {
            soql += ' AND CurrencyIsoCode = :quoteCurrency';
        }
        soql += ' WITH SECURITY_ENFORCED ORDER BY Product2.Name LIMIT :pageSize OFFSET :offset';

        List<PricebookEntry> entries = (List<PricebookEntry>) Database.query(soql);

        // Collect product IDs to fetch selling models
        Set<Id> productIdsForModels = new Set<Id>();
        for (PricebookEntry pbe : entries) {
            productIdsForModels.add(pbe.Product2Id);
        }
        Map<Id, List<SellingModelOption>> sellingModelsMap = getSellingModelsMapForProducts(productIdsForModels);

        for (PricebookEntry pbe : entries) {
            MobileProductCard card = new MobileProductCard();
            card.pricebookEntryId = pbe.Id;
            card.product2Id = pbe.Product2Id;
            SObject p2 = pbe.getSObject('Product2');
            card.productName = p2 != null ? (String) p2.get('Name') : null;
            card.productCode = p2 != null ? (String) p2.get('ProductCode') : null;
            card.productImageUrl = p2 != null ? (String) p2.get('DisplayUrl') : null;
            card.unitPrice = pbe.UnitPrice;
            if (pbeMap.containsKey('CurrencyIsoCode')) {
                card.currencyIsoCode = (String) pbe.get('CurrencyIsoCode');
            }
            card.sellingModels = sellingModelsMap.containsKey(pbe.Product2Id)
                ? sellingModelsMap.get(pbe.Product2Id) : new List<SellingModelOption>();
            if (pbeMap.containsKey('ProductSellingModelId') && pbe.get('ProductSellingModelId') != null) {
                card.defaultSellingModelId = String.valueOf(pbe.get('ProductSellingModelId'));
            }
            page.products.add(card);
        }
        enrichProductCardsWithBundleInfo(page.products);
        applyTranslationsToProductCards(page.products);
        page.totalCount = totalCount;
        Integer nextOffset = offset + pageSize;
        page.nextPageToken = nextOffset < totalCount ? String.valueOf(nextOffset) : null;
        return page;
    }

    // ─── Search products ────────────────────────────────────────────────────

    @AuraEnabled
    public static ProductPage searchProducts(
        Id quoteId, String searchTerm, Id catalogId, Id categoryId, Integer pageSize
    ) {
        if (quoteId == null) {
            throw new AuraHandledException('Quote Id is required.');
        }
        if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
            ProductPage empty = new ProductPage();
            empty.products = new List<MobileProductCard>();
            empty.totalCount = 0;
            return empty;
        }
        Integer effectiveSize = (pageSize != null && pageSize > 0 && pageSize <= 50) ? pageSize : 25;
        Quote q = queryQuote(quoteId);

        // SOQL-only: direct SOQL search is faster than Discovery invocable.
        return searchProductsDirectPaged(q, searchTerm.trim(), categoryId, effectiveSize);
    }

    private static ProductPage searchProductsDirectPaged(
        Quote q, String searchTerm, Id categoryId, Integer rowLimit
    ) {
        ProductPage page = new ProductPage();
        page.products = new List<MobileProductCard>();
        if (categoryId == null || q.Pricebook2Id == null) {
            page.totalCount = 0;
            return page;
        }
        Id pbId = q.Pricebook2Id;
        Id productCategoryId = categoryId;
        String quoteCurrency = getQuoteCurrency(q);
        String term = '%' + searchTerm + '%';

        List<String> selectFields = new List<String>{
            'Id', 'Product2Id', 'UnitPrice',
            'Product2.Name', 'Product2.ProductCode', 'Product2.DisplayUrl'
        };
        Map<String, Schema.SObjectField> pbeMap = Schema.SObjectType.PricebookEntry.fields.getMap();
        if (pbeMap.containsKey('CurrencyIsoCode')) {
            selectFields.add('CurrencyIsoCode');
        }
        if (pbeMap.containsKey('ProductSellingModelId')) {
            selectFields.add('ProductSellingModelId');
        }

        String soql =
            'SELECT ' + String.join(selectFields, ',') +
            ' FROM PricebookEntry WHERE Pricebook2Id = :pbId' +
            ' AND IsActive = TRUE AND Product2.IsActive = TRUE' +
            ' AND Product2Id IN (SELECT ProductId FROM ProductCategoryProduct WHERE ProductCategoryId = :productCategoryId)' +
            ' AND (Product2.Name LIKE :term OR Product2.ProductCode LIKE :term)';
        if (pbeMap.containsKey('CurrencyIsoCode') && String.isNotBlank(quoteCurrency)) {
            soql += ' AND CurrencyIsoCode = :quoteCurrency';
        }
        soql += ' WITH SECURITY_ENFORCED ORDER BY Product2.Name LIMIT :rowLimit';

        List<PricebookEntry> entries = (List<PricebookEntry>) Database.query(soql);

        Set<Id> productIdsForModels = new Set<Id>();
        for (PricebookEntry pbe : entries) {
            productIdsForModels.add(pbe.Product2Id);
        }
        Map<Id, List<SellingModelOption>> sellingModelsMap = getSellingModelsMapForProducts(productIdsForModels);

        for (PricebookEntry pbe : entries) {
            MobileProductCard card = new MobileProductCard();
            card.pricebookEntryId = pbe.Id;
            card.product2Id = pbe.Product2Id;
            SObject p2 = pbe.getSObject('Product2');
            card.productName = p2 != null ? (String) p2.get('Name') : null;
            card.productCode = p2 != null ? (String) p2.get('ProductCode') : null;
            card.productImageUrl = p2 != null ? (String) p2.get('DisplayUrl') : null;
            card.unitPrice = pbe.UnitPrice;
            if (pbeMap.containsKey('CurrencyIsoCode')) {
                card.currencyIsoCode = (String) pbe.get('CurrencyIsoCode');
            }
            card.sellingModels = sellingModelsMap.containsKey(pbe.Product2Id)
                ? sellingModelsMap.get(pbe.Product2Id) : new List<SellingModelOption>();
            if (pbeMap.containsKey('ProductSellingModelId') && pbe.get('ProductSellingModelId') != null) {
                card.defaultSellingModelId = String.valueOf(pbe.get('ProductSellingModelId'));
            }
            page.products.add(card);
        }
        enrichProductCardsWithBundleInfo(page.products);
        applyTranslationsToProductCards(page.products);
        page.totalCount = entries.size();
        return page;
    }

    // ─── Selling Models for a Product ───────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<SellingModelOption> getSellingModelsForProduct(Id product2Id) {
        if (product2Id == null) {
            return new List<SellingModelOption>();
        }
        return querySellingModels(product2Id);
    }

    private static Map<Id, List<SellingModelOption>> getSellingModelsMapForProducts(Set<Id> productIds) {
        Map<Id, List<SellingModelOption>> result = new Map<Id, List<SellingModelOption>>();
        if (productIds == null || productIds.isEmpty()) {
            return result;
        }
        try {
            for (ProductSellingModelOption psmo : [
                SELECT Product2Id, ProductSellingModelId,
                       ProductSellingModel.Name, ProductSellingModel.SellingModelType
                FROM ProductSellingModelOption
                WHERE Product2Id IN :productIds
                WITH SECURITY_ENFORCED
                ORDER BY ProductSellingModel.Name
            ]) {
                if (!result.containsKey(psmo.Product2Id)) {
                    result.put(psmo.Product2Id, new List<SellingModelOption>());
                }
                SellingModelOption opt = new SellingModelOption();
                opt.id = psmo.ProductSellingModelId;
                opt.name = psmo.ProductSellingModel.Name;
                opt.sellingModelType = psmo.ProductSellingModel.SellingModelType;
                result.get(psmo.Product2Id).add(opt);
            }
        } catch (Exception e) {
            // ProductSellingModelOption may not exist in all orgs
        }
        return result;
    }

    private static List<SellingModelOption> querySellingModels(Id product2Id) {
        List<SellingModelOption> out = new List<SellingModelOption>();
        try {
            for (ProductSellingModelOption psmo : [
                SELECT ProductSellingModelId,
                       ProductSellingModel.Name, ProductSellingModel.SellingModelType
                FROM ProductSellingModelOption
                WHERE Product2Id = :product2Id
                WITH SECURITY_ENFORCED
                ORDER BY ProductSellingModel.Name
            ]) {
                SellingModelOption opt = new SellingModelOption();
                opt.id = psmo.ProductSellingModelId;
                opt.name = psmo.ProductSellingModel.Name;
                opt.sellingModelType = psmo.ProductSellingModel.SellingModelType;
                out.add(opt);
            }
        } catch (Exception e) {
            // non-fatal
        }
        return out;
    }

    // ─── Add line via PlaceQuote standard RCA API ──────────────────────────
    // Uses ONLY the PlaceQuote Apex API (standard RCA action).
    // No Flow or DML fallback — PlaceQuote handles:
    //   - Creating the QuoteLineItem with pricing (PricingPreferenceEnum.System)
    //   - Executing configuration rules (ConfigurationInputEnum.RunAndAllowErrors)
    //   - Auto-adding default bundle children (addDefaultConfiguration = true)
    //   - Respecting ProductSellingModel for the line

    @AuraEnabled
    public static Id addQuoteLineWithModel(
        Id quoteId, String product2Id, String pricebookEntryId,
        Decimal unitPrice, Decimal quantity, String sellingModelId
    ) {
        if (quoteId == null || String.isBlank(pricebookEntryId)) {
            throw new AuraHandledException('Quote Id and PricebookEntry Id are required.');
        }
        if (quantity == null || quantity <= 0) {
            quantity = 1;
        }
        PricebookEntry pbe = queryPricebookEntryForAdd((Id) pricebookEntryId);
        String effectiveProduct2Id = String.isBlank(product2Id)
            ? String.valueOf(pbe.Product2Id)
            : product2Id;
        Decimal effectiveUnitPrice = unitPrice == null ? pbe.UnitPrice : unitPrice;
        String billingFrequency = deriveBillingFrequency(pbe, effectiveProduct2Id, sellingModelId);

        // Resolve productSellingModelId from PBE if not explicitly provided
        String productSellingModelId = sellingModelId;
        if (String.isBlank(productSellingModelId) &&
            Schema.SObjectType.PricebookEntry.fields.getMap().containsKey('ProductSellingModelId')) {
            productSellingModelId = (String) pbe.get('ProductSellingModelId');
        }

        // Test context uses DML fallback (PlaceQuote not available in unit tests)
        if (USE_SOQL_FALLBACK) {
            return addLineDirect(quoteId, effectiveProduct2Id, pricebookEntryId,
                effectiveUnitPrice, quantity, billingFrequency);
        }

        // Standard RCA PlaceQuote API — single path, no fallbacks
        return addLineViaPlaceQuote(quoteId, effectiveProduct2Id, pricebookEntryId,
            effectiveUnitPrice, quantity, billingFrequency, productSellingModelId);
    }

    private static PricebookEntry queryPricebookEntryForAdd(Id pricebookEntryId) {
        List<String> fields = new List<String>{ 'Id', 'Product2Id', 'UnitPrice' };
        if (Schema.SObjectType.PricebookEntry.fields.getMap().containsKey('ProductSellingModelId')) {
            fields.add('ProductSellingModelId');
        }
        String soql = 'SELECT ' + String.join(fields, ',') +
            ' FROM PricebookEntry WHERE Id = :pricebookEntryId WITH SECURITY_ENFORCED LIMIT 1';
        List<PricebookEntry> rows = (List<PricebookEntry>) Database.query(soql);
        if (rows.isEmpty()) {
            throw new AuraHandledException('PricebookEntry not found.');
        }
        return rows[0];
    }

    private static Id addLineViaPlaceQuote(
        Id quoteId, String product2Id, String pricebookEntryId,
        Decimal unitPrice, Decimal quantity, String billingFrequency,
        String productSellingModelId
    ) {
        // 1. Quote record — PATCH existing quote (valid methods: POST, PATCH)
        PlaceQuote.RecordResource quoteRecord =
            new PlaceQuote.RecordResource(Quote.getSobjectType(), 'PATCH', quoteId);
        PlaceQuote.RecordWithReferenceRequest quoteRef =
            new PlaceQuote.RecordWithReferenceRequest('refQuote', quoteRecord);

        // 2. QuoteLineItem record — POST new line
        PlaceQuote.RecordResource qliRecord =
            new PlaceQuote.RecordResource(QuoteLineItem.getSobjectType(), 'POST');
        Map<String, Object> qliFields = new Map<String, Object>();
        qliFields.put('QuoteId', '@{refQuote.id}');
        qliFields.put('PricebookEntryId', pricebookEntryId);
        if (String.isNotBlank(product2Id)) {
            qliFields.put('Product2Id', product2Id);
        }
        qliFields.put('Quantity', quantity);
        qliFields.put('UnitPrice', unitPrice);
        if (String.isNotBlank(billingFrequency)) {
            qliFields.put('BillingFrequency', billingFrequency);
        }
        // ProductSellingModelId — only include when the running user has FLS write
        // access.  PlaceQuote respects field-level security, so passing a field the
        // profile cannot write causes "Unable to create/update fields" errors.
        // When omitted, RCA resolves the selling model automatically via
        // addDefaultConfiguration = true.
        if (String.isNotBlank(productSellingModelId)) {
            Schema.DescribeFieldResult psmField =
                QuoteLineItem.ProductSellingModelId.getDescribe();
            if (psmField.isCreateable()) {
                qliFields.put('ProductSellingModelId', productSellingModelId);
            }
        }
        qliRecord.fieldValues = qliFields;

        PlaceQuote.RecordWithReferenceRequest qliRef =
            new PlaceQuote.RecordWithReferenceRequest('refQLI', qliRecord);

        // 3. Build the graph with quote + line records
        List<PlaceQuote.RecordWithReferenceRequest> records =
            new List<PlaceQuote.RecordWithReferenceRequest>();
        records.add(quoteRef);
        records.add(qliRef);

        PlaceQuote.GraphRequest graph = new PlaceQuote.GraphRequest('addLine', records);

        // 4. Configuration options — enable default configuration for bundles
        //    This auto-creates child lines with default quantities/attributes
        PlaceQuote.ConfigurationOptionsInput cInput = new PlaceQuote.ConfigurationOptionsInput();
        cInput.addDefaultConfiguration = true;
        cInput.executeConfigurationRules = true;
        cInput.validateAmendRenewCancel = false;
        cInput.validateProductCatalog = true;

        // 5. Pricing = System (let RCA calculate from pricebook/rate cards)
        //    Configuration = RunAndAllowErrors (non-blocking rule violations)
        PlaceQuote.PricingPreferenceEnum pricingPref =
            PlaceQuote.PricingPreferenceEnum.System;
        PlaceQuote.ConfigurationInputEnum configPref =
            PlaceQuote.ConfigurationInputEnum.RunAndAllowErrors;

        // 6. Execute PlaceQuote
        PlaceQuote.PlaceQuoteResponse resp =
            PlaceQuote.PlaceQuoteRLMApexProcessor.execute(
                pricingPref, graph, configPref, cInput
            );

        // 7. Check response
        if (resp == null || resp.success != true) {
            String errDetail = '';
            if (resp != null && resp.responseError != null) {
                List<String> msgs = new List<String>();
                for (ConnectApi.PlaceQuoteErrorResponse er : resp.responseError) {
                    msgs.add(er.message);
                }
                errDetail = String.join(msgs, '; ');
            }
            throw new AuraHandledException(
                'PlaceQuote failed' + (String.isNotBlank(errDetail) ? ': ' + errDetail : '.')
            );
        }
        return resp.quoteId;
    }

    // addLineViaRcaFlow — REMOVED
    // Flow-based fallback has been removed. The standard PlaceQuote API is the
    // sole mechanism for adding products to quotes. This aligns with RCA best
    // practices: PlaceQuote handles pricing, configuration rules, and default
    // bundle child creation in a single synchronous call.

    @TestVisible
    private static Id addLineDirect(
        Id quoteId, String product2Id, String pricebookEntryId,
        Decimal unitPrice, Decimal quantity, String billingFrequency
    ) {
        if (!QuoteLineItem.SObjectType.getDescribe().isCreateable()) {
            throw new AuraHandledException('Insufficient access to create quote lines.');
        }
        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = quoteId,
            PricebookEntryId = (Id) pricebookEntryId,
            Quantity = quantity,
            UnitPrice = unitPrice
        );
        if (String.isNotBlank(billingFrequency)) {
            qli.BillingFrequency = billingFrequency;
        }
        try {
            Database.insert(qli, AccessLevel.USER_MODE);
        } catch (DmlException e) {
            throw new AuraHandledException(buildDmlMessage(e));
        }
        return qli.Id;
    }

    // ─── Clone line ─────────────────────────────────────────────────────────

    @AuraEnabled
    public static Id cloneQuoteLine(Id quoteLineItemId) {
        if (quoteLineItemId == null) {
            throw new AuraHandledException('Quote Line Item Id is required.');
        }
        // Query the source line
        QuoteLineItem source = [
            SELECT Id, QuoteId, Product2Id, PricebookEntryId, Quantity, UnitPrice,
                   Discount, BillingFrequency, ParentQuoteLineItemId, Description
            FROM QuoteLineItem
            WHERE Id = :quoteLineItemId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        // Query children of source (for bundle cloning)
        List<QuoteLineItem> sourceChildren = [
            SELECT Id, Product2Id, PricebookEntryId, Quantity, UnitPrice,
                   Discount, BillingFrequency, Description
            FROM QuoteLineItem
            WHERE ParentQuoteLineItemId = :source.Id AND QuoteId = :source.QuoteId
            WITH SECURITY_ENFORCED
            ORDER BY LineNumber NULLS LAST, CreatedDate
        ];

        // Collect all original line IDs (parent + children) for attribute cloning
        Set<Id> originalLineIds = new Set<Id>{ source.Id };
        for (QuoteLineItem child : sourceChildren) {
            originalLineIds.add(child.Id);
        }

        // Snapshot existing line IDs on the quote before cloning
        Set<Id> existingLineIds = new Set<Id>();
        for (QuoteLineItem existing : [
            SELECT Id FROM QuoteLineItem
            WHERE QuoteId = :source.QuoteId
            WITH SECURITY_ENFORCED
        ]) {
            existingLineIds.add(existing.Id);
        }

        if (USE_SOQL_FALLBACK) {
            Id newId = cloneLineDirect(source);
            // Clone attributes for the single line (DML path cannot clone children)
            cloneAttributes(new Map<Id, Id>{ source.Id => newId });
            return newId;
        }

        // Try PlaceQuote clone (handles bundles)
        try {
            Id quoteId = cloneViaPlaceQuote(source, sourceChildren);
            // Find newly created lines by comparing against pre-clone snapshot
            List<QuoteLineItem> allLinesAfter = [
                SELECT Id, Product2Id, ParentQuoteLineItemId
                FROM QuoteLineItem
                WHERE QuoteId = :source.QuoteId
                WITH SECURITY_ENFORCED
            ];
            Map<Id, Id> oldToNewMap = buildOldToNewLineMap(
                source, sourceChildren, existingLineIds, allLinesAfter
            );
            cloneAttributes(oldToNewMap);
            return quoteId;
        } catch (Exception e) {
            // Fallback to direct DML
            Id newId = cloneLineDirect(source);
            cloneAttributes(new Map<Id, Id>{ source.Id => newId });
            return newId;
        }
    }

    /**
     * Build a mapping from original line IDs to newly cloned line IDs.
     * Matches by Product2Id: the parent line first, then children in order.
     */
    private static Map<Id, Id> buildOldToNewLineMap(
        QuoteLineItem source,
        List<QuoteLineItem> sourceChildren,
        Set<Id> existingLineIds,
        List<QuoteLineItem> allLinesAfter
    ) {
        Map<Id, Id> oldToNew = new Map<Id, Id>();

        // Identify new lines (those not in the pre-clone snapshot)
        List<QuoteLineItem> newLines = new List<QuoteLineItem>();
        for (QuoteLineItem qli : allLinesAfter) {
            if (!existingLineIds.contains(qli.Id)) {
                newLines.add(qli);
            }
        }

        // Find the new parent line: same Product2Id as source, no parent (or parent is itself new)
        Id newParentId = null;
        for (QuoteLineItem nl : newLines) {
            if (nl.Product2Id == source.Product2Id && nl.ParentQuoteLineItemId == null) {
                newParentId = nl.Id;
                oldToNew.put(source.Id, newParentId);
                break;
            }
        }
        // If parent has a parent (source is a child being cloned standalone), match differently
        if (newParentId == null) {
            for (QuoteLineItem nl : newLines) {
                if (nl.Product2Id == source.Product2Id) {
                    newParentId = nl.Id;
                    oldToNew.put(source.Id, newParentId);
                    break;
                }
            }
        }

        // Map children: match by Product2Id under the new parent
        if (newParentId != null && !sourceChildren.isEmpty()) {
            // Group new children by Product2Id (children of the new parent)
            Map<Id, List<QuoteLineItem>> newChildrenByProduct = new Map<Id, List<QuoteLineItem>>();
            for (QuoteLineItem nl : newLines) {
                if (nl.ParentQuoteLineItemId == newParentId) {
                    if (!newChildrenByProduct.containsKey(nl.Product2Id)) {
                        newChildrenByProduct.put(nl.Product2Id, new List<QuoteLineItem>());
                    }
                    newChildrenByProduct.get(nl.Product2Id).add(nl);
                }
            }
            // Match source children to new children by Product2Id, preserving order
            Map<Id, Integer> productMatchIndex = new Map<Id, Integer>();
            for (QuoteLineItem srcChild : sourceChildren) {
                Id prodId = srcChild.Product2Id;
                Integer idx = productMatchIndex.containsKey(prodId) ? productMatchIndex.get(prodId) : 0;
                List<QuoteLineItem> candidates = newChildrenByProduct.get(prodId);
                if (candidates != null && idx < candidates.size()) {
                    oldToNew.put(srcChild.Id, candidates[idx].Id);
                    productMatchIndex.put(prodId, idx + 1);
                }
            }
        }

        return oldToNew;
    }

    /**
     * Clone QuoteLineItemAttribute records from original lines to their
     * corresponding new cloned lines.
     */
    private static void cloneAttributes(Map<Id, Id> oldToNewLineMap) {
        if (oldToNewLineMap == null || oldToNewLineMap.isEmpty()) {
            return;
        }
        // Query all attributes for the original lines
        Set<Id> sourceLineIds = oldToNewLineMap.keySet();
        List<QuoteLineItemAttribute> sourceAttrs;
        try {
            sourceAttrs = [
                SELECT QuoteLineItemId, AttributeDefinitionId, AttributeName,
                       AttributeValue, AttributePicklistValueId
                FROM QuoteLineItemAttribute
                WHERE QuoteLineItemId IN :sourceLineIds
                WITH SECURITY_ENFORCED
            ];
        } catch (Exception e) {
            // QuoteLineItemAttribute may not be accessible — skip silently
            return;
        }

        if (sourceAttrs == null || sourceAttrs.isEmpty()) {
            return;
        }

        // Build new attribute records pointing to cloned lines
        // Note: AttributeName is auto-derived from AttributeDefinitionId, so we don't set it.
        // QuoteLineItemAttribute is an internal sObject – use insertImmediate().
        List<QuoteLineItemAttribute> newAttrs = new List<QuoteLineItemAttribute>();
        for (QuoteLineItemAttribute attr : sourceAttrs) {
            Id newLineId = oldToNewLineMap.get(attr.QuoteLineItemId);
            if (newLineId == null) {
                continue;
            }
            QuoteLineItemAttribute clone = new QuoteLineItemAttribute();
            clone.QuoteLineItemId = newLineId;
            clone.AttributeDefinitionId = attr.AttributeDefinitionId;
            clone.AttributeValue = attr.AttributeValue;
            if (attr.AttributePicklistValueId != null) {
                clone.AttributePicklistValueId = attr.AttributePicklistValueId;
            }
            newAttrs.add(clone);
        }

        if (!newAttrs.isEmpty()) {
            Database.insertImmediate(newAttrs);
        }
    }

    private static Id cloneViaPlaceQuote(QuoteLineItem source, List<QuoteLineItem> children) {
        PlaceQuote.RecordResource quoteRecord =
            new PlaceQuote.RecordResource(Quote.getSobjectType(), 'GET', source.QuoteId);
        PlaceQuote.RecordWithReferenceRequest quoteRef =
            new PlaceQuote.RecordWithReferenceRequest('refQuote', quoteRecord);

        PlaceQuote.RecordResource qliRecord =
            new PlaceQuote.RecordResource(QuoteLineItem.getSobjectType(), 'POST');
        Map<String, Object> qliFields = new Map<String, Object>();
        qliFields.put('QuoteId', '@{refQuote.id}');
        qliFields.put('PricebookEntryId', source.PricebookEntryId);
        if (source.Product2Id != null) {
            qliFields.put('Product2Id', source.Product2Id);
        }
        qliFields.put('Quantity', source.Quantity);
        qliFields.put('UnitPrice', source.UnitPrice);
        if (source.Discount != null) {
            qliFields.put('Discount', source.Discount);
        }
        if (source.BillingFrequency != null) {
            qliFields.put('BillingFrequency', source.BillingFrequency);
        }
        if (String.isNotBlank(source.Description)) {
            qliFields.put('Description', source.Description);
        }
        qliRecord.fieldValues = qliFields;
        PlaceQuote.RecordWithReferenceRequest qliRef =
            new PlaceQuote.RecordWithReferenceRequest('refNewQLI', qliRecord);

        List<PlaceQuote.RecordWithReferenceRequest> records =
            new List<PlaceQuote.RecordWithReferenceRequest>();
        records.add(quoteRef);
        records.add(qliRef);

        // Clone children if bundle parent
        Integer childIdx = 0;
        for (QuoteLineItem child : children) {
            PlaceQuote.RecordResource childRecord =
                new PlaceQuote.RecordResource(QuoteLineItem.getSobjectType(), 'POST');
            Map<String, Object> childFields = new Map<String, Object>();
            childFields.put('QuoteId', '@{refQuote.id}');
            childFields.put('ParentQuoteLineItemId', '@{refNewQLI.id}');
            childFields.put('PricebookEntryId', child.PricebookEntryId);
            if (child.Product2Id != null) {
                childFields.put('Product2Id', child.Product2Id);
            }
            childFields.put('Quantity', child.Quantity);
            childFields.put('UnitPrice', child.UnitPrice);
            if (child.Discount != null) {
                childFields.put('Discount', child.Discount);
            }
            if (child.BillingFrequency != null) {
                childFields.put('BillingFrequency', child.BillingFrequency);
            }
            childRecord.fieldValues = childFields;
            records.add(new PlaceQuote.RecordWithReferenceRequest('refChild' + childIdx, childRecord));
            childIdx++;
        }

        PlaceQuote.GraphRequest graph = new PlaceQuote.GraphRequest('cloneLine', records);

        PlaceQuote.ConfigurationOptionsInput cInput = new PlaceQuote.ConfigurationOptionsInput();
        cInput.addDefaultConfiguration = true;
        cInput.executeConfigurationRules = true;
        cInput.validateAmendRenewCancel = false;
        cInput.validateProductCatalog = true;

        PlaceQuote.PlaceQuoteResponse resp =
            PlaceQuote.PlaceQuoteRLMApexProcessor.execute(
                PlaceQuote.PricingPreferenceEnum.System,
                graph,
                PlaceQuote.ConfigurationInputEnum.RunAndAllowErrors,
                cInput
            );

        if (resp == null || resp.success != true) {
            String errDetail = '';
            if (resp != null && resp.responseError != null) {
                List<String> msgs = new List<String>();
                for (ConnectApi.PlaceQuoteErrorResponse er : resp.responseError) {
                    msgs.add(er.message);
                }
                errDetail = String.join(msgs, '; ');
            }
            throw new AuraHandledException(
                'PlaceQuote clone failed' + (String.isNotBlank(errDetail) ? ': ' + errDetail : '.')
            );
        }
        return resp.quoteId;
    }

    private static Id cloneLineDirect(QuoteLineItem source) {
        if (!QuoteLineItem.SObjectType.getDescribe().isCreateable()) {
            throw new AuraHandledException('Insufficient access to create quote lines.');
        }
        QuoteLineItem newLine = new QuoteLineItem(
            QuoteId = source.QuoteId,
            PricebookEntryId = source.PricebookEntryId,
            Quantity = source.Quantity,
            UnitPrice = source.UnitPrice
        );
        if (source.Discount != null) {
            newLine.Discount = source.Discount;
        }
        if (source.BillingFrequency != null) {
            newLine.BillingFrequency = source.BillingFrequency;
        }
        if (String.isNotBlank(source.Description)) {
            newLine.Description = source.Description;
        }
        Database.insert(newLine, AccessLevel.USER_MODE);

        // DML clone only copies the root line, not children. ParentQuoteLineItemId
        // is not writeable via DML; only the PlaceQuote path supports bundle cloning.
        // Attribute cloning is handled by the caller (cloneQuoteLine).
        return newLine.Id;
    }

    // ─── Pricebook management ───────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<PricebookOption> getPricebooks() {
        List<PricebookOption> out = new List<PricebookOption>();
        for (Pricebook2 pb : [
            SELECT Id, Name FROM Pricebook2
            WHERE IsActive = true
            WITH SECURITY_ENFORCED
            ORDER BY Name LIMIT 200
        ]) {
            PricebookOption o = new PricebookOption();
            o.id = pb.Id;
            o.name = pb.Name;
            out.add(o);
        }
        return out;
    }

    @AuraEnabled
    public static void assignPricebook(Id quoteId, Id pricebook2Id) {
        if (quoteId == null || pricebook2Id == null) {
            throw new AuraHandledException('Quote Id and Pricebook Id are required.');
        }
        Quote q = new Quote(Id = quoteId, Pricebook2Id = pricebook2Id);
        Database.update(q, AccessLevel.USER_MODE);
    }

    // ─── Bundle & configurability enrichment for product cards ─────────────

    private static void enrichProductCardsWithBundleInfo(List<MobileProductCard> cards) {
        if (cards == null || cards.isEmpty()) return;

        Set<Id> productIds = new Set<Id>();
        for (MobileProductCard card : cards) {
            if (String.isNotBlank(card.product2Id)) {
                productIds.add((Id) card.product2Id);
            }
        }
        if (productIds.isEmpty()) return;

        // Query ProductRelatedComponent to find which products are bundle parents
        Map<Id, List<BundleChildInfo>> bundleMap = new Map<Id, List<BundleChildInfo>>();
        try {
            for (ProductRelatedComponent prc : [
                SELECT ParentProductId, ChildProductId,
                       ChildProduct.Name, ChildProduct.ProductCode
                FROM ProductRelatedComponent
                WHERE ParentProductId IN :productIds
                WITH SECURITY_ENFORCED
                ORDER BY ChildProduct.Name
            ]) {
                if (!bundleMap.containsKey(prc.ParentProductId)) {
                    bundleMap.put(prc.ParentProductId, new List<BundleChildInfo>());
                }
                BundleChildInfo child = new BundleChildInfo();
                child.product2Id = prc.ChildProductId;
                child.productName = prc.ChildProduct.Name;
                child.productCode = prc.ChildProduct.ProductCode;
                bundleMap.get(prc.ParentProductId).add(child);
            }
        } catch (Exception e) {
            // ProductRelatedComponent may not be accessible — non-fatal
        }

        // Resolve config flows for the products
        Map<Id, String> configFlowMap = resolveConfigFlowsByProduct(productIds);

        for (MobileProductCard card : cards) {
            if (String.isNotBlank(card.product2Id)) {
                Id pid = (Id) card.product2Id;
                List<BundleChildInfo> children = bundleMap.get(pid);
                card.isBundle = children != null && !children.isEmpty();
                card.bundleChildCount = card.isBundle == true ? children.size() : 0;
                card.bundleChildren = card.isBundle == true ? children : new List<BundleChildInfo>();
                card.isConfigurable = configFlowMap.containsKey(pid);
            } else {
                card.isBundle = false;
                card.bundleChildCount = 0;
                card.bundleChildren = new List<BundleChildInfo>();
                card.isConfigurable = false;
            }
        }
    }

    // ─── Add bundle to quote ─────────────────────────────────────────────────
    // PlaceQuote with addDefaultConfiguration=true automatically creates
    // the bundle parent AND its default child lines (from ProductRelatedComponent).
    // We only need to call addQuoteLineWithModel for the parent — PlaceQuote
    // handles the rest. No manual child creation is needed.

    @AuraEnabled
    public static Id addBundleToQuote(
        Id quoteId, String product2Id, String pricebookEntryId,
        Decimal unitPrice, Decimal quantity, String sellingModelId
    ) {
        if (quoteId == null || String.isBlank(pricebookEntryId) || String.isBlank(product2Id)) {
            throw new AuraHandledException('Quote Id, Product Id, and PricebookEntry Id are required.');
        }
        if (quantity == null || quantity <= 0) {
            quantity = 1;
        }

        // PlaceQuote creates the parent line and auto-adds default bundle
        // children when addDefaultConfiguration = true (set in addLineViaPlaceQuote).
        return addQuoteLineWithModel(
            quoteId, product2Id, pricebookEntryId,
            unitPrice, quantity, sellingModelId
        );
    }

    // ─── Configuration flow resolution ──────────────────────────────────────

    private static Map<Id, String> resolveConfigFlowsByProduct(Set<Id> productIds) {
        Map<Id, String> flowMap = new Map<Id, String>();
        if (productIds == null || productIds.isEmpty()) {
            return flowMap;
        }
        try {
            for (ProductConfigFlowAssignment pcfa : [
                SELECT ProductId, ProductClassificationId,
                       ProductConfigurationFlow.FlowIdentifier
                FROM ProductConfigFlowAssignment
                WHERE ProductId IN :productIds
                  AND ProductConfigurationFlow.Status = 'Active'
                ORDER BY ProductConfigurationFlow.IsDefault DESC
            ]) {
                if (pcfa.ProductId != null && !flowMap.containsKey(pcfa.ProductId)) {
                    flowMap.put(pcfa.ProductId, pcfa.ProductConfigurationFlow.FlowIdentifier);
                }
            }
            Set<Id> unmatchedIds = new Set<Id>();
            for (Id pid : productIds) {
                if (!flowMap.containsKey(pid)) {
                    unmatchedIds.add(pid);
                }
            }
            if (!unmatchedIds.isEmpty()) {
                Map<Id, Id> prodToClass = new Map<Id, Id>();
                String junctionSoql =
                    'SELECT ProductId, ProductClassificationId ' +
                    'FROM ProductClassificationProduct ' +
                    'WHERE ProductId IN :unmatchedIds';
                for (SObject sobj : Database.query(junctionSoql)) {
                    Id pid = (Id) sobj.get('ProductId');
                    Id cid = (Id) sobj.get('ProductClassificationId');
                    if (!prodToClass.containsKey(pid)) {
                        prodToClass.put(pid, cid);
                    }
                }
                if (!prodToClass.isEmpty()) {
                    Set<Id> classIds = new Set<Id>(prodToClass.values());
                    for (ProductConfigFlowAssignment pcfa : [
                        SELECT ProductClassificationId,
                               ProductConfigurationFlow.FlowIdentifier
                        FROM ProductConfigFlowAssignment
                        WHERE ProductClassificationId IN :classIds
                          AND ProductConfigurationFlow.Status = 'Active'
                        ORDER BY ProductConfigurationFlow.IsDefault DESC
                    ]) {
                        for (Id pid : prodToClass.keySet()) {
                            if (prodToClass.get(pid) == pcfa.ProductClassificationId
                                && !flowMap.containsKey(pid)) {
                                flowMap.put(pid, pcfa.ProductConfigurationFlow.FlowIdentifier);
                            }
                        }
                    }
                }
            }
        } catch (Exception e) {
            // ProductConfigFlowAssignment may not exist
        }
        return flowMap;
    }

    private static String resolveDefaultConfigFlowApiName() {
        try {
            List<ProductConfigurationFlow> rows = [
                SELECT FlowIdentifier
                FROM ProductConfigurationFlow
                WHERE Status = 'Active' AND IsDefault = true
                ORDER BY LastModifiedDate DESC LIMIT 1
            ];
            return rows.isEmpty() ? null : rows[0].FlowIdentifier;
        } catch (Exception e) {
            return null;
        }
    }

    // ─── Shared helpers ─────────────────────────────────────────────────────

    private static Quote queryQuote(Id quoteId) {
        Boolean isMulti = Schema.SObjectType.Quote.fields.getMap().containsKey('CurrencyIsoCode');
        List<String> qf = new List<String>{ 'Id', 'Pricebook2Id', 'OpportunityId' };
        if (isMulti) {
            qf.add('CurrencyIsoCode');
            qf.add('Opportunity.CurrencyIsoCode');
            qf.add('Opportunity.Account.CurrencyIsoCode');
        }
        String soql = 'SELECT ' + String.join(qf, ',') +
            ' FROM Quote WHERE Id = :quoteId WITH SECURITY_ENFORCED LIMIT 1';
        List<Quote> rows = (List<Quote>) Database.query(soql);
        if (rows.isEmpty()) {
            throw new AuraHandledException('Quote not found.');
        }
        return rows[0];
    }

    /**
     * Resolve the effective currency for product filtering.
     * Follows a resilient 6-step fallback chain:
     *   1. Quote.CurrencyIsoCode
     *   2. Opportunity.CurrencyIsoCode
     *   3. Account.CurrencyIsoCode (via Opportunity.Account)
     *   4. Running user's default currency (UserInfo.getDefaultCurrency)
     *   5. Org corporate (default) currency
     *   6. 'USD' as absolute last resort
     */
    private static String getQuoteCurrency(Quote q) {
        if (!Schema.SObjectType.Quote.fields.getMap().containsKey('CurrencyIsoCode')) {
            return null;
        }

        // 1. Quote's own currency
        String curr = (String) q.get('CurrencyIsoCode');
        if (String.isNotBlank(curr)) {
            return curr;
        }

        // 2. Opportunity currency
        try {
            SObject opp = q.getSObject('Opportunity');
            if (opp != null) {
                curr = (String) opp.get('CurrencyIsoCode');
                if (String.isNotBlank(curr)) {
                    return curr;
                }
                // 3. Account currency (via Opportunity.Account)
                SObject acct = opp.getSObject('Account');
                if (acct != null) {
                    curr = (String) acct.get('CurrencyIsoCode');
                    if (String.isNotBlank(curr)) {
                        return curr;
                    }
                }
            }
        } catch (Exception e) {
            // Relationship traversal failed — continue to next fallback
        }

        // 4. Running user's default currency
        try {
            curr = UserInfo.getDefaultCurrency();
            if (String.isNotBlank(curr)) {
                return curr;
            }
        } catch (Exception e) {
            // UserInfo call failed — continue to next fallback
        }

        // 5. Org corporate (default) currency
        curr = getOrgDefaultCurrency();
        if (String.isNotBlank(curr)) {
            return curr;
        }

        // 6. Absolute last resort
        return 'USD';
    }

    private static String orgDefaultCurrencyCache;
    private static Boolean orgDefaultCurrencyLoaded = false;

    private static String getOrgDefaultCurrency() {
        if (orgDefaultCurrencyLoaded) {
            return orgDefaultCurrencyCache;
        }
        orgDefaultCurrencyLoaded = true;
        try {
            List<SObject> rows = Database.query(
                'SELECT IsoCode FROM CurrencyType WHERE IsCorporate = true AND IsActive = true LIMIT 1'
            );
            orgDefaultCurrencyCache = rows.isEmpty() ? null : (String) rows[0].get('IsoCode');
        } catch (Exception e) {
            orgDefaultCurrencyCache = null;
        }
        return orgDefaultCurrencyCache;
    }

    private static String deriveBillingFrequency(PricebookEntry pbe, String product2Id, String sellingModelId) {
        String pricingTermUnit = null;
        try {
            // First try from the explicitly selected selling model
            if (String.isNotBlank(sellingModelId)) {
                Id psmId = (Id) sellingModelId;
                List<ProductSellingModel> psmRows = [
                    SELECT PricingTermUnit FROM ProductSellingModel WHERE Id = :psmId LIMIT 1
                ];
                if (!psmRows.isEmpty()) {
                    pricingTermUnit = psmRows[0].PricingTermUnit;
                }
            }
            // Then from PBE
            if (String.isBlank(pricingTermUnit) &&
                Schema.SObjectType.PricebookEntry.fields.getMap().containsKey('ProductSellingModelId')) {
                Id psmId = (Id) pbe.get('ProductSellingModelId');
                if (psmId != null) {
                    List<ProductSellingModel> psmRows = [
                        SELECT PricingTermUnit FROM ProductSellingModel WHERE Id = :psmId LIMIT 1
                    ];
                    if (!psmRows.isEmpty()) {
                        pricingTermUnit = psmRows[0].PricingTermUnit;
                    }
                }
            }
            // Then from Product2
            if (String.isBlank(pricingTermUnit) &&
                Schema.SObjectType.Product2.fields.getMap().containsKey('ProductSellingModelId') &&
                product2Id != null) {
                Id pid = (Id) product2Id;
                String p2Soql = 'SELECT ProductSellingModelId FROM Product2 WHERE Id = :pid LIMIT 1';
                List<SObject> products = Database.query(p2Soql);
                if (!products.isEmpty()) {
                    Id psmIdFromProduct = (Id) products[0].get('ProductSellingModelId');
                    if (psmIdFromProduct != null) {
                        List<ProductSellingModel> psmRowsFromProduct = [
                            SELECT PricingTermUnit FROM ProductSellingModel
                            WHERE Id = :psmIdFromProduct LIMIT 1
                        ];
                        if (!psmRowsFromProduct.isEmpty()) {
                            pricingTermUnit = psmRowsFromProduct[0].PricingTermUnit;
                        }
                    }
                }
            }
        } catch (Exception ex) {
            // non-fatal
        }
        return mapPricingTermUnitToBillingFrequency(pricingTermUnit);
    }

    private static String mapPricingTermUnitToBillingFrequency(String pricingTermUnit) {
        if (String.isBlank(pricingTermUnit)) {
            return null;
        }
        String key = pricingTermUnit.trim().toLowerCase();
        if (key == 'month' || key == 'months') return 'Monthly';
        if (key == 'quarter' || key == 'quarters' || key == 'quarterly') return 'Quarterly';
        if (key == 'year' || key == 'years' || key == 'annual' || key == 'annually') return 'Annual';
        if (key == 'semi-annual' || key == 'semi annual' || key == 'semiannually') return 'Semi-Annual';
        return pricingTermUnit;
    }

    // ─── Product Data Translation helper ───────────────────────────────

    /**
     * Queries Product2DataTranslation for the running user's language.
     * Returns a map of Product2Id → ProductTranslation (name + description).
     * Falls back gracefully if the object doesn't exist or no translations are found.
     */
    private static Map<Id, ProductTranslation> getTranslationMap(Set<Id> productIds) {
        Map<Id, ProductTranslation> result = new Map<Id, ProductTranslation>();
        if (productIds == null || productIds.isEmpty()) {
            return result;
        }
        try {
            String userLang = UserInfo.getLanguage(); // e.g. 'es', 'en_US', 'pt_BR'
            for (Product2DataTranslation pdt : [
                SELECT ParentId, Name, Description
                FROM Product2DataTranslation
                WHERE ParentId IN :productIds
                  AND Language = :userLang
                WITH SECURITY_ENFORCED
            ]) {
                ProductTranslation pt = new ProductTranslation();
                pt.name = pdt.Name;
                pt.description = pdt.Description;
                result.put(pdt.ParentId, pt);
            }
        } catch (Exception e) {
            // Product2DataTranslation may not exist or be inaccessible — non-fatal
        }
        return result;
    }

    /**
     * Applies translations from Product2DataTranslation to a list of MobileProductCards.
     * Called after product cards are built, overriding productName and productDescription
     * with the translated values for the running user's language.
     */
    private static void applyTranslationsToProductCards(List<MobileProductCard> cards) {
        if (cards == null || cards.isEmpty()) return;
        Set<Id> productIds = new Set<Id>();
        for (MobileProductCard card : cards) {
            if (String.isNotBlank(card.product2Id)) {
                productIds.add((Id) card.product2Id);
            }
            // Also collect child product IDs for bundle children
            if (card.bundleChildren != null) {
                for (BundleChildInfo child : card.bundleChildren) {
                    if (String.isNotBlank(child.product2Id)) {
                        productIds.add((Id) child.product2Id);
                    }
                }
            }
        }
        if (productIds.isEmpty()) return;

        Map<Id, ProductTranslation> txMap = getTranslationMap(productIds);
        if (txMap.isEmpty()) return;

        for (MobileProductCard card : cards) {
            if (String.isNotBlank(card.product2Id)) {
                ProductTranslation tx = txMap.get((Id) card.product2Id);
                if (tx != null) {
                    if (String.isNotBlank(tx.name)) {
                        card.productName = tx.name;
                    }
                    card.productDescription = tx.description;
                }
            }
            // Translate bundle children names
            if (card.bundleChildren != null) {
                for (BundleChildInfo child : card.bundleChildren) {
                    if (String.isNotBlank(child.product2Id)) {
                        ProductTranslation childTx = txMap.get((Id) child.product2Id);
                        if (childTx != null) {
                            if (String.isNotBlank(childTx.name)) {
                                child.productName = childTx.name;
                            }
                            child.productDescription = childTx.description;
                        }
                    }
                }
            }
        }
    }

    private static String buildDmlMessage(DmlException e) {
        String msg = e.getMessage();
        if (e.getNumDml() > 0 && !e.getDmlFields(0).isEmpty()) {
            msg += ' — ' + String.join(e.getDmlFields(0), ', ');
        }
        return msg;
    }

    private static String firstErrorMessage(Exception e) {
        if (e == null) return 'unknown';
        return String.isNotBlank(e.getMessage()) ? e.getMessage() : e.getTypeName();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ─── Bundle Configurator ─────────────────────────────────────────────────
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * Load the full bundle configuration state for a given QuoteLineItem.
     * Joins catalog data (ProductComponentGroup, ProductRelatedComponent) with
     * the current quote state (child QuoteLineItems, QuoteLineItemAttributes).
     * Supports up to 3 levels of bundle nesting.
     */
    @AuraEnabled
    public static BundleConfigState loadBundleConfiguration(Id quoteId, Id quoteLineItemId) {
        if (quoteId == null || quoteLineItemId == null) {
            throw new AuraHandledException('Quote Id and QuoteLineItem Id are required.');
        }

        // 1. Query the parent QuoteLineItem
        QuoteLineItem parentQli = [
            SELECT Id, Product2Id, Product2.Name, Quantity, UnitPrice
            FROM QuoteLineItem
            WHERE Id = :quoteLineItemId AND QuoteId = :quoteId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        // Query the Quote for currency resolution (includes CurrencyIsoCode in multi-currency orgs)
        Quote q = queryQuote(quoteId);

        BundleConfigState state = new BundleConfigState();
        state.quoteLineItemId = parentQli.Id;
        state.product2Id = parentQli.Product2Id;
        state.productName = parentQli.Product2.Name;
        state.quantity = parentQli.Quantity;
        state.unitPrice = parentQli.UnitPrice;
        state.currencyIsoCode = getQuoteCurrency(q);
        state.attributes = new List<ConfigAttribute>();

        // 2. Load groups and options from catalog (recursive, up to 3 levels)
        state.groups = loadConfigGroupsForProduct(
            parentQli.Product2Id, quoteId, quoteLineItemId, 0
        );

        return state;
    }

    /**
     * Recursive helper: load ProductComponentGroups and ProductRelatedComponents
     * for a given parent product, and merge with existing child QuoteLineItems.
     * @param nestingLevel — 0-based; stops recursion at level 3
     */
    private static List<ConfigGroup> loadConfigGroupsForProduct(
        Id parentProduct2Id, Id quoteId, Id parentQuoteLineItemId, Integer nestingLevel
    ) {
        if (nestingLevel > 2) return new List<ConfigGroup>(); // max 3 levels (0, 1, 2)

        // 2a. Query component groups
        List<ProductComponentGroup> pcgRows = [
            SELECT Id, Name, MinBundleComponents, MaxBundleComponents, Sequence
            FROM ProductComponentGroup
            WHERE ParentProductId = :parentProduct2Id
            WITH SECURITY_ENFORCED
            ORDER BY Sequence NULLS LAST, Name
        ];
        if (pcgRows.isEmpty()) return new List<ConfigGroup>();

        Set<Id> groupIds = new Set<Id>();
        for (ProductComponentGroup pcg : pcgRows) {
            groupIds.add(pcg.Id);
        }

        // 2b. Query related components for all groups
        List<ProductRelatedComponent> prcRows = [
            SELECT Id, ChildProductId, ChildProduct.Name, ChildProduct.ProductCode,
                   ProductComponentGroupId, IsDefaultComponent, IsComponentRequired,
                   MinQuantity, MaxQuantity, Quantity, IsQuantityEditable, Sequence
            FROM ProductRelatedComponent
            WHERE ParentProductId = :parentProduct2Id
              AND ProductComponentGroupId IN :groupIds
            WITH SECURITY_ENFORCED
            ORDER BY Sequence NULLS LAST, ChildProduct.Name
        ];

        // Collect child product IDs for PricebookEntry resolution
        Set<Id> childProductIds = new Set<Id>();
        for (ProductRelatedComponent prc : prcRows) {
            childProductIds.add(prc.ChildProductId);
        }

        // 2c. Resolve PricebookEntries for child products
        Map<Id, PricebookEntry> pbeMap = getChildPricebookEntries(quoteId, childProductIds);

        // 2d. Query existing child QuoteLineItems under the parent line
        Map<Id, QuoteLineItem> existingChildByProduct = new Map<Id, QuoteLineItem>();
        Map<Id, Id> childLineToProduct = new Map<Id, Id>();
        if (parentQuoteLineItemId != null) {
            for (QuoteLineItem childQli : [
                SELECT Id, Product2Id, Quantity, UnitPrice, TotalPrice
                FROM QuoteLineItem
                WHERE ParentQuoteLineItemId = :parentQuoteLineItemId
                  AND QuoteId = :quoteId
                WITH SECURITY_ENFORCED
            ]) {
                existingChildByProduct.put(childQli.Product2Id, childQli);
                childLineToProduct.put(childQli.Id, childQli.Product2Id);
            }
        }

        // 2e. Query QuoteLineItemAttribute for existing child lines
        Map<Id, List<QuoteLineItemAttribute>> attrsByLineId = new Map<Id, List<QuoteLineItemAttribute>>();
        if (!existingChildByProduct.isEmpty()) {
            Set<Id> childLineIds = existingChildByProduct.values() != null
                ? new Set<Id>()
                : new Set<Id>();
            for (QuoteLineItem cqli : existingChildByProduct.values()) {
                childLineIds.add(cqli.Id);
            }
            try {
                for (QuoteLineItemAttribute qlia : [
                    SELECT Id, QuoteLineItemId, AttributeDefinitionId,
                           AttributeDefinition.Name, AttributeDefinition.DataType,
                           AttributeValue, AttributePicklistValueId
                    FROM QuoteLineItemAttribute
                    WHERE QuoteLineItemId IN :childLineIds
                    WITH SECURITY_ENFORCED
                ]) {
                    if (!attrsByLineId.containsKey(qlia.QuoteLineItemId)) {
                        attrsByLineId.put(qlia.QuoteLineItemId, new List<QuoteLineItemAttribute>());
                    }
                    attrsByLineId.get(qlia.QuoteLineItemId).add(qlia);
                }
            } catch (Exception e) {
                // QuoteLineItemAttribute may not be queryable — non-fatal
            }
        }

        // 2f. Detect which child products are themselves bundle parents (nested bundles)
        Set<Id> nestedBundleProductIds = new Set<Id>();
        try {
            for (ProductComponentGroup nestedPcg : [
                SELECT ParentProductId
                FROM ProductComponentGroup
                WHERE ParentProductId IN :childProductIds
                WITH SECURITY_ENFORCED
            ]) {
                nestedBundleProductIds.add(nestedPcg.ParentProductId);
            }
        } catch (Exception e) {
            // non-fatal
        }

        // 2g. Build ConfigGroup + ConfigOption structures
        Map<Id, ConfigGroup> groupMap = new Map<Id, ConfigGroup>();
        List<ConfigGroup> orderedGroups = new List<ConfigGroup>();

        for (ProductComponentGroup pcg : pcgRows) {
            ConfigGroup cg = new ConfigGroup();
            cg.groupId = pcg.Id;
            cg.groupName = pcg.Name;
            cg.minSelections = pcg.MinBundleComponents;
            cg.maxSelections = pcg.MaxBundleComponents;
            cg.sequence = pcg.Sequence;
            cg.options = new List<ConfigOption>();
            groupMap.put(pcg.Id, cg);
            orderedGroups.add(cg);
        }

        for (ProductRelatedComponent prc : prcRows) {
            ConfigGroup parentGroup = groupMap.get(prc.ProductComponentGroupId);
            if (parentGroup == null) continue;

            ConfigOption opt = new ConfigOption();
            opt.productRelatedComponentId = prc.Id;
            opt.childProduct2Id = prc.ChildProductId;
            opt.childProductName = prc.ChildProduct.Name;
            opt.childProductCode = prc.ChildProduct.ProductCode;
            opt.isDefault = prc.IsDefaultComponent;
            opt.isRequired = prc.IsComponentRequired;
            opt.minQuantity = prc.MinQuantity;
            opt.maxQuantity = prc.MaxQuantity;
            opt.defaultQuantity = prc.Quantity;
            opt.isQuantityEditable = prc.IsQuantityEditable;
            opt.sequence = prc.Sequence;
            opt.attributes = new List<ConfigAttribute>();

            // PricebookEntry
            PricebookEntry pbe = pbeMap.get(prc.ChildProductId);
            if (pbe != null) {
                opt.pricebookEntryId = pbe.Id;
                opt.currentUnitPrice = pbe.UnitPrice;
            }

            // Merge with existing child QLI
            QuoteLineItem existingChild = existingChildByProduct.get(prc.ChildProductId);
            if (existingChild != null) {
                opt.quoteLineItemId = existingChild.Id;
                opt.isSelected = true;
                opt.currentQuantity = existingChild.Quantity;
                opt.currentUnitPrice = existingChild.UnitPrice;

                // Attributes from QuoteLineItemAttribute
                List<QuoteLineItemAttribute> qlias = attrsByLineId.get(existingChild.Id);
                if (qlias != null) {
                    for (QuoteLineItemAttribute qlia : qlias) {
                        ConfigAttribute ca = new ConfigAttribute();
                        ca.attributeDefinitionId = qlia.AttributeDefinitionId;
                        ca.attributeName = qlia.AttributeDefinition?.Name;
                        ca.dataType = qlia.AttributeDefinition?.DataType;
                        ca.currentValue = qlia.AttributeValue;
                        ca.quoteLineItemAttributeId = qlia.Id;
                        ca.isRequired = false;
                        ca.picklistValues = new List<AttributePicklistOption>();
                        opt.attributes.add(ca);
                    }
                }
            } else {
                opt.isSelected = prc.IsDefaultComponent && prc.IsComponentRequired;
                opt.currentQuantity = prc.Quantity;
            }

            // Nested bundle detection + recursive load
            opt.isNestedBundle = nestedBundleProductIds.contains(prc.ChildProductId);
            if (opt.isNestedBundle && opt.isSelected && existingChild != null) {
                opt.childGroups = loadConfigGroupsForProduct(
                    prc.ChildProductId, quoteId, existingChild.Id, nestingLevel + 1
                );
            } else if (opt.isNestedBundle) {
                // Load catalog structure but without quote state
                opt.childGroups = loadConfigGroupsForProduct(
                    prc.ChildProductId, quoteId, null, nestingLevel + 1
                );
            } else {
                opt.childGroups = new List<ConfigGroup>();
            }

            parentGroup.options.add(opt);
        }

        return orderedGroups;
    }

    /**
     * Save bundle configuration changes via PlaceQuote API.
     * Processes ADD, REMOVE, UPDATE actions for child QuoteLineItems.
     * Handles QuoteLineItemAttribute DML separately after PlaceQuote.
     */
    @AuraEnabled
    public static BundleConfigState saveBundleConfiguration(
        Id quoteId, Id parentLineId, String configJson
    ) {
        if (quoteId == null || parentLineId == null || String.isBlank(configJson)) {
            throw new AuraHandledException('Quote Id, parent line Id, and configuration are required.');
        }

        List<ConfigChange> changes = (List<ConfigChange>) JSON.deserialize(
            configJson, List<ConfigChange>.class
        );

        if (changes.isEmpty()) {
            // No changes — just reload and return
            return loadBundleConfiguration(quoteId, parentLineId);
        }

        // Separate actions
        List<ConfigChange> removes = new List<ConfigChange>();
        List<ConfigChange> adds = new List<ConfigChange>();
        List<ConfigChange> updates = new List<ConfigChange>();
        for (ConfigChange c : changes) {
            if (c.action == 'REMOVE') removes.add(c);
            else if (c.action == 'ADD') adds.add(c);
            else if (c.action == 'UPDATE') updates.add(c);
        }

        // Step 1: DELETE removed lines via DML (PlaceQuote may not support DELETE method)
        if (!removes.isEmpty()) {
            List<Id> removeIds = new List<Id>();
            for (ConfigChange r : removes) {
                if (String.isNotBlank(r.quoteLineItemId)) {
                    removeIds.add(r.quoteLineItemId);
                }
            }
            if (!removeIds.isEmpty()) {
                // Delete attributes first (cascade)
                try {
                    delete [SELECT Id FROM QuoteLineItemAttribute WHERE QuoteLineItemId IN :removeIds];
                } catch (Exception e) { /* non-fatal */ }
                // Delete the QuoteLineItems
                delete [SELECT Id FROM QuoteLineItem WHERE Id IN :removeIds AND QuoteId = :quoteId];
            }
        }

        // Step 2: ADD new child lines via PlaceQuote (without ParentQuoteLineItemId,
        //         which is system-managed and cannot be written by user code) and
        //         UPDATE existing child lines for quantity/price changes.
        //
        //         After PlaceQuote creates the standalone children, we insert
        //         QuoteLineRelationship records via DML to establish the bundle
        //         parent-child link.  The platform auto-populates
        //         ParentQuoteLineItemId when a QuoteLineRelationship exists.

        // Snapshot existing orphan QLI IDs so we can identify newly-created ones
        Set<Id> preExistingLineIds = new Set<Id>();
        if (!adds.isEmpty()) {
            for (QuoteLineItem ql : [
                SELECT Id FROM QuoteLineItem WHERE QuoteId = :quoteId
            ]) {
                preExistingLineIds.add(ql.Id);
            }
        }

        // Build a map of Product2Id → ProductRelatedComponentId for new children
        // (needed when creating QuoteLineRelationship records)
        Map<String, Id> product2ToCompIdMap = new Map<String, Id>();
        if (!adds.isEmpty()) {
            Set<String> addProduct2Ids = new Set<String>();
            for (ConfigChange a : adds) {
                if (String.isNotBlank(a.childProduct2Id)) {
                    addProduct2Ids.add(a.childProduct2Id);
                }
            }
            // Look up the parent product from the parent QLI
            QuoteLineItem parentQli = [
                SELECT Id, Product2Id FROM QuoteLineItem
                WHERE Id = :parentLineId AND QuoteId = :quoteId
                LIMIT 1
            ];
            if (parentQli.Product2Id != null && !addProduct2Ids.isEmpty()) {
                for (ProductRelatedComponent prc : [
                    SELECT Id, ChildProductId
                    FROM ProductRelatedComponent
                    WHERE ParentProductId = :parentQli.Product2Id
                      AND ChildProductId IN :addProduct2Ids
                ]) {
                    product2ToCompIdMap.put(prc.ChildProductId, prc.Id);
                }
            }
        }

        // Look up the "Bundle to Bundle Component" ProductRelationshipType
        Id bundleRelTypeId;
        if (!adds.isEmpty()) {
            List<ProductRelationshipType> relTypes = [
                SELECT Id FROM ProductRelationshipType
                WHERE Name = 'Bundle to Bundle Component Relationship'
                LIMIT 1
            ];
            if (!relTypes.isEmpty()) {
                bundleRelTypeId = relTypes[0].Id;
            }
        }

        if (!adds.isEmpty() || !updates.isEmpty()) {
            List<PlaceQuote.RecordWithReferenceRequest> records =
                new List<PlaceQuote.RecordWithReferenceRequest>();

            // Quote reference — PATCH existing
            PlaceQuote.RecordResource quoteRecord =
                new PlaceQuote.RecordResource(Quote.getSobjectType(), 'PATCH', quoteId);
            records.add(new PlaceQuote.RecordWithReferenceRequest('refQuote', quoteRecord));

            Integer refIdx = 0;

            // POST new child lines WITHOUT ParentQuoteLineItemId
            for (ConfigChange a : adds) {
                PlaceQuote.RecordResource childRec =
                    new PlaceQuote.RecordResource(QuoteLineItem.getSobjectType(), 'POST');
                Map<String, Object> childFields = new Map<String, Object>();
                childFields.put('QuoteId', '@{refQuote.id}');
                // ParentQuoteLineItemId intentionally omitted — system-managed field.
                // Bundle link established via QuoteLineRelationship in Step 2b.
                if (String.isNotBlank(a.pricebookEntryId)) {
                    childFields.put('PricebookEntryId', a.pricebookEntryId);
                }
                if (String.isNotBlank(a.childProduct2Id)) {
                    childFields.put('Product2Id', a.childProduct2Id);
                }
                childFields.put('Quantity', a.quantity != null ? a.quantity : 1);
                if (a.unitPrice != null) {
                    childFields.put('UnitPrice', a.unitPrice);
                }
                childRec.fieldValues = childFields;
                records.add(new PlaceQuote.RecordWithReferenceRequest(
                    'refAdd' + refIdx++, childRec
                ));
            }

            // PATCH existing child lines (quantity/price changes)
            for (ConfigChange u : updates) {
                if (String.isBlank(u.quoteLineItemId)) continue;
                PlaceQuote.RecordResource qliRec = new PlaceQuote.RecordResource(
                    QuoteLineItem.getSobjectType(), 'PATCH', Id.valueOf(u.quoteLineItemId)
                );
                Map<String, Object> fields = new Map<String, Object>();
                if (u.quantity != null) {
                    fields.put('Quantity', u.quantity);
                }
                if (u.unitPrice != null) {
                    fields.put('UnitPrice', u.unitPrice);
                }
                qliRec.fieldValues = fields;
                records.add(new PlaceQuote.RecordWithReferenceRequest(
                    'refUpd' + refIdx++, qliRec
                ));
            }

            PlaceQuote.ConfigurationOptionsInput cInput = new PlaceQuote.ConfigurationOptionsInput();
            cInput.addDefaultConfiguration = false;
            cInput.executeConfigurationRules = true;
            cInput.validateAmendRenewCancel = false;
            cInput.validateProductCatalog = true;

            PlaceQuote.GraphRequest graph = new PlaceQuote.GraphRequest('configBundle', records);

            PlaceQuote.PlaceQuoteResponse resp =
                PlaceQuote.PlaceQuoteRLMApexProcessor.execute(
                    PlaceQuote.PricingPreferenceEnum.System,
                    graph,
                    PlaceQuote.ConfigurationInputEnum.RunAndAllowErrors,
                    cInput
                );

            if (resp == null || resp.success != true) {
                String errDetail = '';
                if (resp != null && resp.responseError != null) {
                    List<String> msgs = new List<String>();
                    for (ConnectApi.PlaceQuoteErrorResponse er : resp.responseError) {
                        msgs.add(er.message);
                    }
                    errDetail = String.join(msgs, '; ');
                }
                throw new AuraHandledException(
                    'Configuration save failed' + (String.isNotBlank(errDetail) ? ': ' + errDetail : '.')
                );
            }
        }

        // Step 2b: Ensure QuoteLineRelationship records exist for newly-added children.
        //          PlaceQuote may auto-create these via executeConfigurationRules;
        //          only insert if missing to avoid "bundle component already exists" errors.
        if (!adds.isEmpty() && bundleRelTypeId != null) {
            // Find newly created QLIs (IDs not in the pre-existing snapshot)
            List<QuoteLineItem> newLines = [
                SELECT Id, Product2Id, ParentQuoteLineItemId FROM QuoteLineItem
                WHERE QuoteId = :quoteId
                  AND Id NOT IN :preExistingLineIds
            ];

            // Check which new lines already have a QuoteLineRelationship
            Set<Id> newLineIds = new Set<Id>();
            for (QuoteLineItem nl : newLines) {
                newLineIds.add(nl.Id);
            }
            Set<Id> alreadyLinkedIds = new Set<Id>();
            for (QuoteLineRelationship existingRel : [
                SELECT AssociatedQuoteLineId FROM QuoteLineRelationship
                WHERE AssociatedQuoteLineId IN :newLineIds
            ]) {
                alreadyLinkedIds.add(existingRel.AssociatedQuoteLineId);
            }

            // Only create relationships for lines that don't have one yet
            List<QuoteLineRelationship> newRels = new List<QuoteLineRelationship>();
            for (QuoteLineItem nl : newLines) {
                if (alreadyLinkedIds.contains(nl.Id)) continue;
                QuoteLineRelationship rel = new QuoteLineRelationship();
                rel.MainQuoteLineId = parentLineId;
                rel.AssociatedQuoteLineId = nl.Id;
                rel.ProductRelationshipTypeId = bundleRelTypeId;
                rel.AssociatedQuoteLinePricing = 'IncludedInBundlePrice';
                if (nl.Product2Id != null && product2ToCompIdMap.containsKey(nl.Product2Id)) {
                    rel.ProductRelatedComponentId = product2ToCompIdMap.get(nl.Product2Id);
                }
                newRels.add(rel);
            }
            if (!newRels.isEmpty()) {
                insert newRels;
            }
        }

        // Step 3: Handle QuoteLineItemAttribute changes via DML
        // (for both new and updated lines)
        List<QuoteLineItemAttribute> attrsToUpsert = new List<QuoteLineItemAttribute>();
        for (ConfigChange c : changes) {
            if (c.attributes == null || c.attributes.isEmpty()) continue;
            if (String.isBlank(c.quoteLineItemId) && c.action != 'ADD') continue;

            // For ADDs, we need to re-query to find the newly created QLI
            Id targetLineId;
            if (c.action == 'ADD' && String.isNotBlank(c.childProduct2Id)) {
                try {
                    List<QuoteLineItem> newLines = [
                        SELECT Id FROM QuoteLineItem
                        WHERE ParentQuoteLineItemId = :parentLineId
                          AND Product2Id = :c.childProduct2Id
                          AND QuoteId = :quoteId
                        ORDER BY CreatedDate DESC LIMIT 1
                    ];
                    if (!newLines.isEmpty()) {
                        targetLineId = newLines[0].Id;
                    }
                } catch (Exception e) { continue; }
            } else {
                targetLineId = Id.valueOf(c.quoteLineItemId);
            }
            if (targetLineId == null) continue;

            for (AttributeChange ac : c.attributes) {
                QuoteLineItemAttribute qlia = new QuoteLineItemAttribute();
                qlia.QuoteLineItemId = targetLineId;
                qlia.AttributeDefinitionId = Id.valueOf(ac.attributeDefinitionId);
                qlia.AttributeValue = ac.value;
                if (String.isNotBlank(ac.picklistValueId)) {
                    qlia.AttributePicklistValueId = Id.valueOf(ac.picklistValueId);
                }
                attrsToUpsert.add(qlia);
            }
        }
        if (!attrsToUpsert.isEmpty()) {
            try {
                upsert attrsToUpsert;
            } catch (Exception e) {
                // Non-fatal — log but don't fail the whole operation
                System.debug(LoggingLevel.WARN, 'Attribute upsert error: ' + e.getMessage());
            }
        }

        // Reload and return the updated state
        return loadBundleConfiguration(quoteId, parentLineId);
    }

    /**
     * Resolve PricebookEntries for a set of product IDs using the quote's pricebook.
     */
    private static Map<Id, PricebookEntry> getChildPricebookEntries(Id quoteId, Set<Id> productIds) {
        Map<Id, PricebookEntry> result = new Map<Id, PricebookEntry>();
        if (productIds == null || productIds.isEmpty()) return result;
        try {
            Quote q = [SELECT Pricebook2Id FROM Quote WHERE Id = :quoteId WITH SECURITY_ENFORCED LIMIT 1];
            if (q.Pricebook2Id == null) return result;
            for (PricebookEntry pbe : [
                SELECT Id, Product2Id, UnitPrice
                FROM PricebookEntry
                WHERE Pricebook2Id = :q.Pricebook2Id
                  AND Product2Id IN :productIds
                  AND IsActive = true
                WITH SECURITY_ENFORCED
            ]) {
                result.put(pbe.Product2Id, pbe);
            }
        } catch (Exception e) {
            // non-fatal
        }
        return result;
    }

}