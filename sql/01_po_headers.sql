-- ============================================================
-- 01_po_headers.sql
-- Выборка заголовков заказов на закупку из Oracle EBS.
-- Источник: PO_HEADERS_ALL, PO_VENDORS, HR_OPERATING_UNITS
-- ============================================================

SELECT
    ph.po_header_id,
    ph.segment1                      AS po_number,
    ph.org_id,
    hou.name                         AS operating_unit,
    ph.vendor_id,
    pv.vendor_name,
    ph.type_lookup_code              AS po_type,
    ph.status_lookup_code            AS po_status,
    ph.authorization_status          AS approval_status,
    ph.currency_code,
    ph.creation_date,
    ph.approved_date,
    ph.start_date,
    ph.end_date,
    ph.closed_date,
    ph.cancel_flag,
    ph.summary_flag,
    ph.blanket_total_amount,
    NVL(ph.revised_total_amount, ph.total_amount) AS total_amount
FROM
    po_headers_all          ph
    JOIN po_vendors         pv  ON pv.vendor_id = ph.vendor_id
    LEFT JOIN hr_operating_units hou ON hou.organization_id = ph.org_id
WHERE
    ph.type_lookup_code IN ('STANDARD', 'BLANKET', 'CONTRACT')
    AND NVL(ph.cancel_flag, 'N') = 'N'
ORDER BY
    ph.creation_date DESC;
