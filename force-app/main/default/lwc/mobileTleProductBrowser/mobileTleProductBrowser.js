import { LightningElement, api, track } from 'lwc';
import getProductCatalogs from '@salesforce/apex/MobileTleController.getProductCatalogs';
import getProductCategoriesForCatalog from '@salesforce/apex/MobileTleController.getProductCategoriesForCatalog';
import getDefaultCatalogContext from '@salesforce/apex/MobileTleController.getDefaultCatalogContext';
import getProductsPage from '@salesforce/apex/MobileTleController.getProductsPage';
import searchProducts from '@salesforce/apex/MobileTleController.searchProducts';
import getPricebooks from '@salesforce/apex/MobileTleController.getPricebooks';
import assignPricebook from '@salesforce/apex/MobileTleController.assignPricebook';
import { reduceError } from 'c/mobileTleUtils';

// Custom Labels
import LBL_ADD_PRODUCT from '@salesforce/label/c.MTLE_AddProduct';
import LBL_CLOSE from '@salesforce/label/c.MTLE_Close';
import LBL_CANCEL from '@salesforce/label/c.MTLE_Cancel';
import LBL_LOADING from '@salesforce/label/c.MTLE_Loading';
import LBL_NO_PB_WARNING from '@salesforce/label/c.MTLE_NoPricebookWarning';
import LBL_SELECT_PB from '@salesforce/label/c.MTLE_SelectPricebook';
import LBL_CHOOSE_PB from '@salesforce/label/c.MTLE_ChoosePricebook';
import LBL_ASSIGN from '@salesforce/label/c.MTLE_Assign';
import LBL_SEARCH_PRODUCT from '@salesforce/label/c.MTLE_SearchProduct';
import LBL_SEARCH_PLACEHOLDER from '@salesforce/label/c.MTLE_SearchProductPlaceholder';
import LBL_CATALOG from '@salesforce/label/c.MTLE_Catalog';
import LBL_SELECT_CATALOG from '@salesforce/label/c.MTLE_SelectCatalog';
import LBL_CATEGORY from '@salesforce/label/c.MTLE_Category';
import LBL_SELECT_CATEGORY from '@salesforce/label/c.MTLE_SelectCategory';
import LBL_LIST_PRODUCTS from '@salesforce/label/c.MTLE_ListProducts';
import LBL_SEARCHING from '@salesforce/label/c.MTLE_Searching';
import LBL_PREVIOUS from '@salesforce/label/c.MTLE_Previous';
import LBL_NEXT from '@salesforce/label/c.MTLE_Next';
import LBL_SELECT_CAT_AND_CATEG from '@salesforce/label/c.MTLE_SelectCatalogAndCategory';
import LBL_SELECT_CAT_AND_CATEG_SHORT from '@salesforce/label/c.MTLE_SelectCatalogAndCategoryShort';
import LBL_PAGE_N_OF_M from '@salesforce/label/c.MTLE_PageNofM';

function fmt(template, ...args) {
    return template.replace(/\{(\d+)\}/g, (_, i) => args[i] ?? '');
}

const STORAGE_KEY_PREFIX = 'mobileTle.catalogCtx.';

export default class MobileTleProductBrowser extends LightningElement {
    @api quoteId;
    @api quoteContext;
    @api defaultPageSize = 6;

    @track loading = true;
    @track catalogRows = [];
    @track categoryRows = [];
    @track selectedCatalogId;
    @track selectedCategoryId;
    @track selectedCatalogName = '';
    @track selectedCategoryName = '';
    @track searchTerm = '';
    @track searchLoading = false;
    @track products = [];
    @track nextPageToken;
    @track totalCount = 0;
    @track currentPage = 1;

    // Pricebook picker
    @track showPricebookPicker = false;
    @track pricebooks = [];
    @track selectedPricebookId;

    _searchDebounceId;
    _categoriesLoading = false;

    // Expose labels to template
    label = {
        addProduct: LBL_ADD_PRODUCT,
        close: LBL_CLOSE,
        cancel: LBL_CANCEL,
        loading: LBL_LOADING,
        noPbWarning: LBL_NO_PB_WARNING,
        selectPb: LBL_SELECT_PB,
        choosePb: LBL_CHOOSE_PB,
        assign: LBL_ASSIGN,
        searchProduct: LBL_SEARCH_PRODUCT,
        searchPlaceholder: LBL_SEARCH_PLACEHOLDER,
        catalog: LBL_CATALOG,
        selectCatalog: LBL_SELECT_CATALOG,
        category: LBL_CATEGORY,
        selectCategory: LBL_SELECT_CATEGORY,
        listProducts: LBL_LIST_PRODUCTS,
        searching: LBL_SEARCHING,
        previous: LBL_PREVIOUS,
        next: LBL_NEXT,
        selectCatAndCateg: LBL_SELECT_CAT_AND_CATEG,
        selectCatAndCategShort: LBL_SELECT_CAT_AND_CATEG_SHORT
    };

    get hasPricebook() {
        return this.quoteContext?.hasPricebook;
    }

    get hasProducts() {
        return this.products && this.products.length > 0;
    }

    get catalogComboOptions() {
        return (this.catalogRows || []).map((r) => ({ label: r.name, value: r.id }));
    }

    get categoryComboOptions() {
        return (this.categoryRows || []).map((r) => ({ label: r.name, value: r.id }));
    }

    get categoryPickerDisabled() {
        return !this.selectedCatalogId || this._categoriesLoading;
    }

    get catalogContextSummary() {
        if (this.selectedCatalogName && this.selectedCategoryName) {
            return `${this.selectedCatalogName} · ${this.selectedCategoryName}`;
        }
        return LBL_SELECT_CAT_AND_CATEG_SHORT;
    }

    get pageInfo() {
        if (this.totalCount == null || this.totalCount === 0) return '';
        const totalPages = Math.ceil(this.totalCount / this.defaultPageSize);
        return fmt(LBL_PAGE_N_OF_M, this.currentPage, totalPages);
    }

    get hasNextPage() {
        return !!this.nextPageToken;
    }

    get hasPrevPage() {
        return this.currentPage > 1;
    }

    get pricebookComboOptions() {
        return (this.pricebooks || []).map((r) => ({ label: r.name, value: r.id }));
    }

    get assignButtonDisabled() {
        return !this.selectedPricebookId;
    }

    get listButtonDisabled() {
        return !this.selectedCategoryId;
    }

    get prevPageDisabled() {
        return !this.hasPrevPage;
    }

    get nextPageDisabled() {
        return !this.hasNextPage;
    }

    // ─── Lifecycle ──────────────────────────────────────────────────────────

    async connectedCallback() {
        this.loading = true;
        try {
            if (!this.hasPricebook) {
                await this.loadPricebooks();
                this.showPricebookPicker = true;
                this.loading = false;
                return;
            }
            await this.initCatalogContext();
        } catch (e) {
            // non-fatal
        } finally {
            this.loading = false;
        }
    }

    async initCatalogContext() {
        // Try localStorage first
        try {
            const raw = globalThis?.localStorage?.getItem(STORAGE_KEY_PREFIX + this.quoteId);
            if (raw) {
                const ctx = JSON.parse(raw);
                if (ctx?.categoryId) {
                    this.selectedCatalogId = ctx.catalogId;
                    this.selectedCategoryId = ctx.categoryId;
                    this.selectedCatalogName = ctx.catalogName || '';
                    this.selectedCategoryName = ctx.categoryName || '';
                    await this.loadCatalogs();
                    await this.loadCategories(this.selectedCatalogId);
                    await this.loadProducts();
                    return;
                }
            }
        } catch (e) { /* ignore */ }

        // Try default from org
        try {
            const def = await getDefaultCatalogContext();
            if (def?.catalogId) {
                this.selectedCatalogId = def.catalogId;
                this.selectedCategoryId = def.categoryId;
                this.selectedCatalogName = def.catalogName || '';
                this.selectedCategoryName = def.categoryName || '';
                this.persistContext();
            }
        } catch (e) { /* ignore */ }

        await this.loadCatalogs();
        if (this.selectedCatalogId) {
            await this.loadCategories(this.selectedCatalogId);
            if (this.selectedCategoryId) {
                await this.loadProducts();
            }
        }
    }

    // ─── Data loading ───────────────────────────────────────────────────────

    async loadCatalogs() {
        const rows = await getProductCatalogs();
        this.catalogRows = rows || [];
    }

    async loadCategories(catalogId) {
        if (!catalogId) {
            this.categoryRows = [];
            return;
        }
        this._categoriesLoading = true;
        try {
            const rows = await getProductCategoriesForCatalog({ catalogId });
            this.categoryRows = rows || [];
        } finally {
            this._categoriesLoading = false;
        }
    }

    async loadProducts() {
        if (!this.selectedCategoryId) return;
        this.searchLoading = true;
        try {
            const page = await getProductsPage({
                quoteId: this.quoteId,
                catalogId: this.selectedCatalogId,
                categoryId: this.selectedCategoryId,
                pageToken: null,
                pageSize: this.defaultPageSize
            });
            this.products = page.products || [];
            this.nextPageToken = page.nextPageToken;
            this.totalCount = page.totalCount;
            this.currentPage = 1;
        } catch (e) {
            this.products = [];
            this.dispatchEvent(new CustomEvent('productadderror', {
                detail: { productName: '', errorMessage: reduceError(e) }
            }));
        } finally {
            this.searchLoading = false;
        }
    }

    async loadPricebooks() {
        const rows = await getPricebooks();
        this.pricebooks = rows || [];
    }

    // ─── Event handlers ─────────────────────────────────────────────────────

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    async handleCatalogChange(event) {
        this.selectedCatalogId = event.detail.value;
        const cat = this.catalogRows.find((r) => r.id === this.selectedCatalogId);
        this.selectedCatalogName = cat ? cat.name : '';
        this.selectedCategoryId = undefined;
        this.selectedCategoryName = '';
        this.products = [];
        await this.loadCategories(this.selectedCatalogId);
    }

    async handleCategoryChange(event) {
        this.selectedCategoryId = event.detail.value;
        const cat = this.categoryRows.find((r) => r.id === this.selectedCategoryId);
        this.selectedCategoryName = cat ? cat.name : '';
        this.persistContext();
        await this.loadProducts();
    }

    handleSearchInput(event) {
        this.searchTerm = event.target?.value ?? '';
        clearTimeout(this._searchDebounceId);
        const term = (this.searchTerm || '').trim();
        if (term.length < 2) {
            if (this.selectedCategoryId) this.loadProducts();
            return;
        }
        this.searchLoading = true;
        this._searchDebounceId = setTimeout(() => this.runSearch(term), 320);
    }

    async runSearch(term) {
        try {
            const page = await searchProducts({
                quoteId: this.quoteId,
                searchTerm: term,
                catalogId: this.selectedCatalogId,
                categoryId: this.selectedCategoryId,
                pageSize: 25
            });
            this.products = page.products || [];
            this.nextPageToken = page.nextPageToken;
            this.totalCount = page.totalCount;
            this.currentPage = 1;
        } catch (e) {
            this.products = [];
        } finally {
            this.searchLoading = false;
        }
    }

    async handleListProducts() {
        this.searchTerm = '';
        await this.loadProducts();
    }

    async handleNextPage() {
        if (!this.nextPageToken) return;
        this.searchLoading = true;
        try {
            const page = await getProductsPage({
                quoteId: this.quoteId,
                catalogId: this.selectedCatalogId,
                categoryId: this.selectedCategoryId,
                pageToken: this.nextPageToken,
                pageSize: this.defaultPageSize
            });
            this.products = page.products || [];
            this.nextPageToken = page.nextPageToken;
            this.totalCount = page.totalCount;
            this.currentPage += 1;
        } finally {
            this.searchLoading = false;
        }
    }

    async handlePrevPage() {
        if (this.currentPage <= 1) return;
        // For SOQL offset, calculate previous token
        const prevOffset = Math.max(0, ((this.currentPage - 2) * this.defaultPageSize));
        this.searchLoading = true;
        try {
            const page = await getProductsPage({
                quoteId: this.quoteId,
                catalogId: this.selectedCatalogId,
                categoryId: this.selectedCategoryId,
                pageToken: String(prevOffset),
                pageSize: this.defaultPageSize
            });
            this.products = page.products || [];
            this.nextPageToken = page.nextPageToken;
            this.totalCount = page.totalCount;
            this.currentPage -= 1;
        } finally {
            this.searchLoading = false;
        }
    }

    handleProductAdded(event) {
        // Relay from product card
        this.dispatchEvent(new CustomEvent('productadded', {
            detail: event.detail
        }));
    }

    handleProductAddError(event) {
        this.dispatchEvent(new CustomEvent('productadderror', {
            detail: event.detail
        }));
    }

    // ─── Pricebook picker ───────────────────────────────────────────────────

    handlePricebookChange(event) {
        this.selectedPricebookId = event.detail.value;
    }

    async handleAssignPricebook() {
        if (!this.selectedPricebookId) return;
        try {
            this.loading = true;
            await assignPricebook({
                quoteId: this.quoteId,
                pricebook2Id: this.selectedPricebookId
            });
            this.showPricebookPicker = false;
            // Refresh quote context in parent
            this.quoteContext = { ...this.quoteContext, hasPricebook: true, pricebook2Id: this.selectedPricebookId };
            await this.initCatalogContext();
        } catch (e) {
            this.dispatchEvent(new CustomEvent('productadderror', {
                detail: { productName: '', errorMessage: reduceError(e) }
            }));
        } finally {
            this.loading = false;
        }
    }

    // ─── Helpers ────────────────────────────────────────────────────────────

    persistContext() {
        try {
            globalThis?.localStorage?.setItem(
                STORAGE_KEY_PREFIX + this.quoteId,
                JSON.stringify({
                    catalogId: this.selectedCatalogId,
                    categoryId: this.selectedCategoryId,
                    catalogName: this.selectedCatalogName,
                    categoryName: this.selectedCategoryName
                })
            );
        } catch (e) { /* quota */ }
    }
}
