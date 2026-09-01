-- ============================================================
-- 02_po_lines.sql
-- Выборка строк заказов на закупку.
-- Источник: PO_LINES_ALL, PO_LINE_LOCATIONS_ALL, PO_DISTRIBUTIONS_ALL
-- ============================================================

SELECT
    pl.po_line_id,
    pl.po_header_id,
    pl.line_num,
    pl.item_description,
    pl.category_id,
    pl.unit_meas_lookup_code         AS uom,
    pl.unit_price,
    pl.quantity,
    pl.quantity_received,
    pl.quantity_billed,
    pl.quantity_cancelled,
    pl.closed_code,
    pl.cancel_flag,
    -- локации поставки
    pll.line_location_id,
    pll.ship_to_organization_id,
    pll.quantity_received             AS loc_quantity_received,
    pll.quantity_billed               AS loc_quantity_billed,
    pll.promised_date,
    pll.need_by_date,
    pll.expected_receipt_date,
    pll.quantity,
    pll.quantity_cancelled            AS loc_quantity_cancelled
FROM
    po_lines_all             pl
    LEFT JOIN po_line_locations_all pll
           ON pll.po_line_id = pl.po_line_id
          AND NVL(pll.cancel_flag, 'N') = 'N'
WHERE
    NVL(pl.cancel_flag, 'N') = 'N'
    AND pl.closed_code IS NULL
ORDER BY
    pl.po_header_id, pl.line_num;
