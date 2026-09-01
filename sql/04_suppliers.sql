-- ============================================================
-- 04_suppliers.sql
-- Выборка поставщиков и связанных с ними площадок и контактов.
-- Источник: PO_VENDORS, PO_VENDOR_SITES_ALL, AP_SUPPLIERS
-- ============================================================

SELECT
    pv.vendor_id,
    pv.vendor_name,
    pv.vendor_name_alt,
    pv.segment1                       AS vendor_number,
    pv.enabled_flag                   AS vendor_enabled,
    pv.start_date_active,
    pv.end_date_active,
    pv.creation_date,
    -- площадки поставщика
    pvs.vendor_site_id,
    pvs.vendor_site_code,
    pvs.address_line1,
    pvs.city,
    pvs.state,
    pvs.zip,
    pvs.country,
    pvs.purchasing_site_flag,
    pvs.pay_site_flag,
    pvs.primary_pay_site_flag,
    -- агрегаты по заказам
    (SELECT COUNT(*)
       FROM po_headers_all ph
      WHERE ph.vendor_id = pv.vendor_id
        AND NVL(ph.cancel_flag, 'N') = 'N')          AS total_po_count,
    (SELECT NVL(SUM(NVL(ph.revised_total_amount, ph.total_amount)), 0)
       FROM po_headers_all ph
      WHERE ph.vendor_id = pv.vendor_id
        AND NVL(ph.cancel_flag, 'N') = 'N')          AS total_po_amount
FROM
    po_vendors              pv
    LEFT JOIN po_vendor_sites_all pvs
           ON pvs.vendor_id = pv.vendor_id
          AND NVL(pvs.inactive_date, SYSDATE + 1) > SYSDATE
WHERE
    pv.enabled_flag = 'Y'
ORDER BY
    pv.vendor_name;
