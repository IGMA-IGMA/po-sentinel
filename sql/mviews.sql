-- ============================================================
-- mviews.sql
-- Материализованные представления для быстрой выборки
-- проблемных заказов на закупку.
-- Обновление: ежедневно ночью (job в DBMS_SCHEDULER).
-- ============================================================

-- ------------------------------------------------------------
-- MV 1. Проблемные заказы: агрегированная витрина по заголовку
-- ------------------------------------------------------------
CREATE MATERIALIZED VIEW xx_mv_problem_orders
    TABLESPACE xx_po_mv
    BUILD IMMEDIATE
    REFRESH COMPLETE ON DEMAND
    ENABLE QUERY REWRITE
AS
SELECT
    ph.po_header_id,
    ph.segment1                       AS po_number,
    ph.org_id,
    ph.vendor_id,
    pv.vendor_name,
    ph.currency_code,
    NVL(ph.revised_total_amount, ph.total_amount) AS total_amount,
    ph.creation_date,
    ph.approved_date,
    -- флаги проблем
    CASE WHEN EXISTS (
            SELECT 1
              FROM po_line_locations_all pll
              JOIN po_lines_all pl ON pl.po_line_id = pll.po_line_id
             WHERE pl.po_header_id = ph.po_header_id
               AND NVL(pll.cancel_flag, 'N') = 'N'
               AND pll.expected_receipt_date < TRUNC(SYSDATE)
               AND NVL(pll.quantity_received, 0) < pll.quantity
         ) THEN 'Y' ELSE 'N' END                       AS flag_overdue,
    CASE WHEN EXISTS (
            SELECT 1
              FROM po_line_locations_all pll
              JOIN po_lines_all pl ON pl.po_line_id = pll.po_line_id
             WHERE pl.po_header_id = ph.po_header_id
               AND NVL(pll.cancel_flag, 'N') = 'N'
               AND NVL(pll.quantity_received, 0) = 0
               AND ph.approved_date IS NOT NULL
         ) THEN 'Y' ELSE 'N' END                       AS flag_no_receipt,
    CASE WHEN EXISTS (
            SELECT 1
              FROM ap_invoice_lines_all ail
              JOIN ap_invoices_all ai ON ai.invoice_id = ail.invoice_id
             WHERE ail.po_header_id = ph.po_header_id
               AND ai.cancelled_date IS NULL
               AND ail.unit_price > (
                    SELECT pl.unit_price
                      FROM po_lines_all pl
                     WHERE pl.po_line_id = ail.po_line_id
               )
         ) THEN 'Y' ELSE 'N' END                       AS flag_price_diff,
    CASE WHEN EXISTS (
            SELECT 1
              FROM ap_invoices_all ai
             WHERE ai.vendor_id = ph.vendor_id
               AND ai.cancelled_date IS NULL
               AND ai.payment_status_flag <> 'Y'
               AND ai.invoice_date + 30 < TRUNC(SYSDATE)
         ) THEN 'Y' ELSE 'N' END                       AS flag_unpaid
FROM
    po_headers_all ph
    JOIN po_vendors pv ON pv.vendor_id = ph.vendor_id
WHERE
    NVL(ph.cancel_flag, 'N') = 'N'
    AND ph.type_lookup_code IN ('STANDARD', 'BLANKET', 'CONTRACT');

CREATE UNIQUE INDEX xx_mv_problem_orders_pk
    ON xx_mv_problem_orders (po_header_id)
    TABLESPACE xx_po_idx;

-- ------------------------------------------------------------
-- MV 2. Сводка по поставщикам: количество и сумма проблемных заказов
-- ------------------------------------------------------------
CREATE MATERIALIZED VIEW xx_mv_supplier_summary
    TABLESPACE xx_po_mv
    BUILD IMMEDIATE
    REFRESH COMPLETE ON DEMAND
    ENABLE QUERY REWRITE
AS
SELECT
    vendor_id,
    vendor_name,
    COUNT(*)                                                  AS total_orders,
    SUM(CASE WHEN flag_overdue    = 'Y' THEN 1 ELSE 0 END)    AS overdue_orders,
    SUM(CASE WHEN flag_no_receipt = 'Y' THEN 1 ELSE 0 END)    AS no_receipt_orders,
    SUM(CASE WHEN flag_price_diff = 'Y' THEN 1 ELSE 0 END)    AS price_diff_orders,
    SUM(CASE WHEN flag_unpaid     = 'Y' THEN 1 ELSE 0 END)    AS unpaid_orders,
    SUM(total_amount)                                         AS total_amount,
    SUM(CASE WHEN flag_overdue = 'Y'
             OR flag_no_receipt = 'Y'
             OR flag_price_diff = 'Y'
             OR flag_unpaid = 'Y'
             THEN total_amount ELSE 0 END)                    AS problem_amount
FROM
    xx_mv_problem_orders
GROUP BY
    vendor_id, vendor_name;

CREATE UNIQUE INDEX xx_mv_supplier_summary_pk
    ON xx_mv_supplier_summary (vendor_id)
    TABLESPACE xx_po_idx;

-- ============================================================
-- Задание на ежедневное обновление MV в 02:00
-- ============================================================
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'XX_REFRESH_PROBLEM_ORDERS_MV',
        job_type        => 'PLSQL_BLOCK',
        job_action      => q'[
            BEGIN
                DBMS_MVIEW.REFRESH('XX_MV_PROBLEM_ORDERS',  'C');
                DBMS_MVIEW.REFRESH('XX_MV_SUPPLIER_SUMMARY','C');
            END;
        ]',
        start_date      => TRUNC(SYSDATE) + 1 + 2/24,
        repeat_interval => 'FREQ=DAILY; BYHOUR=2; BYMINUTE=0',
        enabled         => TRUE,
        comments        => 'PO Sentinel: refresh problem orders MVs'
    );
END;
/
