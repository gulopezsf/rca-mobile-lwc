/**
 * Construye lista en profundidad primero (padres antes que hijos en cada nivel)
 * a partir de filas planas con parentQuoteLineItemId.
 */
export function flattenTree(rows) {
    if (!rows || rows.length === 0) {
        return [];
    }
    const byParent = new Map();
    rows.forEach((r) => {
        const key = r.parentQuoteLineItemId || 'ROOT';
        if (!byParent.has(key)) {
            byParent.set(key, []);
        }
        byParent.get(key).push(r);
    });
    const out = [];
    function walk(parentKey, depth) {
        const list = byParent.get(parentKey);
        if (!list) {
            return;
        }
        list.forEach((r) => {
            out.push({ row: r, depth });
            walk(r.id, depth + 1);
        });
    }
    walk('ROOT', 0);
    return out;
}

export function formatCellValue(value, type) {
    if (value === null || value === undefined) {
        return '';
    }
    if (type === 'DOUBLE' || type === 'CURRENCY' || type === 'PERCENT' || type === 'INTEGER') {
        return typeof value === 'number' ? String(value) : String(value);
    }
    if (type === 'BOOLEAN') {
        return value ? 'Yes' : 'No';
    }
    return String(value);
}