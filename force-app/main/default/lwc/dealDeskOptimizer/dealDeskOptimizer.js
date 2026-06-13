import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRecommendations from '@salesforce/apex/DealDeskRecommendationsController.getRecommendations';
import getQuoteSummary from '@salesforce/apex/DealDeskRecommendationsController.getQuoteSummary';
import applyOne from '@salesforce/apex/DealDeskRecommendationsController.applyOne';
import applyAll from '@salesforce/apex/DealDeskRecommendationsController.applyAll';
import scoreQuote from '@salesforce/apex/DealDeskRecommendationsController.scoreQuote';

const SEGMENT_STYLE = {
    Premium: 'segment-premium',
    Standard: 'segment-standard',
    'At-Risk': 'segment-atrisk',
    'Churn-Risk': 'segment-churnrisk'
};

const STRATEGY_STYLE = {
    'Churn Mitigation': 'strategy-churn',
    'Loyalty Retention': 'strategy-loyalty',
    'Segmentation Match': 'strategy-segment',
    'Lifetime Value Optimization': 'strategy-ltv',
    'Industry Benchmark Match': 'strategy-benchmark',
    'Bundle Retention': 'strategy-bundle',
    'Margin Floor': 'strategy-margin',
    'Compliance Approval Avoidance': 'strategy-compliance'
};

export default class DealDeskOptimizer extends LightningElement {
    @api recordId;
    @track applyingId;
    @track applyingAll = false;
    @track analyzing = false;
    wiredRecsResult;
    wiredSummaryResult;
    recs = [];
    summary = {};
    error;

    @wire(getRecommendations, { quoteId: '$recordId' })
    wiredRecs(result) {
        this.wiredRecsResult = result;
        if (result.data) {
            this.recs = result.data.map((r) => this.decorate(r));
            this.error = undefined;
        } else if (result.error) {
            this.error = this.extractErrorMessage(result.error);
            this.recs = [];
        }
    }

    @wire(getQuoteSummary, { quoteId: '$recordId' })
    wiredSummary(result) {
        this.wiredSummaryResult = result;
        if (result.data) {
            this.summary = result.data;
        }
    }

    decorate(rec) {
        const segmentClass = SEGMENT_STYLE[rec.Customer_Segment__c] || 'segment-standard';
        const strategyClass = STRATEGY_STYLE[rec.Strategy__c] || 'strategy-default';
        const confidence = rec.Confidence_Score__c == null ? 0 : Number(rec.Confidence_Score__c);
        return {
            ...rec,
            segmentClass,
            strategyClass,
            confidence,
            confidenceStyle: `width: ${Math.max(4, Math.min(100, confidence))}%`,
            currentFormatted: this.formatPct(rec.Current_Discount__c),
            recommendedFormatted: this.formatPct(rec.Recommended_Discount__c),
            historicalFormatted: this.formatPct(rec.Historical_Discount_Avg__c),
            benchmarkFormatted: this.formatPct(rec.Industry_Benchmark_Discount__c),
            marginFormatted: this.formatPct(rec.Margin_After_Discount__c),
            netImpactFormatted: this.formatEur(rec.Net_Increase__c),
            tenureLabel: rec.Account_Tenure_Months__c != null
                ? `${rec.Account_Tenure_Months__c} m`
                : '—',
            similarLabel: rec.Similar_Customers_Count__c != null
                ? `${rec.Similar_Customers_Count__c} cuentas`
                : '—',
            isApplied: rec.Applied__c === true,
            applyDisabled: rec.Applied__c === true || this.applyingId === rec.Id,
            applying: this.applyingId === rec.Id
        };
    }

    formatPct(val) {
        if (val == null) return '0%';
        return `${Number(val).toFixed(2)}%`;
    }

    formatEur(val) {
        if (val == null) return '0 €';
        const n = Number(val);
        const sign = n >= 0 ? '+' : '';
        return `${sign}${n.toFixed(2)} €`;
    }

    extractErrorMessage(err) {
        if (!err) return 'Error desconocido.';
        if (err.body && err.body.message) return err.body.message;
        if (Array.isArray(err.body)) return err.body.map((e) => e.message).join(', ');
        if (typeof err.message === 'string') return err.message;
        return JSON.stringify(err);
    }

    get hasRecs() {
        return Array.isArray(this.recs) && this.recs.length > 0;
    }

    get pendingCount() {
        return this.recs ? this.recs.filter((r) => !r.isApplied).length : 0;
    }

    get appliedCount() {
        return this.recs ? this.recs.filter((r) => r.isApplied).length : 0;
    }

    get applyAllDisabled() {
        return this.applyingAll || this.pendingCount === 0;
    }

    get netImpactFormatted() {
        if (!this.summary || this.summary.netImpact == null) return '0 €';
        const n = Number(this.summary.netImpact);
        const sign = n >= 0 ? '+' : '';
        return `${sign}${n.toFixed(2)} €`;
    }

    get headerLine() {
        const acct = this.summary && this.summary.accountName ? this.summary.accountName : '';
        const num = this.summary && this.summary.quoteNumber ? this.summary.quoteNumber : '';
        if (!acct && !num) return 'Recomendaciones de retención';
        return acct ? `${acct} · ${num}` : `Presupuesto ${num}`;
    }

    async handleScore() {
        this.analyzing = true;
        try {
            await scoreQuote({ quoteId: this.recordId });
            await this.refreshData();
            this.toast('Análisis completado', 'Recomendaciones actualizadas.', 'success');
        } catch (e) {
            this.toast('No se pudo analizar', this.extractErrorMessage(e), 'error');
        } finally {
            this.analyzing = false;
        }
    }

    async handleApplyOne(event) {
        const recId = event.currentTarget.dataset.id;
        if (!recId) return;
        this.applyingId = recId;
        this.refreshDecorations();
        try {
            await applyOne({ recommendationId: recId });
            await this.refreshData();
            this.toast('Recomendación aplicada', 'El descuento se ha trasladado a la línea.', 'success');
        } catch (e) {
            this.toast('No se pudo aplicar', this.extractErrorMessage(e), 'error');
        } finally {
            this.applyingId = undefined;
            this.refreshDecorations();
        }
    }

    async handleApplyAll() {
        this.applyingAll = true;
        try {
            const res = await applyAll({ quoteId: this.recordId });
            await this.refreshData();
            const total = res && res.appliedCount != null ? res.appliedCount : 0;
            this.toast(
                'Recomendaciones aplicadas',
                `Se han aplicado ${total} líneas. Refresca el presupuesto para ver los totales recalculados.`,
                'success'
            );
        } catch (e) {
            this.toast('No se pudo aplicar', this.extractErrorMessage(e), 'error');
        } finally {
            this.applyingAll = false;
        }
    }

    async refreshData() {
        await Promise.all([
            refreshApex(this.wiredRecsResult),
            refreshApex(this.wiredSummaryResult)
        ]);
    }

    refreshDecorations() {
        if (!this.recs) return;
        this.recs = this.recs.map((r) => ({
            ...r,
            applyDisabled: r.isApplied || this.applyingId === r.Id,
            applying: this.applyingId === r.Id
        }));
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}