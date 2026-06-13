import { LightningElement, api, track } from 'lwc';
import addQuoteLineWithModel from '@salesforce/apex/MobileTleController.addQuoteLineWithModel';
import addBundleToQuote from '@salesforce/apex/MobileTleController.addBundleToQuote';
import { formatCurrency, reduceError } from 'c/mobileTleUtils';

// Custom Labels
import LBL_NO_NAME from '@salesforce/label/c.MTLE_NoName';
import LBL_BUNDLE from '@salesforce/label/c.MTLE_Bundle';
import LBL_CONFIGURABLE from '@salesforce/label/c.MTLE_Configurable';
import LBL_HIDE_COMPONENTS from '@salesforce/label/c.MTLE_HideComponents';
import LBL_VIEW_N_COMPONENTS from '@salesforce/label/c.MTLE_ViewNComponents';
import LBL_SELLING_MODEL from '@salesforce/label/c.MTLE_SellingModel';
import LBL_QUANTITY from '@salesforce/label/c.MTLE_Quantity';
import LBL_DECREASE_QTY from '@salesforce/label/c.MTLE_DecreaseQty';
import LBL_INCREASE_QTY from '@salesforce/label/c.MTLE_IncreaseQty';
import LBL_ADDING_ELLIPSIS from '@salesforce/label/c.MTLE_AddingEllipsis';
import LBL_ADD_FULL_BUNDLE from '@salesforce/label/c.MTLE_AddFullBundle';
import LBL_ADD_TO_QUOTE from '@salesforce/label/c.MTLE_AddToQuote';

function fmt(template, ...args) {
    return template.replace(/\{(\d+)\}/g, (_, i) => args[i] ?? '');
}

export default class MobileTleProductCard extends LightningElement {
    @api product;
    @api quoteId;
    @api currencyIsoCode = 'EUR';

    @track quantity = 1;
    @track selectedSellingModelId;
    @track adding = false;
    @track showChildren = false;

    // Expose labels to template
    label = {
        bundle: LBL_BUNDLE,
        configurable: LBL_CONFIGURABLE,
        sellingModel: LBL_SELLING_MODEL,
        quantity: LBL_QUANTITY,
        decreaseQty: LBL_DECREASE_QTY,
        increaseQty: LBL_INCREASE_QTY
    };

    get productName() {
        return this.product?.productName || LBL_NO_NAME;
    }

    get productCode() {
        return this.product?.productCode || '';
    }

    get productDescription() {
        return this.product?.productDescription || '';
    }

    get hasDescription() {
        return !!this.product?.productDescription;
    }

    get hasImage() {
        return !!this.product?.productImageUrl;
    }

    get productImage() {
        return this.product?.productImageUrl;
    }

    get displayPrice() {
        const iso = this.product?.currencyIsoCode || this.currencyIsoCode;
        return formatCurrency(this.product?.unitPrice, iso);
    }

    get sellingModelLabel() {
        return this.product?.sellingModelName || '';
    }

    get hasSellingModels() {
        return this.product?.sellingModels && this.product.sellingModels.length > 0;
    }

    get sellingModelOptions() {
        return (this.product?.sellingModels || []).map((m) => ({
            label: `${m.name} (${m.sellingModelType || ''})`,
            value: m.id
        }));
    }

    get addButtonLabel() {
        if (this.adding) return LBL_ADDING_ELLIPSIS;
        return this.isBundle ? LBL_ADD_FULL_BUNDLE : LBL_ADD_TO_QUOTE;
    }

    get addButtonDisabled() {
        return this.adding || this.quantity < 1;
    }

    // ─── Bundle & configurable getters ─────────────────────────────────────

    get isBundle() {
        return this.product?.isBundle === true;
    }

    get isConfigurable() {
        return this.product?.isConfigurable === true;
    }

    get bundleChildCount() {
        return this.product?.bundleChildCount || 0;
    }

    get hasBundleChildren() {
        return this.product?.bundleChildren && this.product.bundleChildren.length > 0;
    }

    get bundleChildren() {
        return this.product?.bundleChildren || [];
    }

    get showBadges() {
        return this.isBundle || this.isConfigurable;
    }

    get childrenToggleLabel() {
        return this.showChildren
            ? LBL_HIDE_COMPONENTS
            : fmt(LBL_VIEW_N_COMPONENTS, this.bundleChildCount);
    }

    get childrenToggleIcon() {
        return this.showChildren ? 'utility:chevronup' : 'utility:chevrondown';
    }

    // ─── Lifecycle ─────────────────────────────────────────────────────────

    connectedCallback() {
        // Pre-select default selling model
        if (this.product?.defaultSellingModelId) {
            this.selectedSellingModelId = this.product.defaultSellingModelId;
        } else if (this.product?.sellingModels?.length > 0) {
            this.selectedSellingModelId = this.product.sellingModels[0].id;
        }
    }

    // ─── Event handlers ────────────────────────────────────────────────────

    handleSellingModelChange(event) {
        this.selectedSellingModelId = event.detail.value;
    }

    handleQtyMinus() {
        if (this.quantity > 1) this.quantity -= 1;
    }

    handleQtyPlus() {
        this.quantity += 1;
    }

    handleQtyChange(event) {
        const val = parseInt(event.target.value, 10);
        if (!isNaN(val) && val > 0) {
            this.quantity = val;
        }
    }

    handleToggleChildren() {
        this.showChildren = !this.showChildren;
    }

    async handleAdd() {
        if (this.adding) return;
        this.adding = true;
        try {
            let newLineId;
            if (this.isBundle) {
                // Use bundle-aware method that adds parent + all children
                newLineId = await addBundleToQuote({
                    quoteId: this.quoteId,
                    product2Id: this.product.product2Id,
                    pricebookEntryId: this.product.pricebookEntryId,
                    unitPrice: this.product.unitPrice,
                    quantity: this.quantity,
                    sellingModelId: this.selectedSellingModelId || null
                });
            } else {
                newLineId = await addQuoteLineWithModel({
                    quoteId: this.quoteId,
                    product2Id: this.product.product2Id,
                    pricebookEntryId: this.product.pricebookEntryId,
                    unitPrice: this.product.unitPrice,
                    quantity: this.quantity,
                    sellingModelId: this.selectedSellingModelId || null
                });
            }
            this.dispatchEvent(new CustomEvent('productadded', {
                detail: {
                    productName: this.productName,
                    quantity: this.quantity,
                    newLineId,
                    isBundle: this.isBundle,
                    childCount: this.bundleChildCount
                },
                bubbles: true,
                composed: true
            }));
            // Reset
            this.quantity = 1;
        } catch (e) {
            this.dispatchEvent(new CustomEvent('productadderror', {
                detail: {
                    productName: this.productName,
                    errorMessage: reduceError(e)
                },
                bubbles: true,
                composed: true
            }));
        } finally {
            this.adding = false;
        }
    }
}
