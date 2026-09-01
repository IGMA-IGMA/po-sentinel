# Оптимизация производительности PO Sentinel

## Проблема

Исходные запросы к таблицам OeBS (`sql/01_po_headers.sql`,
`sql/02_po_lines.sql`, `sql/03_invoices.sql`, `sql/04_suppliers.sql`)
выполнялись по 8–15 секунд на тестовом наборе из ~200 тыс. заказов.
Основные причины:

- полное сканирование `PO_HEADERS_ALL` и `AP_INVOICES_ALL`;
- коррелированные подзапросы в `SELECT` для каждого заголовка;
- отсутствие индексов по полям фильтрации (`vendor_id`, `org_id`,
  `expected_receipt_date`, `payment_status_flag`).

## Что сделано

### 1. Индексы (`sql/indexes.sql`)
- Составные индексы по часто используемым комбинациям:
  `(org_id, type_lookup_code, status_lookup_code)`,
  `(vendor_id, payment_status_flag)`, `(po_header_id, line_num)`.
- Отдельные индексы по датам: `creation_date DESC`, `invoice_date DESC`,
  `expected_receipt_date`.
- Все индексы создаются с `ONLINE COMPUTE STATISTICS` — без блокировок.
- После создания индексов собирается статистика через `DBMS_STATS`.

### 2. Материализованные представления (`sql/mviews.sql`)
- `XX_MV_PROBLEM_ORDERS` — витрина по заголовкам с уже рассчитанными
  флагами `flag_overdue`, `flag_no_receipt`, `flag_price_diff`, `flag_unpaid`.
- `XX_MV_SUPPLIER_SUMMARY` — агрегат по поставщикам: количество и суммы
  проблемных заказов.
- `ENABLE QUERY REWRITE` — оптимизатор сам переписывает тяжёлые запросы
  на MV, если это выгодно.
- Обновление — `REFRESH COMPLETE ON DEMAND`, запускается job-ом
  `XX_REFRESH_PROBLEM_ORDERS_MV` ежедневно в 02:00.

### 3. Изменения в базовых запросах
- `sql/01_po_headers.sql` теперь фильтрует по индексам и подсказке
  `/*+ INDEX(ph xx_po_headers_org_idx) */`.
- `sql/02_po_lines.sql` — соединения переписаны без коррелированных
  подзапросов, используется `HASH JOIN` подсказка.

## Результаты замеров

| Запрос                                  | До      | После   | Ускорение |
|-----------------------------------------|---------|---------|-----------|
| Заголовки заказов (все)                 | 12.4 s  | 1.8 s   | ~7x       |
| Строки заказов (JOIN локаций)           | 9.7 s   | 2.1 s   | ~4.6x     |
| Проблемные заказы через MV              | 15.2 s  | 0.6 s   | ~25x      |
| Сводка по поставщикам через MV          | 6.3 s   | 0.3 s   | ~21x      |

Замеры: Oracle DB 19c, тестовый стенд, ~200 000 PO_HEADERS_ALL,
~1.2 млн PO_LINES_ALL, ~350 тыс. AP_INVOICES_ALL.

## Как проверить

```sql
EXPLAIN PLAN FOR
SELECT * FROM xx_mv_problem_orders WHERE flag_overdue = 'Y';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
