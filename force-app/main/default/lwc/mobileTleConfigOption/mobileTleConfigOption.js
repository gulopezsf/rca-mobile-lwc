import { LightningElement, api, track } from 'lwc';
import { formatCurrency } from 'c/mobileTleUtils';

// Custom Labels
import LBL_QUANTITY from '@salesforce/label/c.MTLE_Quantity';
import LBL_DECREASE_QTY from '@salesforce/label/c.MTLE_DecreaseQty';
import LBL_INCREASE_QTY from '@salesforce/label/c.MTLE_IncreaseQty';
import LBL_REQUIRED from '@salesforce/label/c.MTLE_CfgRequired';
import LBL_NESTED_BUNDLE from '@salesforce/label/c.MTLE_CfgNestedBundle';
import LBL_EXPAND_OPTIONS from '@salesforce/label/c.MTLE_CfgExpandOptions';
import LBL_COLLAPSE_OPTIONS from '@salesforce/label/c.MTLE_CfgCollapseOptions';

export default class MobileTleConfigOption extends LightningElement {
    @api option;
    @api currencyIsoCode = 'EUR';
    @api nestingLevel = 0;
    @api disabled = false;

    @track showNestedGroups = false;

    label = {
        quantity: LBL_QUANTITY,
        decreaseQty: LBL_DECREASE_QTY,
        increaseQty: LBL_INCREASE_QTY,
        required: LBL_REQUIRED,
        nestedBundle: LBL_NESTED_BUNDLE,
        expandOptions: LBL_EXPAND_OPTIONS,
        collapseOptions: LBL_COLLAPSE_OPTIONS
    };

    // ─── Getters ──────────────────────────────────────────────────────────

    get optionName() {
        return this.option?.childProductName || '';
    }

    get optionCode() {
        return this.option?.childProductCode || '';
    }

    get isSelected() {
        return this.option?.isSelected === true;
    }

    get isRequired() {
        return this.option?.isRequired === true;
    }

    get isQuantityEditable() {
        return this.option?.isQuantityEditable === true && this.isSelected;
    }

    get currentQuantity() {
        return this.option?.currentQuantity ?? this.option?.defaultQuantity ?? 1;
    }

    get minQuantity() {
        return this.option?.minQuantity ?? 0;
    }

    get maxQuantity() {
        return this.option?.maxQuantity ?? 999999;
    }

    get displayPrice() {
        return formatCurrency(this.option?.currentUnitPrice, this.currencyIsoCode);
    }

    get hasPrice() {
        return this.option?.currentUnitPrice != null && this.option.currentUnitPrice > 0;
    }

    get isNestedBundle() {
        return this.option?.isNestedBundle === true;
    }

    get hasChildGroups() {
        return this.isNestedBundle && this.option?.childGroups?.length > 0;
    }

    get childGroups() {
        return this.option?.childGroups || [];
    }

    get childNestingLevel() {
        return (this.nestingLevel || 0) + 1;
    }

    get canDecrease() {
        return this.isSelected && this.isQuantityEditable && this.currentQuantity > this.minQuantity;
    }

    get canIncrease() {
        return this.isSelected && this.isQuantityEditable && this.currentQuantity < this.maxQuantity;
    }

    get decreaseDisabled() {
        return !this.canDecrease;
    }

    get increaseDisabled() {
        return !this.canIncrease;
    }

    get checkboxDisabled() {
        return this.isRequired || this.disabled;
    }

    get nestedToggleLabel() {
        return this.showNestedGroups ? this.label.collapseOptions : this.label.expandOptions;
    }

    get nestedToggleIcon() {
        return this.showNestedGroups ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get cardClass() {
        let cls = 'mtle-cfg-option';
        if (this.isSelected) cls += ' mtle-cfg-option--selected';
        if (this.isRequired) cls += ' mtle-cfg-option--required';
        return cls;
    }

    // ─── Event Handlers ───────────────────────────────────────────────────

    handleToggle() {
        if (this.isRequired) return; // cannot unselect required
        this.dispatchEvent(new CustomEvent('optionchange', {
            detail: {
                productRelatedComponentId: this.option.productRelatedComponentId,
                childProduct2Id: this.option.childProduct2Id,
                action: this.isSelected ? 'REMOVE' : 'ADD',
                quantity: this.option.defaultQuantity || 1,
                pricebookEntryId: this.option.pricebookEntryId,
                unitPrice: this.option.currentUnitPrice
            },
            bubbles: true,
            composed: true
        }));
    }

    handleQtyMinus() {
        if (!this.canDecrease) return;
        const newQty = this.currentQuantity - 1;
        this._fireQuantityChange(newQty);
    }

    handleQtyPlus() {
        if (!this.canIncrease) return;
        const newQty = this.currentQuantity + 1;
        this._fireQuantityChange(newQty);
    }

    handleQtyInput(event) {
        const val = parseFloat(event.target.value);
        if (isNaN(val)) return;
        const clamped = Math.max(this.minQuantity, Math.min(this.maxQuantity, val));
        this._fireQuantityChange(clamped);
    }

    handleToggleNested() {
        this.showNestedGroups = !this.showNestedGroups;
    }

    // Relay nested group changes upward
    handleNestedGroupChange(event) {
        // Just let it bubble — composed: true on optionchange already does this
    }

    // ─── Private ──────────────────────────────────────────────────────────

    _fireQuantityChange(newQty) {
        this.dispatchEvent(new CustomEvent('optionchange', {
            detail: {
                productRelatedComponentId: this.option.productRelatedComponentId,
                childProduct2Id: this.option.childProduct2Id,
                action: 'UPDATE',
                quantity: newQty,
                pricebookEntryId: this.option.pricebookEntryId,
                unitPrice: this.option.currentUnitPrice
            },
            bubbles: true,
            composed: true
        }));
    }
}
