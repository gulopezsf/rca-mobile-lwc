import { LightningElement, api, track } from 'lwc';

// Custom Labels
import LBL_SELECT_BETWEEN from '@salesforce/label/c.MTLE_CfgSelectBetween';
import LBL_SELECT_EXACTLY from '@salesforce/label/c.MTLE_CfgSelectExactly';
import LBL_SELECT_UP_TO from '@salesforce/label/c.MTLE_CfgSelectUpTo';
import LBL_SELECT_AT_LEAST from '@salesforce/label/c.MTLE_CfgSelectAtLeast';
import LBL_SELECTED_N from '@salesforce/label/c.MTLE_CfgSelectedCount';
import LBL_VALIDATION_MIN from '@salesforce/label/c.MTLE_CfgValidationMin';
import LBL_VALIDATION_MAX from '@salesforce/label/c.MTLE_CfgValidationMax';

function fmt(template, ...args) {
    return template.replace(/\{(\d+)\}/g, (_, i) => args[i] ?? '');
}

export default class MobileTleConfigGroup extends LightningElement {
    @api group;
    @api currencyIsoCode = 'EUR';
    @api nestingLevel = 0;

    @track collapsed = false;

    label = {
        selectBetween: LBL_SELECT_BETWEEN,
        selectExactly: LBL_SELECT_EXACTLY,
        selectUpTo: LBL_SELECT_UP_TO,
        selectAtLeast: LBL_SELECT_AT_LEAST,
        selectedCount: LBL_SELECTED_N,
        validationMin: LBL_VALIDATION_MIN,
        validationMax: LBL_VALIDATION_MAX
    };

    // ─── Getters ──────────────────────────────────────────────────────────

    get groupName() {
        return this.group?.groupName || '';
    }

    get options() {
        return this.group?.options || [];
    }

    get minSelections() {
        return this.group?.minSelections ?? 0;
    }

    get maxSelections() {
        return this.group?.maxSelections ?? 999;
    }

    get selectedCount() {
        return this.options.filter((o) => o.isSelected).length;
    }

    get selectionHint() {
        const min = this.minSelections;
        const max = this.maxSelections;
        if (min > 0 && max < 999 && min === max) {
            return fmt(this.label.selectExactly, min);
        }
        if (min > 0 && max < 999) {
            return fmt(this.label.selectBetween, min, max);
        }
        if (min > 0) {
            return fmt(this.label.selectAtLeast, min);
        }
        if (max < 999) {
            return fmt(this.label.selectUpTo, max);
        }
        return '';
    }

    get selectedCountLabel() {
        return fmt(this.label.selectedCount, this.selectedCount);
    }

    get hasValidationError() {
        return this.validationMessage !== '';
    }

    get validationMessage() {
        const count = this.selectedCount;
        if (this.minSelections > 0 && count < this.minSelections) {
            return fmt(this.label.validationMin, this.minSelections);
        }
        if (this.maxSelections < 999 && count > this.maxSelections) {
            return fmt(this.label.validationMax, this.maxSelections);
        }
        return '';
    }

    get groupClass() {
        let cls = 'mtle-cfg-group';
        if (this.hasValidationError) cls += ' mtle-cfg-group--error';
        if (this.nestingLevel > 0) cls += ' mtle-cfg-group--nested';
        return cls;
    }

    get headerIcon() {
        return this.collapsed ? 'utility:chevronright' : 'utility:chevrondown';
    }

    get showOptions() {
        return !this.collapsed;
    }

    get counterClass() {
        let cls = 'mtle-cfg-group-counter';
        if (this.hasValidationError) cls += ' mtle-cfg-group-counter--error';
        return cls;
    }

    // ─── Public validation API (called by parent) ─────────────────────────

    @api
    validate() {
        const errors = [];
        const count = this.selectedCount;
        if (this.minSelections > 0 && count < this.minSelections) {
            errors.push({
                groupName: this.groupName,
                message: fmt(this.label.validationMin, this.minSelections)
            });
        }
        if (this.maxSelections < 999 && count > this.maxSelections) {
            errors.push({
                groupName: this.groupName,
                message: fmt(this.label.validationMax, this.maxSelections)
            });
        }
        // Validate nested groups inside selected options
        const nestedGroupEls = this.template.querySelectorAll('c-mobile-tle-config-group');
        nestedGroupEls.forEach((el) => {
            const nested = el.validate();
            if (nested && nested.length) {
                errors.push(...nested);
            }
        });
        return errors;
    }

    // ─── Event Handlers ───────────────────────────────────────────────────

    handleToggleCollapse() {
        this.collapsed = !this.collapsed;
    }

    // Option changes bubble up via composed events — no handler needed here
}
