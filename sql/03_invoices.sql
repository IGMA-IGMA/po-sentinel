-- ============================================================
-- 03_invoices.sql
-- Выборка счетов поставщиков и привязка к строкам заказов.
-- Источник: AP_INVOICES_ALL, AP_INVOICE_LINES_ALL,
--           AP_INVOICE_DISTRIBUTIONS_ALL
-- ============================================================

SELECT
    ai.invoice_id,
    ai.invoice_num,
    ai.invoice_date,
    ai.invoice_type_lookup_code      AS invoice_type,
    ai.vendor_id,
    ai.vendor_site_id,
    ai.invoice_amount,
    ai.amount_paid,
    ai.invoice_amount - NVL(ai.amount_paid, 0) AS amount_due,
    ai.currency_code,
    ai.payment_status_flag,
    ai.cancelled_date,
    -- строки счёта
    ail.invoice_line_id,
    ail.line_number,
    ail.line_type_lookup_code,
    ail.amount                        AS line_amount,
    ail.po_header_id,
    ail.po_line_id,
    ail.po_line_location_id,
    ail.quantity_invoiced,
    ail.unit_price                    AS invoice_unit_price,
    -- проводки
    aid.distribution_id,
    aid.distribution_line_number,
    aid.amount                        AS distribution_amount,
    aid.po_distribution_id
FROM
    ap_invoices_all                  ai
    LEFT JOIN ap_invoice_lines_all   ail ON ail.invoice_id = ai.invoice_id
    LEFT JOIN ap_invoice_distributions_all aid
           ON aid.invoice_id = ai.invoice_id
          AND aid.invoice_line_id = ail.invoice_line_id
WHERE
    ai.cancelled_date IS NULL
    AND ai.invoice_type_lookup_code IN ('STANDARD', 'PREPAYMENT')
ORDER BY
    ai.invoice_date DESC;
