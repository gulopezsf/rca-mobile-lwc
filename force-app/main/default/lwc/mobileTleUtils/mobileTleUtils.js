/**
 * Shared utilities for the Mobile TLE component family.
 */

import LBL_YES from '@salesforce/label/c.MTLE_Yes';
import LBL_NO from '@salesforce/label/c.MTLE_No';
import LBL_UNKNOWN_ERROR from '@salesforce/label/c.MTLE_UnknownError';

/**
 * Depth-first tree flattening for bundle hierarchy.
 * Each entry: { row, depth }
 */
export function flattenTree(rows) {
    if (!rows || rows.length === 0) return [];
    const byParent = new Map();
    rows.forEach((r) => {
        const key = r.parentId || 'ROOT';
        if (!byParent.has(key)) byParent.set(key, []);
        byParent.get(key).push(r);
    });
    const out = [];
    function walk(parentKey, depth) {
        const list = byParent.get(parentKey);
        if (!list) return;
        list.forEach((r) => {
            out.push({ row: r, depth });
            walk(r.id, depth + 1);
        });
    }
    walk('ROOT', 0);
    return out;
}

/**
 * Formats a cell value for display based on its type.
 */
export function formatCellValue(value, dataType) {
    if (value === null || value === undefined) return '';
    if (dataType === 'BOOLEAN') return value ? LBL_YES : LBL_NO;
    return String(value);
}

/**
 * Formats a numeric value as currency string.
 */
export function formatCurrency(value, currencyIso) {
    if (value === null || value === undefined) return '—';
    try {
        return new Intl.NumberFormat(undefined, {
            style: 'currency',
            currency: currencyIso || 'EUR',
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        }).format(Number(value));
    } catch (e) {
        return String(value);
    }
}

/**
 * Generic error reducer for Apex / LDS errors.
 */
export function reduceError(error) {
    if (Array.isArray(error?.body)) {
        return error.body.map((e) => e.message).join(', ');
    }
    const b = error?.body;
    if (b && typeof b === 'object') {
        if (b.message) return b.message;
        if (b.pageErrors?.length) return b.pageErrors.map((p) => p.message).join(', ');
        if (b.fieldErrors && typeof b.fieldErrors === 'object') {
            const msgs = [];
            Object.keys(b.fieldErrors).forEach((k) =>
                (b.fieldErrors[k] || []).forEach((fe) => msgs.push(fe.message || fe.statusCode))
            );
            if (msgs.length) return msgs.join(', ');
        }
        if (b.output?.errors?.length) return b.output.errors.map((e) => e.message).join(', ');
    }
    if (typeof error?.message === 'string') return error.message;
    return LBL_UNKNOWN_ERROR;
}
