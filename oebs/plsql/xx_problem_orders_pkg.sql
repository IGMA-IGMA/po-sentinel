-- ============================================================
-- xx_problem_orders_pkg.sql
-- Спецификация PL/SQL-пакета PO Sentinel.
--
-- Пакет реализует правила выявления проблемных заказов на закупку
-- и предоставляет API для OAF-страницы и конкурентной программы.
--
-- Схема: APPS
-- ============================================================

CREATE OR REPLACE PACKAGE xx_problem_orders_pkg AS

    -- --------------------------------------------------------
    -- Константы: типы проблем
    -- --------------------------------------------------------
    c_flag_overdue    CONSTANT VARCHAR2(1) := 'Y';
    c_flag_no_receipt CONSTANT VARCHAR2(1) := 'Y';
    c_flag_price_diff CONSTANT VARCHAR2(1) := 'Y';
    c_flag_unpaid     CONSTANT VARCHAR2(1) := 'Y';

    -- Порог просрочки платежа (дней после invoice_date)
    c_unpaid_days     CONSTANT NUMBER := 30;

    -- --------------------------------------------------------
    -- Типы записей и коллекций
    -- --------------------------------------------------------
    TYPE t_problem_order_rec IS RECORD (
        po_header_id      NUMBER,
        po_number         VARCHAR2(20),
        org_id            NUMBER,
        vendor_id         NUMBER,
        vendor_name       VARCHAR2(240),
        currency_code     VARCHAR2(15),
        total_amount      NUMBER,
        creation_date     DATE,
        approved_date     DATE,
        flag_overdue      VARCHAR2(1),
        flag_no_receipt   VARCHAR2(1),
        flag_price_diff   VARCHAR2(1),
        flag_unpaid       VARCHAR2(1),
        problem_count     NUMBER
    );

    TYPE t_problem_orders_tab IS TABLE OF t_problem_order_rec
        INDEX BY PLS_INTEGER;

    -- --------------------------------------------------------
    -- Основное API
    -- --------------------------------------------------------

    -- Вернуть проблемные заказы по всем правилам.
    -- p_org_id = NULL -> по всем организациям.
    FUNCTION get_problem_orders(
        p_org_id       IN NUMBER   DEFAULT NULL,
        p_date_from    IN DATE     DEFAULT NULL,
        p_date_to      IN DATE     DEFAULT NULL,
        p_vendor_id    IN NUMBER   DEFAULT NULL
    ) RETURN t_problem_orders_tab
        PIPELINED;

    -- Вернуть один проблемный заказ по id (для OAF-детализации).
    FUNCTION get_problem_order_by_id(
        p_po_header_id IN NUMBER
    ) RETURN t_problem_order_rec;

    -- Пересчитать флаги проблем для одного заказа.
    -- Возвращает TRUE, если заказ проблемный.
    FUNCTION evaluate_order(
        p_po_header_id IN NUMBER
    ) RETURN BOOLEAN;

    -- Полный пересчёт витрины XX_MV_PROBLEM_ORDERS.
    -- Используется конкурентной программой по расписанию.
    PROCEDURE refresh_problem_orders;

    -- Отправить уведомления по проблемным заказам (через Python-скрипт).
    PROCEDURE notify_responsible(
        p_org_id IN NUMBER DEFAULT NULL
    );

    -- Обновить MV и (опционально) отправить уведомления.
    -- Точка входа для конкурентной программы и OAF-кнопки «Обновить».
    PROCEDURE refresh_and_notify(
        p_org_id IN NUMBER   DEFAULT NULL,
        p_notify IN VARCHAR2 DEFAULT 'Y'
    );

    -- --------------------------------------------------------
    -- Вспомогательные функции (публичные — используются OAF-страницей)
    -- --------------------------------------------------------

    FUNCTION count_problem_orders(
        p_org_id IN NUMBER DEFAULT NULL
    ) RETURN NUMBER;

    FUNCTION get_supplier_problem_amount(
        p_vendor_id IN NUMBER
    ) RETURN NUMBER;

END xx_problem_orders_pkg;
/
