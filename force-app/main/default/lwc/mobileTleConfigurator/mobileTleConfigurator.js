import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { reduceError, formatCurrency } from 'c/mobileTleUtils';
import loadBundleConfiguration from '@salesforce/apex/MobileTleController.loadBundleConfiguration';
import saveBundleConfiguration from '@salesforce/apex/MobileTleController.saveBundleConfiguration';
// Custom Labels
import LBL_CONFIGURE_PRODUCT from '@salesforce/label/c.MTLE_ConfigureProduct';
import LBL_CLOSE_CONFIGURATOR from '@salesforce/label/c.MTLE_CloseConfigurator';
import LBL_CLOSE from '@salesforce/label/c.MTLE_Close';
import LBL_SAVE from '@salesforce/label/c.MTLE_Save';
import LBL_LOADING from '@salesforce/label/c.MTLE_Loading';
import LBL_SUCCESS from '@salesforce/label/c.MTLE_Success';
import LBL_ERROR from '@salesforce/label/c.MTLE_Error';
import LBL_CFG_SAVING from '@salesforce/label/c.MTLE_CfgSaving';
import LBL_CFG_SAVED from '@salesforce/label/c.MTLE_CfgSaved';
import LBL_CFG_NO_CHANGES from '@salesforce/label/c.MTLE_CfgNoChanges';
import LBL_CFG_VALIDATION_ERRORS from '@salesforce/label/c.MTLE_CfgValidationErrors';
import LBL_CFG_LOAD_ERROR from '@salesforce/label/c.MTLE_CfgLoadError';
import LBL_CFG_ATTR_VALIDATION from '@salesforce/label/c.MTLE_CfgAttrValidationFailed';
import LBL_CFG_ATTR_SAVING from '@salesforce/label/c.MTLE_CfgAttrSaving';

export default class MobileTleConfigurator extends LightningElement {
    @api quoteId;
    @api lineId;

    @track loading = true;
    @track saving = false;
    @track error;

    // Bundle configuration state from Apex
    @track configState;

    // Working copy of groups with user changes applied
    @track workingGroups = [];

    // Working copy of parent attributes
    @track workingAttributes = [];

    // Price-impacting attribute change flag
    @track hasPriceImpactingChanges = false;

    // Repricing spinner flag
    @track repricing = false;

    // Map of original state for diff computation
    _originalSnapshot = new Map(); // key: productRelatedComponentId → { isSelected, quantity }

    label = {
        configureProduct: LBL_CONFIGURE_PRODUCT,
        closeConfigurator: LBL_CLOSE_CONFIGURATOR,
        close: LBL_CLOSE,
        save: LBL_SAVE,
        loading: LBL_LOADING,
        saving: LBL_CFG_SAVING
    };

    // ─── Getters ──────────────────────────────────────────────────────────

    get productName() {
        return this.configState?.productName || '';
    }

    get parentQuantity() {
        return this.configState?.quantity ?? 1;
    }

    get parentPrice() {
        return formatCurrency(
            this.configState?.unitPrice,
            this.configState?.currencyIsoCode || 'EUR'
        );
    }

    get currencyIsoCode() {
        return this.configState?.currencyIsoCode || 'EUR';
    }

    get hasGroups() {
        return this.workingGroups && this.workingGroups.length > 0;
    }

    get hasAttributes() {
        return this.workingAttributes && this.workingAttributes.length > 0;
    }

    get hasContent() {
        return this.hasGroups || this.hasAttributes;
    }

    get saveLabel() {
        if (this.saving && this.hasPriceImpactingChanges) return LBL_CFG_ATTR_SAVING;
        return this.saving ? LBL_CFG_SAVING : LBL_SAVE;
    }

    get showRepriceMessage() {
        return this.hasPriceImpactingChanges && !this.saving;
    }

    get saveDisabled() {
        return this.saving || this.loading;
    }

    get hasChanges() {
        return this._computeChanges().length > 0;
    }

    // ─── Lifecycle ────────────────────────────────────────────────────────

    connectedCallback() {
        this._loadConfig();
    }

    // ─── Load configuration ───────────────────────────────────────────────

    async _loadConfig() {
        this.loading = true;
        this.error = undefined;
        try {
            const state = await loadBundleConfiguration({
                quoteId: this.quoteId,
                quoteLineItemId: this.lineId
            });
            this.configState = state;
            this.workingGroups = this._deepCloneGroups(state.groups || []);
            this.workingAttributes = JSON.parse(JSON.stringify(state.attributes || []));
            this._snapshotOriginal(this.workingGroups);
        } catch (e) {
            this.error = reduceError(e);
            this.toast(LBL_ERROR, LBL_CFG_LOAD_ERROR + ': ' + this.error, 'error');
        } finally {
            this.loading = false;
        }
    }

    // ─── Option change handler (bubbles up from child components) ─────────

    handleOptionChange(event) {
        event.stopPropagation();
        const { productRelatedComponentId, action, quantity } = event.detail;

        this.workingGroups = this._applyOptionChange(
            this.workingGroups,
            productRelatedComponentId,
            action,
            quantity
        );
    }

    // ─── Attribute change handler (parent-level) ──────────────────────────

    handleAttributeChange(event) {
        event.stopPropagation();
        const { attributeDefinitionId, value, picklistValueId } = event.detail;
        this.workingAttributes = this.workingAttributes.map((attr) => {
            if (attr.attributeDefinitionId === attributeDefinitionId) {
                return { ...attr, currentValue: value, _picklistValueId: picklistValueId };
            }
            return attr;
        });
        this._checkPriceImpactingChanges();
    }

    // ─── Option-level attribute change handler ──────────────────────────

    handleOptionAttributeChange(event) {
        event.stopPropagation();
        const { attributeDefinitionId, value, picklistValueId, productRelatedComponentId } = event.detail;

        this.workingGroups = this._applyOptionAttributeChange(
            this.workingGroups,
            productRelatedComponentId,
            attributeDefinitionId,
            value,
            picklistValueId
        );
        this._checkPriceImpactingChanges();
    }

    // ─── Save ─────────────────────────────────────────────────────────────

    async handleSave() {
        // Validate required attributes first
        if (!this._validateAttributes()) {
            this.toast(LBL_ERROR, LBL_CFG_ATTR_VALIDATION, 'error');
            return;
        }

        // Validate all groups
        const groupEls = this.template.querySelectorAll('c-mobile-tle-config-group');
        const validationErrors = [];
        groupEls.forEach((el) => {
            const errors = el.validate();
            if (errors && errors.length) validationErrors.push(...errors);
        });

        if (validationErrors.length > 0) {
            const msg = validationErrors.map((e) => `${e.groupName}: ${e.message}`).join('\n');
            this.toast(LBL_ERROR, LBL_CFG_VALIDATION_ERRORS + '\n' + msg, 'error');
            return;
        }

        const changes = this._computeChanges();
        if (changes.length === 0) {
            this.toast(LBL_SUCCESS, LBL_CFG_NO_CHANGES, 'info');
            this.dispatchEvent(new CustomEvent('done'));
            return;
        }

        this.saving = true;
        const needsReprice = this.hasPriceImpactingChanges;
        if (needsReprice) {
            this.repricing = true;
        }
        try {
            // Single call: saveBundleConfiguration handles QLI changes + QLIA + pricing
            const updatedState = await saveBundleConfiguration({
                quoteId: this.quoteId,
                parentLineId: this.lineId,
                configJson: JSON.stringify(changes)
            });

            // Update working state with returned prices
            if (updatedState) {
                this.configState = updatedState;
                this.workingGroups = this._deepCloneGroups(updatedState.groups || []);
                this.workingAttributes = JSON.parse(JSON.stringify(updatedState.attributes || []));
                this._snapshotOriginal(this.workingGroups);
                this.hasPriceImpactingChanges = false;
            }
            if (needsReprice) {
                this.toast(LBL_SUCCESS, 'Prices updated', 'success');
            } else {
                this.toast(LBL_SUCCESS, LBL_CFG_SAVED, 'success');
            }
            this.dispatchEvent(new CustomEvent('done'));
        } catch (e) {
            this.toast(LBL_ERROR, reduceError(e), 'error');
        } finally {
            this.saving = false;
            this.repricing = false;
        }
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    // ─── Diff computation ─────────────────────────────────────────────────

    _computeChanges() {
        const changes = [];
        this._walkOptions(this.workingGroups, (opt) => {
            const orig = this._originalSnapshot.get(opt.productRelatedComponentId);
            if (!orig) {
                // Not in original snapshot — newly added
                if (opt.isSelected) {
                    changes.push({
                        action: 'ADD',
                        productRelatedComponentId: opt.productRelatedComponentId,
                        childProduct2Id: opt.childProduct2Id,
                        pricebookEntryId: opt.pricebookEntryId,
                        quantity: opt.currentQuantity ?? opt.defaultQuantity ?? 1,
                        unitPrice: opt.currentUnitPrice,
                        quoteLineItemId: null,
                        attributes: this._getAttributeChanges(opt)
                    });
                }
            } else if (orig.isSelected && !opt.isSelected) {
                // Was selected, now removed
                changes.push({
                    action: 'REMOVE',
                    productRelatedComponentId: opt.productRelatedComponentId,
                    childProduct2Id: opt.childProduct2Id,
                    pricebookEntryId: opt.pricebookEntryId,
                    quoteLineItemId: orig.quoteLineItemId,
                    quantity: 0,
                    unitPrice: null,
                    attributes: null
                });
            } else if (!orig.isSelected && opt.isSelected) {
                // Was not selected, now added
                changes.push({
                    action: 'ADD',
                    productRelatedComponentId: opt.productRelatedComponentId,
                    childProduct2Id: opt.childProduct2Id,
                    pricebookEntryId: opt.pricebookEntryId,
                    quantity: opt.currentQuantity ?? opt.defaultQuantity ?? 1,
                    unitPrice: opt.currentUnitPrice,
                    quoteLineItemId: null,
                    attributes: this._getAttributeChanges(opt)
                });
            } else if (orig.isSelected && opt.isSelected) {
                // Both selected — check quantity or attribute changes
                const origQty = orig.quantity ?? 0;
                const curQty = opt.currentQuantity ?? opt.defaultQuantity ?? 1;
                const attrChanges = this._getAttributeChanges(opt, orig);
                const qtyChanged = origQty !== curQty;
                const attrsChanged = attrChanges && attrChanges.length > 0;
                if (qtyChanged || attrsChanged) {
                    changes.push({
                        action: 'UPDATE',
                        productRelatedComponentId: opt.productRelatedComponentId,
                        childProduct2Id: opt.childProduct2Id,
                        pricebookEntryId: opt.pricebookEntryId,
                        quoteLineItemId: orig.quoteLineItemId,
                        quantity: curQty,
                        unitPrice: opt.currentUnitPrice,
                        attributes: attrChanges
                    });
                }
            }
        });

        // Attribute changes on parent line
        if (this.workingAttributes && this.configState?.attributes) {
            const origAttrs = this.configState.attributes;
            const parentAttrChanges = [];
            this.workingAttributes.forEach((wa) => {
                const origAttr = origAttrs.find(
                    (a) => a.attributeDefinitionId === wa.attributeDefinitionId
                );
                const origVal = origAttr?.currentValue ?? '';
                const curVal = wa.currentValue ?? '';
                if (origVal !== curVal) {
                    parentAttrChanges.push({
                        attributeDefinitionId: wa.attributeDefinitionId,
                        value: curVal,
                        picklistValueId: wa._picklistValueId || null,
                        quoteLineItemAttributeId: wa.quoteLineItemAttributeId || null
                    });
                }
            });
            if (parentAttrChanges.length > 0) {
                changes.push({
                    action: 'UPDATE_PARENT_ATTRIBUTES',
                    quoteLineItemId: this.lineId,
                    attributes: parentAttrChanges
                });
            }
        }

        return changes;
    }

    _getAttributeChanges(opt, orig) {
        if (!opt.attributes || opt.attributes.length === 0) return null;

        // If we have an original snapshot with attributes, only include changed ones
        if (orig && orig.attributes && orig.attributes.length > 0) {
            const changed = [];
            for (const attr of opt.attributes) {
                const origAttr = orig.attributes.find(
                    (a) => a.attributeDefinitionId === attr.attributeDefinitionId
                );
                const origVal = origAttr?.currentValue ?? '';
                const curVal = attr.currentValue ?? '';
                if (origVal !== curVal) {
                    changed.push({
                        attributeDefinitionId: attr.attributeDefinitionId,
                        value: curVal,
                        picklistValueId: attr._picklistValueId || null,
                        quoteLineItemAttributeId: attr.quoteLineItemAttributeId || null
                    });
                }
            }
            return changed.length > 0 ? changed : null;
        }

        // No original — include all attributes with values (new option being added)
        const attrs = opt.attributes
            .filter((a) => a.currentValue != null && a.currentValue !== '')
            .map((a) => ({
                attributeDefinitionId: a.attributeDefinitionId,
                value: a.currentValue,
                picklistValueId: a._picklistValueId || null,
                quoteLineItemAttributeId: a.quoteLineItemAttributeId || null
            }));
        return attrs.length > 0 ? attrs : null;
    }

    // ─── State manipulation helpers ───────────────────────────────────────

    _applyOptionChange(groups, prcId, action, quantity) {
        return groups.map((g) => ({
            ...g,
            options: g.options.map((opt) => {
                if (opt.productRelatedComponentId === prcId) {
                    if (action === 'ADD') {
                        return { ...opt, isSelected: true, currentQuantity: quantity || opt.defaultQuantity || 1 };
                    }
                    if (action === 'REMOVE') {
                        return { ...opt, isSelected: false };
                    }
                    if (action === 'UPDATE') {
                        return { ...opt, currentQuantity: quantity };
                    }
                }
                // Recurse into nested child groups
                if (opt.childGroups && opt.childGroups.length > 0) {
                    return {
                        ...opt,
                        childGroups: this._applyOptionChange(opt.childGroups, prcId, action, quantity)
                    };
                }
                return opt;
            })
        }));
    }

    _snapshotOriginal(groups) {
        this._originalSnapshot = new Map();
        this._walkOptions(groups, (opt) => {
            this._originalSnapshot.set(opt.productRelatedComponentId, {
                isSelected: opt.isSelected === true,
                quantity: opt.currentQuantity ?? opt.defaultQuantity ?? 0,
                quoteLineItemId: opt.quoteLineItemId || null,
                attributes: opt.attributes
                    ? opt.attributes.map((a) => ({
                          attributeDefinitionId: a.attributeDefinitionId,
                          currentValue: a.currentValue ?? ''
                      }))
                    : []
            });
        });
    }

    _walkOptions(groups, fn) {
        if (!groups) return;
        for (const g of groups) {
            for (const opt of (g.options || [])) {
                fn(opt);
                if (opt.childGroups && opt.childGroups.length > 0) {
                    this._walkOptions(opt.childGroups, fn);
                }
            }
        }
    }

    _applyOptionAttributeChange(groups, prcId, attrDefId, value, picklistValueId) {
        return groups.map((g) => ({
            ...g,
            options: g.options.map((opt) => {
                if (opt.productRelatedComponentId === prcId && opt.attributes) {
                    return {
                        ...opt,
                        attributes: opt.attributes.map((a) => {
                            if (a.attributeDefinitionId === attrDefId) {
                                return { ...a, currentValue: value, _picklistValueId: picklistValueId };
                            }
                            return a;
                        })
                    };
                }
                // Recurse into nested child groups
                if (opt.childGroups && opt.childGroups.length > 0) {
                    return {
                        ...opt,
                        childGroups: this._applyOptionAttributeChange(
                            opt.childGroups, prcId, attrDefId, value, picklistValueId
                        )
                    };
                }
                return opt;
            })
        }));
    }

    _validateAttributes() {
        // Check parent-level required attributes
        if (this.workingAttributes) {
            for (const attr of this.workingAttributes) {
                if (attr.isRequired === true) {
                    const val = attr.currentValue;
                    if (val === null || val === undefined || val === '') return false;
                }
            }
        }

        // Check option-level required attributes (only for selected options)
        let valid = true;
        this._walkOptions(this.workingGroups, (opt) => {
            if (!valid) return;
            if (opt.isSelected && opt.attributes) {
                for (const attr of opt.attributes) {
                    if (attr.isRequired === true) {
                        const val = attr.currentValue;
                        if (val === null || val === undefined || val === '') {
                            valid = false;
                            return;
                        }
                    }
                }
            }
        });
        return valid;
    }

    _checkPriceImpactingChanges() {
        let hasPriceImpact = false;

        // Check parent attributes
        if (this.workingAttributes && this.configState?.attributes) {
            const origAttrs = this.configState.attributes;
            for (const wa of this.workingAttributes) {
                if (wa.isPriceImpacting !== true) continue;
                const origAttr = origAttrs.find(
                    (a) => a.attributeDefinitionId === wa.attributeDefinitionId
                );
                const origVal = origAttr?.currentValue ?? '';
                const curVal = wa.currentValue ?? '';
                if (origVal !== curVal) {
                    hasPriceImpact = true;
                    break;
                }
            }
        }

        // Check option-level attributes
        if (!hasPriceImpact) {
            this._walkOptions(this.workingGroups, (opt) => {
                if (hasPriceImpact) return;
                if (!opt.isSelected || !opt.attributes) return;
                const orig = this._originalSnapshot.get(opt.productRelatedComponentId);
                if (!orig) return;
                for (const attr of opt.attributes) {
                    if (attr.isPriceImpacting !== true) continue;
                    const origAttr = (orig.attributes || []).find(
                        (a) => a.attributeDefinitionId === attr.attributeDefinitionId
                    );
                    const origVal = origAttr?.currentValue ?? '';
                    const curVal = attr.currentValue ?? '';
                    if (origVal !== curVal) {
                        hasPriceImpact = true;
                        return;
                    }
                }
            });
        }

        this.hasPriceImpactingChanges = hasPriceImpact;
    }

    _deepCloneGroups(groups) {
        return JSON.parse(JSON.stringify(groups));
    }

    // ─── Toast ────────────────────────────────────────────────────────────

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
