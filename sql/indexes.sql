-- ============================================================
-- indexes.sql
-- Индексы для ускорения выборок проблемных заказов.
-- Создаются в схеме APPS (или в отдельной схеме-владельце).
-- ============================================================

-- Заголовки заказов: фильтрация по вендору, организации, статусу, дате
CREATE INDEX xx_po_headers_vendor_idx
    ON po_headers_all (vendor_id)
    TABLESPACE xx_po_idx
    ONLINE COMPUTE STATISTICS;

CREATE INDEX xx_po_headers_org_idx
    ON po_headers_all (org_id, type_lookup_code, status_lookup_code)
    TABLESPACE xx_po_idx
    ONLINE COMPUTE STATISTICS;

CREATE INDEX xx_po_headers_creation_idx
    ON po_headers_all (creation_date DESC)
    TABLESPACE xx_po_idx
    ONLINE COMPUTE STATISTICS;

-- Строки заказов: связь с заголовком и фильтр по closed_code
CREATE INDEX xx_po_lines_header_idx
    ON po_lines_all (po_header_id, line_num)
    TABLESPACE xx_po_idx
    ONLINE COMPUTE STATISTICS;

CREATE INDEX xx_po_lines_status_idx
    ON po_lines_all (closed_code, cancel_flag)
    TABLESPACE xx_po_idx
    ONLINE COMPUTE STATISTICS;

-- Локации поставки: связь со строкой + ожидаемая дата поступления
CREATE INDEX xx_po_line_loc_line_idx
    ON po_line_locations_all (po_line_id)
    TABLESPACE xx_po_idx
    ONLINE COMPUTE STATISTICS;

CREATE INDEX xx_po_line_loc_expected_idx
    ON po_line_locations_all (expected_receipt_date, cancel_flag)
    TABLESPACE xx_po_idx
    ONLINE COMPUTE STATISTICS;

-- Счета поставщиков: связь с вендором и статус оплаты
CREATE INDEX xx_ap_invoices_vendor_idx
    ON ap_invoices_all (vendor_id, payment_status_flag)
    TABLESPACE xx_po_idx
    ONLINE COMPUTE STATISTICS;

CREATE INDEX xx_ap_invoices_date_idx
    ON ap_invoices_all (invoice_date DESC)
    TABLESPACE xx_po_idx
    ONLINE COMPUTE STATISTICS;

-- Строки счетов: связь со строкой заказа (для поиска расхождений цены)
CREATE INDEX xx_ap_inv_lines_po_idx
    ON ap_invoice_lines_all (po_header_id, po_line_id)
    TABLESPACE xx_po_idx
    ONLINE COMPUTE STATISTICS;

-- Поставщики: включённые/выключенные
CREATE INDEX xx_po_vendors_enabled_idx
    ON po_vendors (enabled_flag, vendor_name)
    TABLESPACE xx_po_idx
    ONLINE COMPUTE STATISTICS;

-- ============================================================
-- Сбор статистики после создания индексов
-- ============================================================
BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(
        ownname          => USER,
        tabname          => 'PO_HEADERS_ALL',
        cascade          => TRUE,
        estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
        degree           => DBMS_STATS.AUTO_DEGREE
    );
    DBMS_STATS.GATHER_TABLE_STATS(
        ownname          => USER,
        tabname          => 'PO_LINES_ALL',
        cascade          => TRUE,
        estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
        degree           => DBMS_STATS.AUTO_DEGREE
    );
    DBMS_STATS.GATHER_TABLE_STATS(
        ownname          => USER,
        tabname          => 'AP_INVOICES_ALL',
        cascade          => TRUE,
        estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
        degree           => DBMS_STATS.AUTO_DEGREE
    );
END;
/
