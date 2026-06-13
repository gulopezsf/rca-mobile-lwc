import { LightningElement, api, track } from 'lwc';

// Custom Labels
import LBL_ATTRIBUTES from '@salesforce/label/c.MTLE_CfgAttributes';
import LBL_NO_ATTRIBUTES from '@salesforce/label/c.MTLE_CfgNoAttributes';

export default class MobileTleConfigAttributes extends LightningElement {
    @api attributes = [];

    @track collapsed = false;

    label = {
        attributes: LBL_ATTRIBUTES,
        noAttributes: LBL_NO_ATTRIBUTES
    };

    get hasAttributes() {
        return this.attributes && this.attributes.length > 0;
    }

    get showAttributes() {
        return this.hasAttributes && !this.collapsed;
    }

    get headerIcon() {
        return this.collapsed ? 'utility:chevronright' : 'utility:chevrondown';
    }

    get attributeCount() {
        return (this.attributes || []).length;
    }

    get renderedAttributes() {
        return (this.attributes || []).map((attr) => ({
            ...attr,
            isPicklist: attr.dataType === 'Picklist',
            isText: attr.dataType === 'Text',
            isNumber: attr.dataType === 'Number',
            picklistOptions: (attr.picklistValues || []).map((pv) => ({
                label: pv.label || pv.value,
                value: pv.value
            })),
            fieldKey: attr.attributeDefinitionId
        }));
    }

    handleToggle() {
        this.collapsed = !this.collapsed;
    }

    handleChange(event) {
        const attrId = event.currentTarget.dataset.attrId;
        let value;
        let picklistValueId;

        // For combobox, the value is event.detail.value
        if (event.detail && event.detail.value !== undefined) {
            value = event.detail.value;
            // Find the corresponding picklistValueId
            const attr = (this.attributes || []).find(
                (a) => a.attributeDefinitionId === attrId
            );
            if (attr && attr.picklistValues) {
                const pv = attr.picklistValues.find((p) => p.value === value);
                picklistValueId = pv ? pv.picklistValueId : null;
            }
        } else {
            value = event.target.value;
        }

        this.dispatchEvent(new CustomEvent('attributechange', {
            detail: {
                attributeDefinitionId: attrId,
                value,
                picklistValueId: picklistValueId || null
            },
            bubbles: true,
            composed: true
        }));
    }
}
