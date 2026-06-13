/**
 * Controller for the `dealDeskOptimizer` Lightning Web Component.
 *
 * Exposes cache-disabled @AuraEnabled endpoints to:
 *   - list every DealDesk_Recommendation__c for a Quote with all Prosegur
 *     enrichment fields (segment, tenure, benchmark, confidence...)
 *   - apply a single recommendation by Id
 *   - apply every pending recommendation for the Quote in one call
 *   - return a small Quote-level summary for the LWC header
 */
public with sharing class DealDeskRecommendationsController {

    @AuraEnabled(cacheable=true)
    public static List<DealDesk_Recommendation__c> getRecommendations(Id quoteId) {
        if (quoteId == null) {
            return new List<DealDesk_Recommendation__c>();
        }
        return [
            SELECT Id, Name, Quote__c, QuoteLineItemId__c, Product_Name__c,
                   Category__c, Sub_Category__c, Strategy__c, Reason__c,
                   Current_Discount__c, Recommended_Discount__c, Net_Increase__c,
                   Applied__c, Status__c,
                   Account_Tenure_Months__c, Customer_Segment__c,
                   Historical_Discount_Avg__c, Industry_Benchmark_Discount__c,
                   Similar_Customers_Count__c, Confidence_Score__c,
                   Margin_After_Discount__c, Recommendation_Source__c,
                   CreatedDate
            FROM DealDesk_Recommendation__c
            WHERE Quote__c = :quoteId
            ORDER BY Applied__c ASC, Confidence_Score__c DESC NULLS LAST, CreatedDate ASC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static QuoteSummary getQuoteSummary(Id quoteId) {
        QuoteSummary out = new QuoteSummary();
        if (quoteId == null) {
            return out;
        }
        List<Quote> quotes = [
            SELECT Id, QuoteNumber, Name, GrandTotal, TotalPrice, Discount,
                   AccountId, Account.Name
            FROM Quote
            WHERE Id = :quoteId
            LIMIT 1
        ];
        if (quotes.isEmpty()) {
            return out;
        }
        Quote q = quotes[0];
        out.quoteNumber = q.QuoteNumber;
        out.accountName = q.Account != null ? q.Account.Name : null;
        out.grandTotal = q.GrandTotal != null ? q.GrandTotal : (q.TotalPrice != null ? q.TotalPrice : 0);
        out.headerDiscount = q.Discount != null ? q.Discount : 0;

        AggregateResult[] aggrs = [
            SELECT COUNT(Id) total,
                   SUM(Net_Increase__c) netImpact
            FROM DealDesk_Recommendation__c
            WHERE Quote__c = :quoteId
        ];
        if (aggrs != null && !aggrs.isEmpty()) {
            Object tot = aggrs[0].get('total');
            Object netImp = aggrs[0].get('netImpact');
            out.recommendationCount = tot == null ? 0 : (Integer) tot;
            out.netImpact = netImp == null ? 0 : (Decimal) netImp;
        }

        AggregateResult[] pendingAggrs = [
            SELECT COUNT(Id) pending
            FROM DealDesk_Recommendation__c
            WHERE Quote__c = :quoteId AND Applied__c = false
        ];
        if (pendingAggrs != null && !pendingAggrs.isEmpty()) {
            Object pend = pendingAggrs[0].get('pending');
            out.pendingCount = pend == null ? 0 : (Integer) pend;
        }
        return out;
    }

    @AuraEnabled
    public static Boolean applyOne(Id recommendationId) {
        if (recommendationId == null) {
            throw new AuraHandledException('No se ha indicado la recomendación a aplicar.');
        }
        try {
            return DealDeskApplyRecommendations.applyOne(recommendationId);
        } catch (Exception e) {
            throw new AuraHandledException('Error al aplicar la recomendación: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static ApplyAllResult applyAll(Id quoteId) {
        if (quoteId == null) {
            throw new AuraHandledException('No se ha indicado el presupuesto.');
        }
        try {
            DealDeskApplyRecommendations.ApplyResult res =
                DealDeskApplyRecommendations.applyAllInternal(quoteId);
            ApplyAllResult out = new ApplyAllResult();
            out.appliedCount = res.appliedCount;
            out.totalCount = res.totalCount;
            return out;
        } catch (Exception e) {
            throw new AuraHandledException('Error al aplicar las recomendaciones: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String scoreQuote(Id quoteId) {
        if (quoteId == null) {
            throw new AuraHandledException('No se ha indicado el presupuesto.');
        }
        try {
            DealDeskAnalyzer.ActionRequest req = new DealDeskAnalyzer.ActionRequest();
            req.quoteId = quoteId;
            List<DealDeskAnalyzer.ActionResult> res = DealDeskAnalyzer.analyzeQuote(
                new List<DealDeskAnalyzer.ActionRequest>{ req }
            );
            return res.isEmpty() ? '' : res[0].analysisResult;
        } catch (Exception e) {
            throw new AuraHandledException('Error al analizar el presupuesto: ' + e.getMessage());
        }
    }

    public class QuoteSummary {
        @AuraEnabled public String quoteNumber;
        @AuraEnabled public String accountName;
        @AuraEnabled public Decimal grandTotal = 0;
        @AuraEnabled public Decimal headerDiscount = 0;
        @AuraEnabled public Decimal netImpact = 0;
        @AuraEnabled public Integer recommendationCount = 0;
        @AuraEnabled public Integer pendingCount = 0;
    }

    public class ApplyAllResult {
        @AuraEnabled public Integer appliedCount = 0;
        @AuraEnabled public Integer totalCount = 0;
    }
}