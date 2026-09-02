-- ============================================================
-- xx_problem_orders_pkg_body.sql
-- Тело PL/SQL-пакета PO Sentinel.
-- Реализует правила выявления проблемных заказов.
-- ============================================================

CREATE OR REPLACE PACKAGE BODY xx_problem_orders_pkg AS

    -- --------------------------------------------------------
    -- Приватные хелперы
    -- --------------------------------------------------------

    FUNCTION is_overdue(p_po_header_id IN NUMBER) RETURN VARCHAR2 IS
        l_count NUMBER;
    BEGIN
        SELECT COUNT(*)
          INTO l_count
          FROM po_line_locations_all pll
          JOIN po_lines_all pl ON pl.po_line_id = pll.po_line_id
         WHERE pl.po_header_id = p_po_header_id
           AND NVL(pll.cancel_flag, 'N') = 'N'
           AND pll.expected_receipt_date < TRUNC(SYSDATE)
           AND NVL(pll.quantity_received, 0) < pll.quantity;

        RETURN CASE WHEN l_count > 0 THEN c_flag_overdue ELSE 'N' END;
    END is_overdue;

    FUNCTION is_no_receipt(p_po_header_id IN NUMBER) RETURN VARCHAR2 IS
        l_count NUMBER;
    BEGIN
        SELECT COUNT(*)
          INTO l_count
          FROM po_line_locations_all pll
          JOIN po_lines_all pl ON pl.po_line_id = pll.po_line_id
         WHERE pl.po_header_id = p_po_header_id
           AND NVL(pll.cancel_flag, 'N') = 'N'
           AND NVL(pll.quantity_received, 0) = 0;

        RETURN CASE WHEN l_count > 0 THEN c_flag_no_receipt ELSE 'N' END;
    END is_no_receipt;

    FUNCTION is_price_diff(p_po_header_id IN NUMBER) RETURN VARCHAR2 IS
        l_count NUMBER;
    BEGIN
        SELECT COUNT(*)
          INTO l_count
          FROM ap_invoice_lines_all ail
          JOIN ap_invoices_all ai ON ai.invoice_id = ail.invoice_id
          JOIN po_lines_all pl    ON pl.po_line_id  = ail.po_line_id
         WHERE ail.po_header_id = p_po_header_id
           AND ai.cancelled_date IS NULL
           AND ail.unit_price > pl.unit_price;

        RETURN CASE WHEN l_count > 0 THEN c_flag_price_diff ELSE 'N' END;
    END is_price_diff;

    FUNCTION is_unpaid(p_po_header_id IN NUMBER) RETURN VARCHAR2 IS
        l_count NUMBER;
    BEGIN
        SELECT COUNT(*)
          INTO l_count
          FROM ap_invoices_all ai
          JOIN po_headers_all ph ON ph.vendor_id = ai.vendor_id
         WHERE ph.po_header_id = p_po_header_id
           AND ai.cancelled_date IS NULL
           AND ai.payment_status_flag <> 'Y'
           AND ai.invoice_date + c_unpaid_days < TRUNC(SYSDATE);

        RETURN CASE WHEN l_count > 0 THEN c_flag_unpaid ELSE 'N' END;
    END is_unpaid;

    -- --------------------------------------------------------
    -- Публичное API
    -- --------------------------------------------------------

    FUNCTION evaluate_order(p_po_header_id IN NUMBER) RETURN BOOLEAN IS
        l_overdue    VARCHAR2(1);
        l_no_receipt VARCHAR2(1);
        l_price_diff VARCHAR2(1);
        l_unpaid     VARCHAR2(1);
    BEGIN
        l_overdue    := is_overdue(p_po_header_id);
        l_no_receipt := is_no_receipt(p_po_header_id);
        l_price_diff := is_price_diff(p_po_header_id);
        l_unpaid     := is_unpaid(p_po_header_id);

        RETURN (l_overdue = 'Y'
             OR l_no_receipt = 'Y'
             OR l_price_diff = 'Y'
             OR l_unpaid = 'Y');
    END evaluate_order;

    FUNCTION get_problem_orders(
        p_org_id    IN NUMBER DEFAULT NULL,
        p_date_from IN DATE   DEFAULT NULL,
        p_date_to   IN DATE   DEFAULT NULL,
        p_vendor_id IN NUMBER DEFAULT NULL
    ) RETURN t_problem_orders_tab PIPELINED
    IS
        l_rec t_problem_order_rec;
    BEGIN
        FOR r IN (
            SELECT
                po.po_header_id,
                po.po_number,
                po.org_id,
                po.vendor_id,
                po.vendor_name,
                po.currency_code,
                po.total_amount,
                po.creation_date,
                po.approved_date,
                po.flag_overdue,
                po.flag_no_receipt,
                po.flag_price_diff,
                po.flag_unpaid
            FROM xx_mv_problem_orders po
            WHERE (p_org_id    IS NULL OR po.org_id    = p_org_id)
              AND (p_vendor_id IS NULL OR po.vendor_id = p_vendor_id)
              AND (p_date_from IS NULL OR po.creation_date >= p_date_from)
              AND (p_date_to   IS NULL OR po.creation_date <= p_date_to)
              AND (po.flag_overdue    = c_flag_overdue
                OR po.flag_no_receipt = c_flag_no_receipt
                OR po.flag_price_diff = c_flag_price_diff
                OR po.flag_unpaid     = c_flag_unpaid)
            ORDER BY po.creation_date DESC
        ) LOOP
            l_rec.po_header_id    := r.po_header_id;
            l_rec.po_number       := r.po_number;
            l_rec.org_id          := r.org_id;
            l_rec.vendor_id       := r.vendor_id;
            l_rec.vendor_name     := r.vendor_name;
            l_rec.currency_code   := r.currency_code;
            l_rec.total_amount    := r.total_amount;
            l_rec.creation_date   := r.creation_date;
            l_rec.approved_date   := r.approved_date;
            l_rec.flag_overdue    := r.flag_overdue;
            l_rec.flag_no_receipt := r.flag_no_receipt;
            l_rec.flag_price_diff := r.flag_price_diff;
            l_rec.flag_unpaid     := r.flag_unpaid;

            l_rec.problem_count :=
                  CASE WHEN r.flag_overdue    = 'Y' THEN 1 ELSE 0 END
                + CASE WHEN r.flag_no_receipt = 'Y' THEN 1 ELSE 0 END
                + CASE WHEN r.flag_price_diff = 'Y' THEN 1 ELSE 0 END
                + CASE WHEN r.flag_unpaid     = 'Y' THEN 1 ELSE 0 END;

            PIPE ROW (l_rec);
        END LOOP;
        RETURN;
    END get_problem_orders;

    PROCEDURE refresh_problem_orders IS
    BEGIN
        DBMS_MVIEW.REFRESH('XX_MV_PROBLEM_ORDERS',  'C');
        DBMS_MVIEW.REFRESH('XX_MV_SUPPLIER_SUMMARY','C');
        COMMIT;
    END refresh_problem_orders;

    PROCEDURE notify_responsible(p_org_id IN NUMBER DEFAULT NULL) IS
        l_count NUMBER;
    BEGIN
        l_count := count_problem_orders(p_org_id);
        IF l_count = 0 THEN
            RETURN;
        END IF;

        -- Фактическая отправка уведомлений делегируется Python-скрипту
        -- notify.py, который вызывается из конкурентной программы
        -- через хост-команду или DBMS_SCHEDULER.
        DBMS_OUTPUT.PUT_LINE('PO Sentinel: problem orders = ' || l_count);
    END notify_responsible;

    FUNCTION count_problem_orders(p_org_id IN NUMBER DEFAULT NULL) RETURN NUMBER IS
        l_count NUMBER;
    BEGIN
        SELECT COUNT(*)
          INTO l_count
          FROM xx_mv_problem_orders po
         WHERE (p_org_id IS NULL OR po.org_id = p_org_id)
           AND (po.flag_overdue    = 'Y'
             OR po.flag_no_receipt = 'Y'
             OR po.flag_price_diff = 'Y'
             OR po.flag_unpaid     = 'Y');
        RETURN l_count;
    END count_problem_orders;

    FUNCTION get_supplier_problem_amount(p_vendor_id IN NUMBER) RETURN NUMBER IS
        l_amount NUMBER;
    BEGIN
        SELECT NVL(problem_amount, 0)
          INTO l_amount
          FROM xx_mv_supplier_summary
         WHERE vendor_id = p_vendor_id;
        RETURN l_amount;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN 0;
    END get_supplier_problem_amount;

END xx_problem_orders_pkg;
/
