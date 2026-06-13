import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import getLines from '@salesforce/apex/QuoteLineEditorController.getLines';
import getFieldSetColumns from '@salesforce/apex/QuoteLineEditorController.getFieldSetColumns';
import deleteLine from '@salesforce/apex/QuoteLineEditorController.deleteLine';
import searchProductsForQuote from '@salesforce/apex/QuoteLineEditorController.searchProductsForQuote';
import listProductsForQuote from '@salesforce/apex/QuoteLineEditorController.listProductsForQuote';
import addQuoteLine from '@salesforce/apex/QuoteLineEditorController.addQuoteLine';
import getProductCatalogs from '@salesforce/apex/QuoteLineEditorController.getProductCatalogs';
import getProductCategoriesForCatalog from '@salesforce/apex/QuoteLineEditorController.getProductCategoriesForCatalog';
import getDefaultCatalogSearchContext from '@salesforce/apex/QuoteLineEditorController.getDefaultCatalogSearchContext';
import { flattenTree, formatCellValue } from './quoteLineTreeUtils';
import currencyCode from '@salesforce/i18n/currencyCode';
import FORM_FACTOR from '@salesforce/client/formFactor';

const STORAGE_CATALOG_PREFIX = 'quoteBundleEditor.catalogContext.';
/** Orden por defecto si Display columns está vacío en App Builder (deben existir en el Field Set / ProductName sintético). */
const DEFAULT_VISIBLE_COLUMNS = ['ProductName', 'Quantity', 'UnitPrice', 'NetUnitPrice', 'NetTotalPrice'];

export default class QuoteLineBundleEditor extends NavigationMixin(LightningElement) {
    @api recordId;
    @api fieldSetName = 'Quote_Line_Editor_Columns';
    @api configuratorFlowApiName = '';
    @api configuratorFlowInputVariableName = 'recordId';
    /** Comma- or newline-separated field API names (solo App Builder). Vacío = columnas por defecto del componente. */
    @api displayColumns;
    /** Conservado por compatibilidad con páginas Lightning; el picker en runtime ya no se muestra. */
    @api hideRuntimeColumnPicker;
    @api hideAddProducts;
    /** Omit or set true in App Builder; set false to hide. */
    @api showDetailAction;
    @api showDeleteAction;
    @api showConfigureAction;

    @track loading = true;
    @track error;
    @track columnDefinitions = [];
    @track selectedColumnApiNames = [];
    @track lineRows = [];
    @track displayRows = [];
    @track showFlowModal = false;
    @track flowInputVariables = [];
    @track currentFlowApiName = '';
    @track searchTerm = '';
    @track searchResults = [];
    @track searchLoading = false;

    @track catalogRows = [];
    @track draftCategoryRows = [];
    @track selectedCatalogId;
    @track selectedCategoryId;
    @track selectedCatalogName = '';
    @track selectedCategoryName = '';
    @track draftCatalogId;
    @track draftCategoryId;
    @track showCatalogModal = false;
    @track draftCategoriesLoading = false;

    searchDebounceId;
    _searchResultMap = new Map();
    _formFactor = FORM_FACTOR;
    _collapsedRowIds = new Set();

    connectedCallback() {
        this.loadColumnsAndLines();
    }

    async loadColumnsAndLines() {
        this.loading = true;
        this.error = undefined;
        try {
            const cols = await getFieldSetColumns({ fieldSetName: this.fieldSetName });
            this.columnDefinitions = cols || [];
            this.applyColumnSelection();
            await this.fetchLines();
            if (this.hideAddProducts !== true) {
                await this.initCatalogSearchUx();
            }
        } catch (e) {
            this.error = this.reduceError(e);
            this.showErrorToast(this.error);
        } finally {
            this.loading = false;
        }
    }

    async initCatalogSearchUx() {
        try {
            const raw = this.getLocalStorage()?.getItem(STORAGE_CATALOG_PREFIX + this.recordId);
            if (raw) {
                const ctx = JSON.parse(raw);
                if (ctx && ctx.categoryId) {
                    this.selectedCatalogId = ctx.catalogId;
                    this.selectedCategoryId = ctx.categoryId;
                    this.selectedCatalogName = ctx.catalogName || '';
                    this.selectedCategoryName = ctx.categoryName || '';
                    await this.ensureCatalogRowsLoaded();
                    return;
                }
            }
            const def = await getDefaultCatalogSearchContext();
            if (def && def.categoryId) {
                this.selectedCatalogId = def.catalogId;
                this.selectedCategoryId = def.categoryId;
                this.selectedCatalogName = def.catalogName || '';
                this.selectedCategoryName = def.categoryName || '';
                await this.ensureCatalogRowsLoaded();
                this.persistCatalogContext();
                return;
            }
            await this.ensureCatalogRowsLoaded();
        } catch (e) {
            /* non-fatal: user can open the picker */
        }
    }

    async ensureCatalogRowsLoaded() {
        if (this.catalogRows && this.catalogRows.length > 0) {
            return;
        }
        const rows = await getProductCatalogs();
        this.catalogRows = rows || [];
    }

    async openCatalogModal() {
        this.draftCatalogId = this.selectedCatalogId;
        this.draftCategoryId = this.selectedCategoryId;
        await this.ensureCatalogRowsLoaded();
        if (this.draftCatalogId) {
            await this.loadDraftCategoriesForCatalog(this.draftCatalogId);
        } else {
            this.draftCategoryRows = [];
        }
        this.showCatalogModal = true;
    }

    closeCatalogModal() {
        this.showCatalogModal = false;
    }

    async handleDraftCatalogChange(event) {
        this.draftCatalogId = event.detail.value;
        this.draftCategoryId = undefined;
        await this.loadDraftCategoriesForCatalog(this.draftCatalogId);
    }

    handleDraftCategoryChange(event) {
        this.draftCategoryId = event.detail.value;
    }

    async loadDraftCategoriesForCatalog(catalogId) {
        if (!catalogId) {
            this.draftCategoryRows = [];
            return;
        }
        this.draftCategoriesLoading = true;
        try {
            const rows = await getProductCategoriesForCatalog({ catalogId });
            this.draftCategoryRows = rows || [];
        } finally {
            this.draftCategoriesLoading = false;
        }
    }

    handleApplyCatalogModal() {
        if (!this.draftCatalogId || !this.draftCategoryId) {
            this.showErrorToast('Seleccione catálogo y categoría.');
            return;
        }
        const catalogRow = this.catalogRows.find((r) => r.id === this.draftCatalogId);
        const catRow = this.draftCategoryRows.find((r) => r.id === this.draftCategoryId);
        this.selectedCatalogId = this.draftCatalogId;
        this.selectedCategoryId = this.draftCategoryId;
        this.selectedCatalogName = catalogRow ? catalogRow.name : '';
        this.selectedCategoryName = catRow ? catRow.name : '';
        this.persistCatalogContext();
        this.showCatalogModal = false;
        this.searchTerm = '';
        this.searchResults = [];
    }

    persistCatalogContext() {
        try {
            this.getLocalStorage()?.setItem(
                STORAGE_CATALOG_PREFIX + this.recordId,
                JSON.stringify({
                    catalogId: this.selectedCatalogId,
                    categoryId: this.selectedCategoryId,
                    catalogName: this.selectedCatalogName,
                    categoryName: this.selectedCategoryName
                })
            );
        } catch (e) {
            // ignore quota
        }
    }

    get catalogComboOptions() {
        return (this.catalogRows || []).map((r) => ({
            label: r.name,
            value: r.id
        }));
    }

    get draftCategoryComboOptions() {
        return (this.draftCategoryRows || []).map((r) => ({
            label: r.name,
            value: r.id
        }));
    }

    get draftCategoryPicklistDisabled() {
        return !this.draftCatalogId || this.draftCategoriesLoading;
    }

    applyColumnSelection() {
        const defs = this.columnDefinitions;
        const allowed = new Set(defs.map((c) => c.apiName));
        const builder = this.displayColumns && String(this.displayColumns).trim();

        if (builder) {
            const order = builder
                .split(/[,\n]/)
                .map((s) => s.trim())
                .filter(Boolean);
            this.selectedColumnApiNames = order.filter((a) => allowed.has(a));
            if (this.selectedColumnApiNames.length === 0) {
                this.selectedColumnApiNames = this.columnsFromDefaultPreset(allowed);
            }
            return;
        }

        this.selectedColumnApiNames = this.columnsFromDefaultPreset(allowed);
    }

    /** ProductName + Quantity + UnitPrice (Sales Price) + NetUnitPrice + NetTotalPrice cuando existan en el Field Set. */
    columnsFromDefaultPreset(allowed) {
        const ordered = DEFAULT_VISIBLE_COLUMNS.filter((a) => allowed.has(a));
        if (ordered.length > 0) {
            return ordered;
        }
        return this.columnDefinitions.map((c) => c.apiName);
    }

    async fetchLines() {
        const rows = await getLines({
            quoteId: this.recordId,
            fieldSetName: this.fieldSetName
        });
        this.lineRows = rows || [];
        this.rebuildDisplay();
    }

    rebuildDisplay() {
        const colByApi = new Map(this.columnDefinitions.map((c) => [c.apiName, c]));
        const childCountByParent = new Map();
        (this.lineRows || []).forEach((row) => {
            if (row.parentQuoteLineItemId) {
                childCountByParent.set(
                    row.parentQuoteLineItemId,
                    (childCountByParent.get(row.parentQuoteLineItemId) || 0) + 1
                );
            }
        });
        const flat = flattenTree(this.lineRows);
        const builtRows = flat.map(({ row, depth }) => {
            const cells = [];
            this.selectedColumnApiNames.forEach((api) => {
                const def = colByApi.get(api);
                if (!def) {
                    return;
                }
                const val = row.fieldValues ? row.fieldValues[api] : undefined;
                cells.push({
                    apiName: api,
                    label: def.label,
                    display: formatCellValue(val, def.type)
                });
            });
            const rid = row.id;
            const isChild = !!row.parentQuoteLineItemId;
            const showRowDetail = this.showDetailAction === true;
            const showRowDelete = this.showDeleteAction === true && !isChild;
            const showRowConfigure =
                this.showConfigureAction !== false &&
                (!!row.configFlowApiName || !!this.configuratorFlowApiName);
            const hasChildren = (childCountByParent.get(rid) || 0) > 0;
            const isCollapsed = hasChildren && this._collapsedRowIds.has(rid);
            return {
                id: rid,
                parentQuoteLineItemId: row.parentQuoteLineItemId,
                depth,
                styleString: `margin-inline-start:${depth * 1.25}rem`,
                hasChildren,
                isCollapsed,
                collapseIcon: isCollapsed ? 'utility:chevronright' : 'utility:chevrondown',
                collapseAltText: isCollapsed ? 'Desplegar línea' : 'Plegar línea',
                menuDetailValue: `detail|${rid}`,
                menuDeleteValue: `delete|${rid}`,
                menuConfigureValue: `configure|${rid}`,
                configFlowApiName: row.configFlowApiName || '',
                showRowDetail,
                showRowDelete,
                showRowConfigure,
                hasActions: showRowDetail || showRowDelete || showRowConfigure,
                cells
            };
        });
        const rowById = new Map(builtRows.map((r) => [r.id, r]));
        this.displayRows = builtRows.filter((r) => !this.hasCollapsedAncestor(r, rowById));
    }

    get hasRows() {
        return Array.isArray(this.displayRows) && this.displayRows.length > 0;
    }

    get hasRowActions() {
        return this.showDetailAction === true ||
               this.showDeleteAction === true ||
               (this.displayRows || []).some((r) => r.showRowConfigure);
    }

    get showAddSection() {
        return this.hideAddProducts !== true;
    }

    get hasSearchResults() {
        return Array.isArray(this.searchResults) && this.searchResults.length > 0;
    }

    get catalogContextSummary() {
        if (this.selectedCatalogName && this.selectedCategoryName) {
            return `${this.selectedCatalogName} · ${this.selectedCategoryName}`;
        }
        if (this.selectedCategoryName) {
            return this.selectedCategoryName;
        }
        return 'Seleccione catálogo y categoría';
    }

    get listProductsDisabled() {
        return !this.selectedCategoryId;
    }

    get addHelpText() {
        return 'La búsqueda y el listado usan el price book de la cotización y la categoría elegida. Pulse "Catálogo y categoría" para cambiar el origen.';
    }

    handleRefresh() {
        this.loadColumnsAndLines();
    }

    handleSearchInput(event) {
        this.searchTerm = event.target?.value ?? event.detail?.value ?? '';
        clearTimeout(this.searchDebounceId);
        const term = (this.searchTerm || '').trim();
        if (term.length < 2) {
            this.searchResults = [];
            this.searchLoading = false;
            return;
        }
        this.searchLoading = true;
        this.searchDebounceId = setTimeout(() => {
            this.runProductSearch(term);
        }, 320);
    }

    async runProductSearch(term) {
        if (!this.selectedCategoryId) {
            this.showErrorToast('Seleccione catálogo y categoría antes de buscar.');
            this.searchLoading = false;
            return;
        }
        try {
            const raw = await searchProductsForQuote({
                quoteId: this.recordId,
                searchTerm: term,
                catalogId: this.selectedCatalogId,
                categoryId: this.selectedCategoryId
            });
            this._searchResultMap.clear();
            this.searchResults = (raw || []).map((r) => {
                this._searchResultMap.set(r.pricebookEntryId, r);
                return { ...r, displayLabel: this.buildProductLabel(r) };
            });
        } catch (e) {
            this.showErrorToast(this.reduceError(e));
            this.searchResults = [];
        } finally {
            this.searchLoading = false;
        }
    }

    async handleListProducts() {
        if (!this.selectedCategoryId) {
            this.showErrorToast('Seleccione catálogo y categoría.');
            return;
        }
        this.searchLoading = true;
        try {
            const raw = await listProductsForQuote({
                quoteId: this.recordId,
                catalogId: this.selectedCatalogId,
                categoryId: this.selectedCategoryId
            });
            this._searchResultMap.clear();
            this.searchResults = (raw || []).map((r) => {
                this._searchResultMap.set(r.pricebookEntryId, r);
                return { ...r, displayLabel: this.buildProductLabel(r) };
            });
        } catch (e) {
            this.showErrorToast(this.reduceError(e));
            this.searchResults = [];
        } finally {
            this.searchLoading = false;
        }
    }

    buildProductLabel(r) {
        const code = r.productCode ? ` · ${r.productCode}` : '';
        const price = this.formatMoney(r.unitPrice);
        const cur = r.currencyIsoCode ? ` · ${r.currencyIsoCode}` : '';
        const sm = r.sellingModelName ? ` · ${r.sellingModelName}` : '';
        return `${r.productName}${code} — ${price}${cur}${sm}`;
    }

    formatMoney(value) {
        if (value === null || value === undefined) {
            return '—';
        }
        try {
            return new Intl.NumberFormat(undefined, {
                style: 'currency',
                currency: currencyCode || 'USD'
            }).format(Number(value));
        } catch (e) {
            return String(value);
        }
    }

    async handlePickProduct(event) {
        const rowEl = event.currentTarget.closest('[data-pbeid]');
        const pbeId = rowEl ? rowEl.dataset.pbeid : undefined;
        if (!pbeId) {
            return;
        }
        const product = this._searchResultMap.get(pbeId);
        if (!product) {
            this.showErrorToast('No se encontró la referencia del producto.');
            return;
        }
        try {
            const newLineId = await addQuoteLine({
                quoteId: this.recordId,
                product2Id: product.product2Id,
                pricebookEntryId: product.pricebookEntryId,
                unitPrice: product.unitPrice,
                quantity: 1
            });
            this.showSuccessToast('Product added');
            this.searchTerm = '';
            this.searchResults = [];
            await this.refreshAfterAdd(newLineId);
        } catch (e) {
            this.showErrorToast(this.reduceError(e));
        }
    }

    handleToggleRow(event) {
        const rowId = event.currentTarget?.dataset?.rowid;
        if (!rowId) {
            return;
        }
        if (this._collapsedRowIds.has(rowId)) {
            this._collapsedRowIds.delete(rowId);
        } else {
            this._collapsedRowIds.add(rowId);
        }
        this.rebuildDisplay();
    }

    handleMenuSelect(event) {
        const v = event.detail.value;
        const sep = v.indexOf('|');
        if (sep < 0) {
            return;
        }
        const action = v.substring(0, sep);
        const lineId = v.substring(sep + 1);
        if (action === 'detail') {
            this.navigateToDetail(lineId);
        } else if (action === 'delete') {
            this.confirmDelete(lineId);
        } else if (action === 'configure') {
            this.openConfigurator(lineId);
        }
    }

    navigateToDetail(lineId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: lineId,
                objectApiName: 'QuoteLineItem',
                actionName: 'view'
            }
        });
    }

    async confirmDelete(lineId) {
        let ok = false;
        try {
            ok = await LightningConfirm.open({
                message: 'Delete this quote line?',
                variant: 'header',
                label: 'Delete quote line'
            });
        } catch (e) {
            // Fallback for containers where LightningConfirm is not available (e.g. some mobile contexts)
            ok = !!globalThis.confirm?.('Delete this quote line?');
        }
        if (!ok) {
            return;
        }
        try {
            await deleteLine({ quoteLineItemId: lineId });
            this.showSuccessToast('Line deleted');
            await this.fetchLines();
        } catch (e) {
            this.showErrorToast(this.reduceError(e));
        }
    }

    openConfigurator(lineId) {
        const row = (this.displayRows || []).find((r) => r.id === lineId);
        const flowName = (row && row.configFlowApiName) || this.configuratorFlowApiName;
        if (!flowName) {
            this.showErrorToast('No se ha encontrado un Flow de configuración para este producto.');
            return;
        }
        this.currentFlowApiName = flowName;
        this.flowInputVariables = [
            {
                name: this.configuratorFlowInputVariableName,
                type: 'String',
                value: lineId
            }
        ];
        this.showFlowModal = true;
    }

    closeFlowModal() {
        this.showFlowModal = false;
        this.flowInputVariables = [];
        this.currentFlowApiName = '';
    }

    handleFlowStatusChange(event) {
        const status = event.detail.status;
        if (status === 'FINISHED' || status === 'FINISHED_SCREEN') {
            this.closeFlowModal();
            this.fetchLines();
        }
    }

    showSuccessToast(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message,
                variant: 'success'
            })
        );
    }

    showErrorToast(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message,
                variant: 'error',
                mode: 'sticky'
            })
        );
    }

    reduceError(error) {
        if (Array.isArray(error.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        const b = error.body;
        if (b && typeof b === 'object') {
            if (b.message) {
                return b.message;
            }
            if (b.pageErrors && b.pageErrors.length) {
                return b.pageErrors.map((p) => p.message).join(', ');
            }
            if (b.fieldErrors && typeof b.fieldErrors === 'object') {
                const msgs = [];
                Object.keys(b.fieldErrors).forEach((k) => {
                    (b.fieldErrors[k] || []).forEach((fe) => msgs.push(fe.message || fe.statusCode));
                });
                if (msgs.length) {
                    return msgs.join(', ');
                }
            }
            if (b.output && b.output.errors && b.output.errors.length) {
                return b.output.errors.map((e) => e.message).join(', ');
            }
        }
        if (typeof error.message === 'string') {
            return error.message;
        }
        return 'Unknown error';
    }

    get isSmallFormFactor() {
        return this._formFactor === 'Small';
    }

    getLocalStorage() {
        try {
            return globalThis?.localStorage;
        } catch (e) {
            return null;
        }
    }

    hasCollapsedAncestor(row, rowById) {
        let parentId = row.parentQuoteLineItemId;
        while (parentId) {
            if (this._collapsedRowIds.has(parentId)) {
                return true;
            }
            const parent = rowById.get(parentId);
            parentId = parent ? parent.parentQuoteLineItemId : null;
        }
        return false;
    }

    async refreshAfterAdd(newLineId) {
        const maxAttempts = 8;
        for (let i = 0; i < maxAttempts; i += 1) {
            await this.fetchLines();
            const hasNewLine = !newLineId || (this.lineRows || []).some((r) => r.id === newLineId);
            if (hasNewLine || i === maxAttempts - 1) {
                return;
            }
            // RCA line creation can finalize asynchronously; retry briefly before giving up.
            await this.sleep(650);
        }
    }

    sleep(ms) {
        return new Promise((resolve) => {
            setTimeout(resolve, ms);
        });
    }
}