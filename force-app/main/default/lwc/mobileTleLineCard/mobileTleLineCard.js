import { LightningElement, api, track } from 'lwc';
import { formatCurrency } from 'c/mobileTleUtils';

// Custom Labels
import LBL_NO_NAME from '@salesforce/label/c.MTLE_NoName';
import LBL_ACTIONS from '@salesforce/label/c.MTLE_Actions';
import LBL_LINE_ACTIONS from '@salesforce/label/c.MTLE_LineActions';
import LBL_EDIT_QTY from '@salesforce/label/c.MTLE_EditQuantity';
import LBL_EDIT_DISCOUNT from '@salesforce/label/c.MTLE_EditDiscount';
import LBL_LESS from '@salesforce/label/c.MTLE_Less';
import LBL_MORE from '@salesforce/label/c.MTLE_More';
import LBL_QTY_SHORT from '@salesforce/label/c.MTLE_QtyShort';
import LBL_DISCOUNT_SHORT from '@salesforce/label/c.MTLE_DiscountShort';
import LBL_SAVE from '@salesforce/label/c.MTLE_Save';
import LBL_CANCEL from '@salesforce/label/c.MTLE_Cancel';

export default class MobileTleLineCard extends LightningElement {
    @api line;
    @api currencyIsoCode = 'EUR';

    @track editingQty = false;
    @track editQtyValue;
    @track editingDiscount = false;
    @track editDiscountValue;

    // Expose labels to template
    label = {
        actions: LBL_ACTIONS,
        lineActions: LBL_LINE_ACTIONS,
        editQty: LBL_EDIT_QTY,
        editDiscount: LBL_EDIT_DISCOUNT,
        less: LBL_LESS,
        more: LBL_MORE,
        qtyShort: LBL_QTY_SHORT,
        discountShort: LBL_DISCOUNT_SHORT,
        save: LBL_SAVE,
        cancel: LBL_CANCEL
    };

    get cardClass() {
        const base = 'mtle-card';
        return this.line?.isChild ? `${base} mtle-card-child` : base;
    }

    get productName() {
        return this.line?.productName || LBL_NO_NAME;
    }

    get productImage() {
        return this.line?.productImageUrl;
    }

    get hasImage() {
        return !!this.line?.productImageUrl;
    }

    get displayQuantity() {
        return this.line?.quantity != null ? String(this.line.quantity) : '—';
    }

    get displayDiscount() {
        if (this.line?.discount == null || this.line.discount === 0) return null;
        return `-${this.line.discount}%`;
    }

    get hasDiscount() {
        return this.line?.discount != null && this.line.discount > 0;
    }

    get displayNetUnitPrice() {
        const iso = this.line?.currencyIsoCode || this.currencyIsoCode;
        return formatCurrency(this.line?.netUnitPrice, iso);
    }

    get displayNetTotalPrice() {
        const iso = this.line?.currencyIsoCode || this.currencyIsoCode;
        return formatCurrency(this.line?.netTotalPrice, iso);
    }

    get sellingModelLabel() {
        return this.line?.sellingModelType || '';
    }

    get hasSellingModel() {
        return !!this.line?.sellingModelType;
    }

    get isBundleParent() {
        return this.line?.isBundleParent === true;
    }

    // ─── Actions ────────────────────────────────────────────────────────────

    handleActionTap() {
        this.dispatchEvent(new CustomEvent('action', {
            detail: {
                lineId: this.line.id,
                line: this.line
            }
        }));
    }

    // ─── Inline edit: Quantity ───────────────────────────────────────────────

    handleQtyTap() {
        this.editQtyValue = this.line?.quantity != null ? this.line.quantity : 1;
        this.editingQty = true;
    }

    handleQtyMinus() {
        const v = Number(this.editQtyValue) || 1;
        if (v > 1) this.editQtyValue = v - 1;
    }

    handleQtyPlus() {
        const v = Number(this.editQtyValue) || 0;
        this.editQtyValue = v + 1;
    }

    handleQtyChange(event) {
        this.editQtyValue = event.target.value;
    }

    handleQtySave() {
        const val = Number(this.editQtyValue);
        if (isNaN(val) || val <= 0) {
            this.editingQty = false;
            return;
        }
        this.editingQty = false;
        if (val !== this.line?.quantity) {
            this.dispatchEvent(new CustomEvent('inlineedit', {
                detail: {
                    lineId: this.line.id,
                    fieldName: 'Quantity',
                    value: val
                }
            }));
        }
    }

    handleQtyCancel() {
        this.editingQty = false;
    }

    // ─── Inline edit: Discount ──────────────────────────────────────────────

    handleDiscountTap() {
        this.editDiscountValue = this.line?.discount != null ? this.line.discount : 0;
        this.editingDiscount = true;
    }

    handleDiscountChange(event) {
        this.editDiscountValue = event.target.value;
    }

    handleDiscountSave() {
        const val = Number(this.editDiscountValue);
        if (isNaN(val) || val < 0 || val > 100) {
            this.editingDiscount = false;
            return;
        }
        this.editingDiscount = false;
        if (val !== this.line?.discount) {
            this.dispatchEvent(new CustomEvent('inlineedit', {
                detail: {
                    lineId: this.line.id,
                    fieldName: 'Discount',
                    value: val
                }
            }));
        }
    }

    handleDiscountCancel() {
        this.editingDiscount = false;
    }
}
