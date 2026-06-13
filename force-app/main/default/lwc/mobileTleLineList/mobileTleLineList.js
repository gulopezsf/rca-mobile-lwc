import { LightningElement, api, track } from 'lwc';
import { flattenTree } from 'c/mobileTleUtils';

// Custom Labels
import LBL_EXPAND from '@salesforce/label/c.MTLE_Expand';
import LBL_COLLAPSE from '@salesforce/label/c.MTLE_Collapse';
import LBL_N_ITEMS from '@salesforce/label/c.MTLE_NItems';

function fmt(template, ...args) {
    return template.replace(/\{(\d+)\}/g, (_, i) => args[i] ?? '');
}

export default class MobileTleLineList extends LightningElement {
    @api lineRows = [];
    @api columnDefinitions = [];
    @api currencyIsoCode = 'EUR';

    @track _collapsedIds = new Set();

    get displayRows() {
        const flat = flattenTree(this.lineRows);
        const rows = flat.map(({ row, depth }) => {
            const isCollapsed = row.isBundleParent && this._collapsedIds.has(row.id);
            const isChild = !!row.parentId;
            return {
                ...row,
                depth,
                isChild,
                isCollapsed,
                chevronIcon: isCollapsed ? 'utility:chevronright' : 'utility:chevrondown',
                chevronAlt: isCollapsed ? LBL_EXPAND : LBL_COLLAPSE,
                childLabel: row.childCount ? fmt(LBL_N_ITEMS, row.childCount, row.childCount > 1 ? 's' : '') : ''
            };
        });

        // Filter out children of collapsed parents
        const rowById = new Map(rows.map((r) => [r.id, r]));
        const visible = rows.filter((r) => !this._hasCollapsedAncestor(r, rowById));

        // Mark last-child for each parent group (for connector styling)
        const lastChildByParent = new Map();
        visible.forEach((r) => {
            if (r.isChild) {
                lastChildByParent.set(r.parentId, r.id);
            }
        });

        return visible.map((r) => {
            let wrapperClass = 'mtle-line-wrapper';
            if (r.isBundleParent) {
                wrapperClass += ' mtle-line-wrapper-parent';
            } else if (r.isChild) {
                wrapperClass += ' mtle-line-wrapper-child';
                if (lastChildByParent.get(r.parentId) === r.id) {
                    wrapperClass += ' mtle-line-wrapper-child-last';
                }
            }
            return {
                ...r,
                wrapperClass
            };
        });
    }

    get hasRows() {
        return this.displayRows && this.displayRows.length > 0;
    }

    handleToggle(event) {
        const rowId = event.currentTarget.dataset.rowid;
        if (!rowId) return;
        const newSet = new Set(this._collapsedIds);
        if (newSet.has(rowId)) {
            newSet.delete(rowId);
        } else {
            newSet.add(rowId);
        }
        this._collapsedIds = newSet;
    }

    handleCardAction(event) {
        // Relay to parent
        this.dispatchEvent(new CustomEvent('lineaction', {
            detail: event.detail,
            bubbles: true,
            composed: true
        }));
    }

    handleCardInlineEdit(event) {
        this.dispatchEvent(new CustomEvent('inlineedit', {
            detail: event.detail,
            bubbles: true,
            composed: true
        }));
    }

    _hasCollapsedAncestor(row, rowById) {
        let parentId = row.parentId;
        while (parentId) {
            if (this._collapsedIds.has(parentId)) return true;
            const parent = rowById.get(parentId);
            parentId = parent ? parent.parentId : null;
        }
        return false;
    }
}
