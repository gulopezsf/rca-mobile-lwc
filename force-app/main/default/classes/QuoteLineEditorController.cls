/**
 * API para el LWC quoteLineBundleEditor.
 *
 * Integra las Product Discovery Standard Invocable Actions de RCA
 * (getCatalogs, getCategories, findProducts, getProducts) y
 * PlaceQuote.PlaceQuoteRLMApexProcessor para añadir líneas al presupuesto.
 *
 * En contexto de test se utiliza un fallback directo (SOQL/DML) porque las
 * Invocable Actions y PlaceQuote requieren Product Discovery configurado.
 */
public with sharing class QuoteLineEditorController {
    private static final String DEFAULT_FIELD_SET = 'Quote_Line_Editor_Columns';
    private static final String TARGET_PRODUCT_CATALOG_NAME = 'Alarmas Negocios y PYMES';
    private static final String TARGET_PRODUCT_CATEGORY_NAME = 'Paquetes Alarmas';

    @TestVisible
    private static Boolean USE_SOQL_FALLBACK = Test.isRunningTest();

    // ─── DTOs ────────────────────────────────────────────────────────────────

    public class LineRow {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public Id parentQuoteLineItemId { get; set; }
        @AuraEnabled public Map<String, Object> fieldValues { get; set; }
        @AuraEnabled public Boolean isBundleParent { get; set; }
        @AuraEnabled public Boolean isConfigurable { get; set; }
        @AuraEnabled public String configFlowApiName { get; set; }
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

    public class ProductSearchResult {
        @AuraEnabled public String pricebookEntryId { get; set; }
        @AuraEnabled public String product2Id { get; set; }
        @AuraEnabled public String productName { get; set; }
        @AuraEnabled public String productCode { get; set; }
        @AuraEnabled public Decimal unitPrice { get; set; }
        @AuraEnabled public String currencyIsoCode { get; set; }
        @AuraEnabled public String sellingModelName { get; set; }
    }

    // ─── Field-set columns ───────────────────────────────────────────────────

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
            Schema.DescribeFieldResult nameDfr = productNameField.getDescribe();
            ColumnDefinition nameCol = new ColumnDefinition();
            nameCol.apiName = 'ProductName';
            nameCol.label = nameDfr.getLabel();
            nameCol.type = String.valueOf(nameDfr.getType());
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

    // ─── Lines (read / delete / update) ──────────────────────────────────────

    @AuraEnabled
    public static List<LineRow> getLines(Id quoteId, String fieldSetName) {
        if (quoteId == null) {
            throw new AuraHandledException('Quote Id is required.');
        }
        String fsName = String.isNotBlank(fieldSetName) ? fieldSetName : DEFAULT_FIELD_SET;
        Schema.FieldSet fs = Schema.SObjectType.QuoteLineItem.FieldSets.getMap().get(fsName);
        if (fs == null) {
            throw new AuraHandledException('Field set not found: ' + fsName);
        }
        Set<String> fieldNames = new Set<String>{ 'Id', 'QuoteId', 'ParentQuoteLineItemId', 'Product2Id' };
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
        String soql =
            'SELECT ' + String.join(ordered, ',') +
            ' FROM QuoteLineItem WHERE QuoteId = :quoteId ORDER BY LineNumber NULLS LAST, CreatedDate';
        List<QuoteLineItem> rows;
        try {
            rows = Database.query(soql);
        } catch (Exception e) {
            throw new AuraHandledException('Query failed: ' + e.getMessage());
        }
        Set<Id> parentLineIds = new Set<Id>();
        Set<Id> productIds = new Set<Id>();
        for (QuoteLineItem qli : rows) {
            if (qli.ParentQuoteLineItemId != null) {
                parentLineIds.add(qli.ParentQuoteLineItemId);
            }
            if (qli.Product2Id != null) {
                productIds.add(qli.Product2Id);
            }
        }
        Map<Id, String> configFlowMap = resolveConfigFlowsByProduct(productIds);
        String defaultFlowApi = resolveDefaultConfigFlowApiName();

        List<LineRow> outRows = new List<LineRow>();
        for (QuoteLineItem qli : rows) {
            LineRow lr = new LineRow();
            lr.id = qli.Id;
            lr.parentQuoteLineItemId = qli.ParentQuoteLineItemId;
            lr.isBundleParent = parentLineIds.contains(qli.Id);
            String flowApi = qli.Product2Id != null ? configFlowMap.get(qli.Product2Id) : null;
            if (String.isBlank(flowApi) && lr.isBundleParent && String.isNotBlank(defaultFlowApi)) {
                flowApi = defaultFlowApi;
            }
            lr.isConfigurable = String.isNotBlank(flowApi);
            lr.configFlowApiName = flowApi;
            lr.fieldValues = new Map<String, Object>();
            for (String fn : fieldNames) {
                if (fn == 'Id' || fn == 'ParentQuoteLineItemId' || fn == 'QuoteId' || fn == 'Product2Id') {
                    continue;
                }
                lr.fieldValues.put(fn, qli.get(fn));
            }
            SObject p2 = qli.getSObject('Product2');
            lr.fieldValues.put('ProductName', p2 != null ? p2.get('Name') : null);
            outRows.add(lr);
        }
        return outRows;
    }

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

    @AuraEnabled
    public static void updateLineFields(Id quoteLineItemId, String fieldSetName, Map<String, Object> fields) {
        if (quoteLineItemId == null || fields == null || fields.isEmpty()) {
            throw new AuraHandledException('Line Id and fields are required.');
        }
        String fsName = String.isNotBlank(fieldSetName) ? fieldSetName : DEFAULT_FIELD_SET;
        Schema.FieldSet fs = Schema.SObjectType.QuoteLineItem.FieldSets.getMap().get(fsName);
        if (fs == null) {
            throw new AuraHandledException('Field set not found: ' + fsName);
        }
        Set<String> allowed = new Set<String>();
        for (Schema.FieldSetMember fsm : fs.getFields()) {
            String path = fsm.getFieldPath();
            if (!path.contains('.')) {
                allowed.add(path);
            }
        }
        allowed.remove('Id');
        allowed.remove('QuoteId');
        allowed.remove('ParentQuoteLineItemId');
        QuoteLineItem qli = new QuoteLineItem(Id = quoteLineItemId);
        for (String key : fields.keySet()) {
            if (!allowed.contains(key)) {
                throw new AuraHandledException('Field not allowed: ' + key);
            }
            Schema.SObjectField sf = Schema.SObjectType.QuoteLineItem.fields.getMap().get(key);
            if (sf == null) {
                continue;
            }
            Schema.DescribeFieldResult dfr = sf.getDescribe();
            if (!dfr.isUpdateable() || !dfr.isAccessible()) {
                throw new AuraHandledException('Field not editable: ' + key);
            }
            qli.put(key, fields.get(key));
        }
        Database.update(qli, AccessLevel.USER_MODE);
    }

    // ─── Catalogs (Product Discovery: getCatalogs) ───────────────────────────

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

    // ─── Categories (Product Discovery: getCategories) ───────────────────────

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

    // ─── Default catalog / category context (SOQL-based) ─────────────────────

    @AuraEnabled(cacheable=true)
    public static CatalogSearchContext getDefaultCatalogSearchContext() {
        CatalogSearchContext ctx = new CatalogSearchContext();
        Id categoryId = resolvePaquetesAlarmasCategoryId();
        if (categoryId == null) {
            return ctx;
        }
        List<ProductCategory> rows = [
            SELECT Id, Name, CatalogId, Catalog.Name
            FROM ProductCategory WHERE Id = :categoryId WITH SECURITY_ENFORCED LIMIT 1
        ];
        if (rows.isEmpty()) {
            return ctx;
        }
        ProductCategory pc = rows[0];
        ctx.categoryId = pc.Id;
        ctx.categoryName = pc.Name;
        ctx.catalogId = pc.CatalogId;
        ctx.catalogName = pc.Catalog != null ? pc.Catalog.Name : null;
        return ctx;
    }

    private static Id resolvePaquetesAlarmasCategoryId() {
        List<ProductCatalog> catalogs = [
            SELECT Id FROM ProductCatalog WHERE Name = :TARGET_PRODUCT_CATALOG_NAME
            WITH SECURITY_ENFORCED LIMIT 1
        ];
        if (catalogs.isEmpty()) {
            return null;
        }
        List<ProductCategory> categories = [
            SELECT Id FROM ProductCategory
            WHERE CatalogId = :catalogs[0].Id AND Name = :TARGET_PRODUCT_CATEGORY_NAME
            WITH SECURITY_ENFORCED LIMIT 1
        ];
        return categories.isEmpty() ? null : categories[0].Id;
    }

    // ─── Search products (Product Discovery: findProducts) ───────────────────

    @AuraEnabled
    public static List<ProductSearchResult> searchProductsForQuote(
        Id quoteId, String searchTerm, Id catalogId, Id categoryId
    ) {
        if (quoteId == null) {
            throw new AuraHandledException('Quote Id is required.');
        }
        if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
            return new List<ProductSearchResult>();
        }
        Quote q = queryQuote(quoteId);
        if (USE_SOQL_FALLBACK) {
            return searchProductsDirect(q, searchTerm.trim(), categoryId);
        }
        try {
            return findProductsViaDiscovery(q, searchTerm.trim(), catalogId, categoryId, 25);
        } catch (Exception e) {
            return searchProductsDirect(q, searchTerm.trim(), categoryId);
        }
    }

    private static List<ProductSearchResult> findProductsViaDiscovery(
        Quote q, String searchTerm, Id catalogId, Id categoryId, Integer rowLimit
    ) {
        Invocable.Action action = Invocable.Action.createStandardAction('findProducts');
        action.setInvocationParameter('searchTerm', searchTerm);
        if (catalogId != null) {
            action.setInvocationParameter('catalogId', String.valueOf(catalogId));
        }
        if (categoryId != null) {
            action.setInvocationParameter('categoryId', String.valueOf(categoryId));
        }
        if (q.Pricebook2Id != null) {
            action.setInvocationParameter('priceBookId', String.valueOf(q.Pricebook2Id));
        }
        String quoteCurrency = getQuoteCurrency(q);
        if (String.isNotBlank(quoteCurrency)) {
            action.setInvocationParameter('currencyCode', quoteCurrency);
        }
        action.setInvocationParameter('limit', rowLimit);
        action.setInvocationParameter('enablePricing', true);

        List<Invocable.Action.Result> results = action.invoke();
        if (results == null || results.isEmpty() || !results[0].isSuccess()) {
            String errMsg = extractInvocableError(results);
            throw new AuraHandledException('Product Discovery findProducts failed' +
                (String.isNotBlank(errMsg) ? ': ' + errMsg : '.'));
        }
        Map<String, Object> output = results[0].getOutputParameters();
        return parseProductResults(output);
    }

    // ─── List products (Product Discovery: getProducts) ──────────────────────

    @AuraEnabled
    public static List<ProductSearchResult> listProductsForQuote(
        Id quoteId, Id catalogId, Id categoryId
    ) {
        if (quoteId == null) {
            throw new AuraHandledException('Quote Id is required.');
        }
        Quote q = queryQuote(quoteId);
        if (USE_SOQL_FALLBACK) {
            return listProductsDirect(q, categoryId);
        }
        try {
            return getProductsViaDiscovery(q, catalogId, categoryId, 50);
        } catch (Exception e) {
            return listProductsDirect(q, categoryId);
        }
    }

    private static List<ProductSearchResult> getProductsViaDiscovery(
        Quote q, Id catalogId, Id categoryId, Integer rowLimit
    ) {
        Invocable.Action action = Invocable.Action.createStandardAction('getProducts');
        if (catalogId != null) {
            action.setInvocationParameter('catalogId', String.valueOf(catalogId));
        }
        if (categoryId != null) {
            action.setInvocationParameter('categoryId', String.valueOf(categoryId));
        }
        if (q.Pricebook2Id != null) {
            action.setInvocationParameter('priceBookId', String.valueOf(q.Pricebook2Id));
        }
        String quoteCurrency = getQuoteCurrency(q);
        if (String.isNotBlank(quoteCurrency)) {
            action.setInvocationParameter('currencyCode', quoteCurrency);
        }
        action.setInvocationParameter('limit', rowLimit);
        action.setInvocationParameter('enablePricing', true);

        List<Invocable.Action.Result> results = action.invoke();
        if (results == null || results.isEmpty() || !results[0].isSuccess()) {
            String errMsg = extractInvocableError(results);
            throw new AuraHandledException('Product Discovery getProducts failed' +
                (String.isNotBlank(errMsg) ? ': ' + errMsg : '.'));
        }
        Map<String, Object> output = results[0].getOutputParameters();
        return parseProductResults(output);
    }

    // ─── Add line (RCA Flow / PlaceQuote / DML fallback) ─────────────────────

    @AuraEnabled
    public static Id addQuoteLine(
        Id quoteId, String product2Id, String pricebookEntryId,
        Decimal unitPrice, Decimal quantity
    ) {
        if (quoteId == null || String.isBlank(pricebookEntryId)) {
            throw new AuraHandledException('Quote Id and PricebookEntry Id are required.');
        }
        if (quantity == null || quantity <= 0) {
            quantity = 1;
        }
        PricebookEntry pbe = queryPricebookEntryForAddLine((Id) pricebookEntryId);
        String effectiveProduct2Id = String.isBlank(product2Id)
            ? String.valueOf(pbe.Product2Id)
            : product2Id;
        Decimal effectiveUnitPrice = unitPrice == null
            ? pbe.UnitPrice
            : unitPrice;
        String billingFrequency = deriveBillingFrequency(pbe, effectiveProduct2Id);
        if (USE_SOQL_FALLBACK) {
            return addLineDirect(
                quoteId,
                effectiveProduct2Id,
                pricebookEntryId,
                effectiveUnitPrice,
                quantity,
                billingFrequency
            );
        }
        String productSellingModelId = null;
        if (Schema.SObjectType.PricebookEntry.fields.getMap().containsKey('ProductSellingModelId')) {
            productSellingModelId = (String) pbe.get('ProductSellingModelId');
        }
        try {
            return addLineViaRcaFlow(quoteId, effectiveProduct2Id, pricebookEntryId, quantity, productSellingModelId);
        } catch (Exception e) {
            try {
                return addLineViaPlaceQuote(
                    quoteId,
                    effectiveProduct2Id,
                    pricebookEntryId,
                    effectiveUnitPrice,
                    quantity,
                    billingFrequency
                );
            } catch (Exception e2) {
                try {
                    return addLineDirect(
                        quoteId,
                        effectiveProduct2Id,
                        pricebookEntryId,
                        effectiveUnitPrice,
                        quantity,
                        billingFrequency
                    );
                } catch (Exception e3) {
                    String msg = 'RCA Flow: ' + firstErrorMessage(e) +
                        ' | PlaceQuote: ' + firstErrorMessage(e2) +
                        ' | DML fallback: ' + firstErrorMessage(e3);
                    AuraHandledException ahe = new AuraHandledException(msg);
                    ahe.setMessage(msg);
                    throw ahe;
                }
            }
        }
    }

    private static PricebookEntry queryPricebookEntryForAddLine(Id pricebookEntryId) {
        if (Schema.SObjectType.PricebookEntry.fields.getMap().containsKey('ProductSellingModelId')) {
            return [
                SELECT Id, Product2Id, UnitPrice, ProductSellingModelId
                FROM PricebookEntry
                WHERE Id = :pricebookEntryId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
        }
        return [
            SELECT Id, Product2Id, UnitPrice
            FROM PricebookEntry
            WHERE Id = :pricebookEntryId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
    }

    private static Id addLineViaRcaFlow(
        Id quoteId, String product2Id, String pricebookEntryId,
        Decimal quantity, String productSellingModelId
    ) {
        Map<String, Object> flowInputs = new Map<String, Object>();
        flowInputs.put('quoteId', String.valueOf(quoteId));
        flowInputs.put('productId', product2Id);
        flowInputs.put('quantity', quantity);
        if (String.isNotBlank(productSellingModelId)) {
            flowInputs.put('productSellingModelID', productSellingModelId);
        }
        Flow.Interview interview = Flow.Interview.createInterview(
            'Add_Quote_Line_Item_to_Quote_NEW_258',
            flowInputs
        );
        interview.start();
        Object successOut = interview.getVariableValue('isSuccess');
        Boolean isSuccess = successOut instanceof Boolean ? (Boolean) successOut : false;
        if (isSuccess != true) {
            String err = (String) interview.getVariableValue('errorMessage');
            throw new AuraHandledException(
                'Add_Quote_Line_Item_to_Quote_NEW_258 failed' +
                (String.isNotBlank(err) ? ': ' + err : '.')
            );
        }
        List<QuoteLineItem> created = [
            SELECT Id
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
              AND PricebookEntryId = :((Id) pricebookEntryId)
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (created.isEmpty()) {
            throw new AuraHandledException(
                'Flow finished but no QuoteLineItem was found for the selected product.'
            );
        }
        return created[0].Id;
    }

    private static Id addLineViaPlaceQuote(
        Id quoteId, String product2Id, String pricebookEntryId,
        Decimal unitPrice, Decimal quantity, String billingFrequency
    ) {
        PlaceQuote.RecordResource quoteRecord =
            new PlaceQuote.RecordResource(Quote.getSobjectType(), 'GET', quoteId);
        PlaceQuote.RecordWithReferenceRequest quoteRef =
            new PlaceQuote.RecordWithReferenceRequest('refQuote', quoteRecord);

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
        qliRecord.fieldValues = qliFields;

        PlaceQuote.RecordWithReferenceRequest qliRef =
            new PlaceQuote.RecordWithReferenceRequest('refQLI', qliRecord);

        List<PlaceQuote.RecordWithReferenceRequest> records =
            new List<PlaceQuote.RecordWithReferenceRequest>();
        records.add(quoteRef);
        records.add(qliRef);

        PlaceQuote.GraphRequest graph = new PlaceQuote.GraphRequest('addLine', records);

        PlaceQuote.ConfigurationOptionsInput cInput = new PlaceQuote.ConfigurationOptionsInput();
        cInput.addDefaultConfiguration = true;
        cInput.executeConfigurationRules = true;
        cInput.validateAmendRenewCancel = false;
        cInput.validateProductCatalog = true;

        PlaceQuote.PricingPreferenceEnum pricingPref =
            PlaceQuote.PricingPreferenceEnum.System;
        PlaceQuote.ConfigurationInputEnum configPref =
            PlaceQuote.ConfigurationInputEnum.RunAndAllowErrors;

        PlaceQuote.PlaceQuoteResponse resp =
            PlaceQuote.PlaceQuoteRLMApexProcessor.execute(
                pricingPref, graph, configPref, cInput
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
                'PlaceQuote failed' + (String.isNotBlank(errDetail) ? ': ' + errDetail : '.')
            );
        }
        return resp.quoteId;
    }

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

    // ─── Configuration flow resolution (ProductConfigurationFlow) ──────────

    /**
     * For each Product2Id, find the active ProductConfigurationFlow.FlowIdentifier
     * assigned via ProductConfigFlowAssignment (by ProductId first, then by
     * ProductClassificationId if available).
     */
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
            // ProductConfigFlowAssignment or ProductClassificationProduct might not exist
        }
        Set<Id> stillUnmatched = new Set<Id>();
        for (Id pid : productIds) {
            if (!flowMap.containsKey(pid)) {
                stillUnmatched.add(pid);
            }
        }
        if (!stillUnmatched.isEmpty()) {
            String defaultFlowApi = resolveDefaultConfigFlowApiName();
            if (String.isNotBlank(defaultFlowApi)) {
                for (Id pid : stillUnmatched) {
                    flowMap.put(pid, defaultFlowApi);
                }
            }
        }
        return flowMap;
    }

    private static String resolveDefaultConfigFlowApiName() {
        try {
            List<ProductConfigurationFlow> rows = [
                SELECT FlowIdentifier
                FROM ProductConfigurationFlow
                WHERE Status = 'Active'
                  AND IsDefault = true
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];
            return rows.isEmpty() ? null : rows[0].FlowIdentifier;
        } catch (Exception e) {
            return null;
        }
    }

    // ─── Shared helpers ──────────────────────────────────────────────────────

    private static Quote queryQuote(Id quoteId) {
        List<String> qf = new List<String>{ 'Id', 'Pricebook2Id' };
        if (Schema.SObjectType.Quote.fields.getMap().containsKey('CurrencyIsoCode')) {
            qf.add('CurrencyIsoCode');
        }
        String soql = 'SELECT ' + String.join(qf, ',') +
            ' FROM Quote WHERE Id = :quoteId WITH SECURITY_ENFORCED LIMIT 1';
        List<Quote> rows = (List<Quote>) Database.query(soql);
        if (rows.isEmpty()) {
            throw new AuraHandledException('Quote not found.');
        }
        return rows[0];
    }

    private static String getQuoteCurrency(Quote q) {
        if (!Schema.SObjectType.Quote.fields.getMap().containsKey('CurrencyIsoCode')) {
            return null;
        }
        return (String) q.get('CurrencyIsoCode');
    }

    /**
     * Converts the output of findProducts / getProducts invocable actions into
     * a flat list of ProductSearchResult (one per product-price combination).
     */
    private static List<ProductSearchResult> parseProductResults(Map<String, Object> output) {
        if (output == null) {
            return new List<ProductSearchResult>();
        }
        Object rawResults = output.get('results');
        if (rawResults == null) {
            rawResults = output.get('result');
        }
        if (rawResults == null) {
            return new List<ProductSearchResult>();
        }
        String rawJson = JSON.serialize(rawResults);
        List<Object> productList = extractProductList(rawJson);
        List<ProductSearchResult> out = new List<ProductSearchResult>();
        for (Object prodObj : productList) {
            Map<String, Object> pMap = (Map<String, Object>) prodObj;
            String prodId = firstNonBlank(
                toStr(pMap.get('id')),
                toStr(pMap.get('productId')),
                toStr(pMap.get('product2Id'))
            );
            String prodName = firstNonBlank(
                toStr(pMap.get('name')),
                toStr(pMap.get('productName')),
                toStr(pMap.get('displayName'))
            );
            String prodCode = firstNonBlank(
                toStr(pMap.get('productCode')),
                toStr(pMap.get('code'))
            );
            List<Object> prices = pMap.get('prices') instanceof List<Object>
                ? (List<Object>) pMap.get('prices')
                : new List<Object>();
            String defaultSellingModel = extractDefaultSellingModelName(pMap);
            if (prices.isEmpty()) {
                ProductSearchResult r = new ProductSearchResult();
                r.product2Id = prodId;
                r.productName = prodName;
                r.productCode = prodCode;
                r.sellingModelName = defaultSellingModel;
                out.add(r);
            } else {
                for (Object priceObj : prices) {
                    Map<String, Object> pr = (Map<String, Object>) priceObj;
                    ProductSearchResult r = new ProductSearchResult();
                    r.product2Id = prodId;
                    r.productName = prodName;
                    r.productCode = prodCode;
                    r.pricebookEntryId = firstNonBlank(
                        toStr(pr.get('priceBookEntryId')),
                        toStr(pr.get('pricebookEntryId'))
                    );
                    Object priceValue = pr.get('price');
                    if (priceValue == null) {
                        priceValue = pr.get('unitPrice');
                    }
                    if (priceValue == null) {
                        priceValue = pr.get('listPrice');
                    }
                    r.unitPrice = toDecimal(priceValue);
                    r.currencyIsoCode = firstNonBlank(
                        toStr(pr.get('currencyIsoCode')),
                        toStr(pr.get('currencyCode'))
                    );
                    Map<String, Object> pm = pr.get('pricingModel') instanceof Map<String, Object>
                        ? (Map<String, Object>) pr.get('pricingModel')
                        : null;
                    if (pm != null) {
                        String pmName = (String) pm.get('name');
                        String pmType = (String) pm.get('pricingModelType');
                        r.sellingModelName = String.isNotBlank(pmName)
                            ? pmName + (String.isNotBlank(pmType) ? ' (' + pmType + ')' : '')
                            : pmType;
                    } else {
                        r.sellingModelName = defaultSellingModel;
                    }
                    out.add(r);
                }
            }
        }
        return out;
    }

    private static String toStr(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static String firstNonBlank(String a, String b) {
        return String.isNotBlank(a) ? a : b;
    }

    private static String firstNonBlank(String a, String b, String c) {
        return firstNonBlank(firstNonBlank(a, b), c);
    }

    private static Decimal toDecimal(Object value) {
        if (value == null) {
            return null;
        }
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }

    private static List<Object> extractProductList(String rawJson) {
        Object parsed = JSON.deserializeUntyped(rawJson);
        if (parsed instanceof List<Object>) {
            return (List<Object>) parsed;
        }
        if (parsed instanceof Map<String, Object>) {
            Map<String, Object> wrapper = (Map<String, Object>) parsed;
            for (String key : new String[]{ 'products', 'records', 'result', 'results' }) {
                Object nested = wrapper.get(key);
                if (nested instanceof List<Object>) {
                    return (List<Object>) nested;
                }
            }
        }
        return new List<Object>();
    }

    private static String extractDefaultSellingModelName(Map<String, Object> productMap) {
        Object psmoRaw = productMap.get('productSellingModelOptions');
        if (!(psmoRaw instanceof List<Object>)) {
            return null;
        }
        for (Object optObj : (List<Object>) psmoRaw) {
            Map<String, Object> opt = (Map<String, Object>) optObj;
            Object psmRaw = opt.get('productSellingModel');
            if (psmRaw instanceof Map<String, Object>) {
                Map<String, Object> psm = (Map<String, Object>) psmRaw;
                return (String) psm.get('name');
            }
        }
        return null;
    }

    private static String extractInvocableError(List<Invocable.Action.Result> results) {
        if (results == null || results.isEmpty()) {
            return null;
        }
        Invocable.Action.Result res = results[0];
        if (res.isSuccess()) {
            return null;
        }
        List<Invocable.Action.Error> errors = res.getErrors();
        if (errors == null || errors.isEmpty()) {
            return null;
        }
        List<String> msgs = new List<String>();
        for (Invocable.Action.Error err : errors) {
            msgs.add(err.getMessage());
        }
        return String.join(msgs, '; ');
    }

    // ─── SOQL/DML fallback for search / list (test isolation) ────────────────

    @TestVisible
    private static List<ProductSearchResult> searchProductsDirect(
        Quote q, String searchTerm, Id categoryId
    ) {
        if (categoryId == null || q.Pricebook2Id == null) {
            return new List<ProductSearchResult>();
        }
        Id productCategoryId = categoryId;
        return mapPricebookToSearchResults(
            queryPricebookEntriesForCategory(q, productCategoryId, searchTerm, 25)
        );
    }

    @TestVisible
    private static List<ProductSearchResult> listProductsDirect(Quote q, Id categoryId) {
        if (categoryId == null || q.Pricebook2Id == null) {
            return new List<ProductSearchResult>();
        }
        Id productCategoryId = categoryId;
        return mapPricebookToSearchResults(
            queryPricebookEntriesForCategory(q, productCategoryId, null, 50)
        );
    }

    private static List<ProductSearchResult> mapPricebookToSearchResults(List<PricebookEntry> entries) {
        List<ProductSearchResult> outList = new List<ProductSearchResult>();
        Boolean hasPbeCurrency = Schema.SObjectType.PricebookEntry.fields.getMap().containsKey('CurrencyIsoCode');
        Boolean hasPsm = Schema.SObjectType.Product2.fields.getMap().containsKey('ProductSellingModelId');
        for (PricebookEntry pbe : entries) {
            ProductSearchResult r = new ProductSearchResult();
            r.pricebookEntryId = pbe.Id;
            r.product2Id = pbe.Product2Id;
            r.productName = pbe.Product2.Name;
            r.productCode = pbe.Product2.ProductCode;
            r.unitPrice = pbe.UnitPrice;
            if (hasPbeCurrency) {
                r.currencyIsoCode = (String) pbe.get('CurrencyIsoCode');
            }
            if (hasPsm) {
                SObject p2 = pbe.getSObject('Product2');
                if (p2 != null) {
                    SObject psm = p2.getSObject('ProductSellingModel');
                    if (psm != null) {
                        r.sellingModelName = (String) psm.get('Name');
                    }
                }
            }
            outList.add(r);
        }
        return outList;
    }

    private static List<PricebookEntry> queryPricebookEntriesForCategory(
        Quote q, Id productCategoryId, String searchTermOrNull, Integer rowLimit
    ) {
        List<String> selectFields = new List<String>{
            'Id', 'Product2Id', 'UnitPrice', 'Product2.Name', 'Product2.ProductCode'
        };
        Map<String, Schema.SObjectField> pbeMap = Schema.SObjectType.PricebookEntry.fields.getMap();
        if (pbeMap.containsKey('CurrencyIsoCode')) {
            selectFields.add('CurrencyIsoCode');
        }
        if (Schema.SObjectType.Product2.fields.getMap().containsKey('ProductSellingModelId')) {
            selectFields.add('Product2.ProductSellingModel.Name');
        }
        Id pbId = q.Pricebook2Id;
        String quoteCurrency = getQuoteCurrency(q);
        String soql =
            'SELECT ' + String.join(selectFields, ',') +
            ' FROM PricebookEntry WHERE Pricebook2Id = :pbId' +
            ' AND IsActive = TRUE AND Product2.IsActive = TRUE' +
            ' AND Product2Id IN (SELECT ProductId FROM ProductCategoryProduct WHERE ProductCategoryId = :productCategoryId)';
        if (pbeMap.containsKey('CurrencyIsoCode') && String.isNotBlank(quoteCurrency)) {
            soql += ' AND CurrencyIsoCode = :quoteCurrency';
        }
        if (String.isNotBlank(searchTermOrNull)) {
            String term = '%' + searchTermOrNull.trim() + '%';
            soql += ' AND (Product2.Name LIKE :term OR Product2.ProductCode LIKE :term)';
        }
        soql += ' WITH SECURITY_ENFORCED ORDER BY Product2.Name LIMIT :rowLimit';
        return (List<PricebookEntry>) Database.query(soql);
    }

    private static String buildDmlMessage(DmlException e) {
        String msg = e.getMessage();
        if (e.getNumDml() > 0 && !e.getDmlFields(0).isEmpty()) {
            msg += ' — ' + String.join(e.getDmlFields(0), ', ');
        }
        return msg;
    }

    private static String firstErrorMessage(Exception e) {
        if (e == null) {
            return 'unknown';
        }
        return String.isNotBlank(e.getMessage()) ? e.getMessage() : e.getTypeName();
    }

    private static String deriveBillingFrequency(PricebookEntry pbe, String product2Id) {
        String pricingTermUnit = null;
        try {
            if (Schema.SObjectType.PricebookEntry.fields.getMap().containsKey('ProductSellingModelId')) {
                Id psmId = (Id) pbe.get('ProductSellingModelId');
                if (psmId != null) {
                    List<ProductSellingModel> psmRows = [
                        SELECT PricingTermUnit
                        FROM ProductSellingModel
                        WHERE Id = :psmId
                        LIMIT 1
                    ];
                    if (!psmRows.isEmpty()) {
                        pricingTermUnit = psmRows[0].PricingTermUnit;
                    }
                }
            }
            if (String.isBlank(pricingTermUnit) &&
                Schema.SObjectType.Product2.fields.getMap().containsKey('ProductSellingModelId') &&
                product2Id != null) {
                String p2Soql =
                    'SELECT ProductSellingModelId FROM Product2 WHERE Id = :pid LIMIT 1';
                Id pid = (Id) product2Id;
                List<SObject> products = Database.query(p2Soql);
                if (!products.isEmpty()) {
                    Id psmIdFromProduct = (Id) products[0].get('ProductSellingModelId');
                    if (psmIdFromProduct != null) {
                        List<ProductSellingModel> psmRowsFromProduct = [
                            SELECT PricingTermUnit
                            FROM ProductSellingModel
                            WHERE Id = :psmIdFromProduct
                            LIMIT 1
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
        if (key == 'month' || key == 'months') {
            return 'Monthly';
        }
        if (key == 'quarter' || key == 'quarters' || key == 'quarterly') {
            return 'Quarterly';
        }
        if (key == 'year' || key == 'years' || key == 'annual' || key == 'annually') {
            return 'Annual';
        }
        if (key == 'semi-annual' || key == 'semi annual' || key == 'semiannually') {
            return 'Semi-Annual';
        }
        return pricingTermUnit;
    }
}