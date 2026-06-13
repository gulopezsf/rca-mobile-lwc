import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getQuoteContext from '@salesforce/apex/MobileTleController.getQuoteContext';
import getLines from '@salesforce/apex/MobileTleController.getLines';
import getFieldSetColumns from '@salesforce/apex/MobileTleController.getFieldSetColumns';
import deleteLine from '@salesforce/apex/MobileTleController.deleteLine';
import cloneQuoteLine from '@salesforce/apex/MobileTleController.cloneQuoteLine';
import updateLineSingleField from '@salesforce/apex/MobileTleController.updateLineSingleField';
import FORM_FACTOR from '@salesforce/client/formFactor';
import LightningConfirm from 'lightning/confirm';
import { reduceError } from 'c/mobileTleUtils';

// Custom Labels
import LBL_QUOTE_LINES from '@salesforce/label/c.MTLE_QuoteLines';
import LBL_ADD_PRODUCT from '@salesforce/label/c.MTLE_AddProduct';
import LBL_REFRESH from '@salesforce/label/c.MTLE_Refresh';
import LBL_LOADING from '@salesforce/label/c.MTLE_Loading';
import LBL_NO_QUOTE_LINES from '@salesforce/label/c.MTLE_NoQuoteLines';
import LBL_PRESS_ADD from '@salesforce/label/c.MTLE_PressAddToStart';
import LBL_ADDING from '@salesforce/label/c.MTLE_Adding';
import LBL_VIEW_DETAIL from '@salesforce/label/c.MTLE_ViewDetail';
import LBL_CLONE_LINE from '@salesforce/label/c.MTLE_CloneLine';
import LBL_CONFIGURE from '@salesforce/label/c.MTLE_Configure';
import LBL_DELETE from '@salesforce/label/c.MTLE_Delete';
import LBL_CONFIRM_DELETE from '@salesforce/label/c.MTLE_ConfirmDeleteLine';
import LBL_DELETE_HEADER from '@salesforce/label/c.MTLE_DeleteLineHeader';
import LBL_LINE_DELETED from '@salesforce/label/c.MTLE_LineDeleted';
import LBL_LINE_CLONED from '@salesforce/label/c.MTLE_LineCloned';
import LBL_FIELD_UPDATED from '@salesforce/label/c.MTLE_FieldUpdated';
import LBL_PRODUCT_ADDED from '@salesforce/label/c.MTLE_ProductAddedToQuote';
import LBL_BUNDLE_ADDED from '@salesforce/label/c.MTLE_BundleAddedToQuote';
import LBL_COULD_NOT_ADD from '@salesforce/label/c.MTLE_CouldNotAdd';
import LBL_COPY_SUFFIX from '@salesforce/label/c.MTLE_CopySuffix';
import LBL_SUCCESS from '@salesforce/label/c.MTLE_Success';
import LBL_ERROR from '@salesforce/label/c.MTLE_Error';
import LBL_INFO from '@salesforce/label/c.MTLE_Info';
import LBL_PRODUCT from '@salesforce/label/c.MTLE_Product';
import LBL_BUNDLE_WITH_N from '@salesforce/label/c.MTLE_BundleWithNComponents';

function fmt(template, ...args) {
    return template.replace(/\{(\d+)\}/g, (_, i) => args[i] ?? '');
}

export default class MobileTransactionLineEditor extends NavigationMixin(LightningElement) {
    @api recordId;
    @api fieldSetName = 'Quote_Line_Editor_Columns';
    @api hideAddProducts = false;
    @api configuratorFlowApiName = ''; // deprecated — kept for backward compat with page layouts
    @api defaultPageSize = 6;

    @track loading = true;
    @track error;
    @track quoteContext;
    @track lineRows = [];
    @track columnDefinitions = [];

    // Product browser state
    @track showProductBrowser = false;
    @track pendingCards = []; // optimistic UI cards

    // Configurator state
    @track showConfigurator = false;
    @track configuratorLineId = '';

    // Bottom sheet (line actions)
    @track showActionSheet = false;
    @track actionSheetLineId;
    @track actionSheetLine;

    _formFactor = FORM_FACTOR;

    // Expose labels to template
    label = {
        quoteLines: LBL_QUOTE_LINES,
        addProduct: LBL_ADD_PRODUCT,
        refresh: LBL_REFRESH,
        loading: LBL_LOADING,
        noQuoteLines: LBL_NO_QUOTE_LINES,
        pressAdd: LBL_PRESS_ADD,
        adding: LBL_ADDING,
        viewDetail: LBL_VIEW_DETAIL,
        cloneLine: LBL_CLONE_LINE,
        configure: LBL_CONFIGURE,
        deleteLbl: LBL_DELETE,
        info: LBL_INFO
    };

    get isMobile() {
        return this._formFactor === 'Small';
    }

    get hasLines() {
        return this.lineRows && this.lineRows.length > 0;
    }

    get hasPendingCards() {
        return this.pendingCards && this.pendingCards.length > 0;
    }

    get showEmptyState() {
        return !this.hasLines && !this.hasPendingCards && !this.loading;
    }

    get addButtonLabel() {
        return LBL_ADD_PRODUCT;
    }

    get showAddButton() {
        return !this.hideAddProducts && this.quoteContext;
    }

    get showConfigureAction() {
        // Show "Configure" for configurable products or bundle parents
        // (falls back to default org flow ProductConfig if no specific flow assigned)
        const line = this.actionSheetLine;
        return line && (line.isConfigurable || line.isBundleParent);
    }

    // ─── Lifecycle ──────────────────────────────────────────────────────────

    connectedCallback() {
        this.loadInitial();
    }

    async loadInitial() {
        this.loading = true;
        this.error = undefined;
        try {
            const [ctx, cols] = await Promise.all([
                getQuoteContext({ quoteId: this.recordId }),
                getFieldSetColumns({ fieldSetName: this.fieldSetName })
            ]);
            this.quoteContext = ctx;
            this.columnDefinitions = cols || [];
            await this.fetchLines();
        } catch (e) {
            this.error = reduceError(e);
            this.toast(LBL_ERROR, this.error, 'error');
        } finally {
            this.loading = false;
        }
    }

    async fetchLines() {
        const rows = await getLines({
            quoteId: this.recordId,
            fieldSetName: this.fieldSetName
        });
        this.lineRows = rows || [];
    }

    // ─── Refresh ────────────────────────────────────────────────────────────

    handleRefresh() {
        this.loadInitial();
    }

    async refreshAfterAdd(newLineId) {
        const maxAttempts = 8;
        for (let i = 0; i < maxAttempts; i++) {
            await this.fetchLines();
            if (!newLineId || this.lineRows.some((r) => r.id === newLineId)) {
                // Remove pending card on success
                this.pendingCards = [];
                return;
            }
            await this._sleep(650);
        }
        this.pendingCards = [];
    }

    // ─── Add product (open browser) ─────────────────────────────────────────

    handleOpenProductBrowser() {
        this.showProductBrowser = true;
    }

    handleCloseProductBrowser() {
        this.showProductBrowser = false;
    }

    async handleProductAdded(event) {
        const { productName, quantity, newLineId, isBundle, childCount } = event.detail;
        // Add optimistic pending card
        const pendingId = 'pending-' + Date.now();
        const label = isBundle
            ? fmt(LBL_BUNDLE_WITH_N, productName, childCount || 0)
            : (productName || LBL_PRODUCT);
        this.pendingCards = [...this.pendingCards, {
            id: pendingId,
            productName: label,
            quantity: quantity || 1,
            status: 'pending'
        }];
        const msg = isBundle
            ? fmt(LBL_BUNDLE_ADDED, productName)
            : fmt(LBL_PRODUCT_ADDED, productName);
        this.toast(LBL_SUCCESS, msg, 'success');
        // Refresh in background
        await this.refreshAfterAdd(newLineId);
    }

    handleProductAddError(event) {
        const { productName, errorMessage } = event.detail;
        this.toast(LBL_ERROR, fmt(LBL_COULD_NOT_ADD, productName, errorMessage), 'error');
    }

    // ─── Line actions (bottom sheet) ────────────────────────────────────────

    handleLineAction(event) {
        const { lineId, line } = event.detail;
        this.actionSheetLineId = lineId;
        this.actionSheetLine = line;
        this.showActionSheet = true;
    }

    handleCloseActionSheet() {
        this.showActionSheet = false;
        this.actionSheetLineId = null;
        this.actionSheetLine = null;
    }

    async handleActionSelect(event) {
        const action = event.currentTarget?.dataset?.action || event.detail;
        this.showActionSheet = false;
        const lineId = this.actionSheetLineId;
        const line = this.actionSheetLine;

        if (action === 'detail') {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: lineId,
                    objectApiName: 'QuoteLineItem',
                    actionName: 'view'
                }
            });
        } else if (action === 'clone') {
            await this.doClone(lineId, line);
        } else if (action === 'configure') {
            this.openConfigurator(lineId);
        } else if (action === 'delete') {
            await this.doDelete(lineId);
        }
        this.actionSheetLineId = null;
        this.actionSheetLine = null;
    }

    async doDelete(lineId) {
        let ok = false;
        try {
            ok = await LightningConfirm.open({
                message: LBL_CONFIRM_DELETE,
                variant: 'header',
                label: LBL_DELETE_HEADER
            });
        } catch (e) {
            ok = !!globalThis.confirm?.(LBL_CONFIRM_DELETE);
        }
        if (!ok) return;
        try {
            this.loading = true;
            await deleteLine({ quoteLineItemId: lineId });
            this.toast(LBL_SUCCESS, LBL_LINE_DELETED, 'success');
            await this.fetchLines();
        } catch (e) {
            this.toast(LBL_ERROR, reduceError(e), 'error');
        } finally {
            this.loading = false;
        }
    }

    async doClone(lineId, line) {
        try {
            this.loading = true;
            const pendingId = 'pending-clone-' + Date.now();
            this.pendingCards = [...this.pendingCards, {
                id: pendingId,
                productName: (line?.productName || LBL_PRODUCT) + ' ' + LBL_COPY_SUFFIX,
                quantity: line?.quantity || 1,
                status: 'pending'
            }];
            const newId = await cloneQuoteLine({ quoteLineItemId: lineId });
            this.toast(LBL_SUCCESS, LBL_LINE_CLONED, 'success');
            await this.refreshAfterAdd(newId);
        } catch (e) {
            this.pendingCards = [];
            this.toast(LBL_ERROR, reduceError(e), 'error');
        } finally {
            this.loading = false;
        }
    }

    // ─── Inline edit ────────────────────────────────────────────────────────

    async handleInlineEdit(event) {
        const { lineId, fieldName, value } = event.detail;
        try {
            await updateLineSingleField({
                quoteLineItemId: lineId,
                fieldName,
                value
            });
            this.toast(LBL_SUCCESS, LBL_FIELD_UPDATED, 'success');
            await this.fetchLines();
        } catch (e) {
            this.toast(LBL_ERROR, reduceError(e), 'error');
            await this.fetchLines(); // revert display
        }
    }

    // ─── Configurator ───────────────────────────────────────────────────────

    openConfigurator(lineId) {
        this.configuratorLineId = lineId;
        this.showConfigurator = true;
    }

    handleConfiguratorClose() {
        this.showConfigurator = false;
        this.configuratorLineId = '';
    }

    async handleConfiguratorDone() {
        this.showConfigurator = false;
        this.configuratorLineId = '';
        await this.fetchLines();
    }

    // ─── Helpers ────────────────────────────────────────────────────────────

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _sleep(ms) {
        return new Promise((resolve) => setTimeout(resolve, ms));
    }
}
