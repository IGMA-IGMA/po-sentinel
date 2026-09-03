# Рекомендации по внедрению PO Sentinel

Документ для команды внедрения и эксплуатации. Описывает, что делать
перед продом, во время и после, а также куда развивать проект.

## 1. Перед внедрением в прод

### 1.1. Аудит прав в схеме APPS

PO Sentinel создаёт объекты в схеме `APPS` (или кастомной). Убедитесь, что
у пользователя есть:

- `CREATE TABLE`, `CREATE INDEX`, `CREATE MATERIALIZED VIEW`;
- `CREATE PROCEDURE`, `CREATE JOB`;
- `SELECT` на `PO_HEADERS_ALL`, `PO_LINES_ALL`, `PO_LINE_LOCATIONS_ALL`,
  `AP_INVOICES_ALL`, `AP_INVOICE_LINES_ALL`, `PO_VENDORS`,
  `PO_VENDOR_SITES_ALL`, `HR_OPERATING_UNITS`;
- `EXECUTE` на `DBMS_MVIEW`, `DBMS_STATS`, `DBMS_SCHEDULER`.

### 1.2. Согласование расписания

Проверить, что окно refresh (02:15–03:00) не пересекается с:

- закрытием периода в AP/PO;
- ночным бэкапом RMAN;
- другими конкурентными программами в EBS.

### 1.3. Оценка объёма

Замерить:

```sql
SELECT COUNT(*) FROM po_headers_all;
SELECT COUNT(*) FROM po_lines_all;
SELECT COUNT(*) FROM ap_invoices_all;
```

- До 500 тыс. заказов — текущая схема (`REFRESH COMPLETE`) комфортна.
- 500 тыс. – 2 млн — рассмотреть `REFRESH FAST` с MV logs.
- Больше 2 млн — переходить на партиционирование MV по `creation_date`.

### 1.4. Бэкап

Перед установкой:

```bash
expdp apps/****@//oebs-db:1521/EBSDB \
    schemas=APPS \
    include=TABLE:\"LIKE \'XX_%\'\" \
    directory=DATA_PUMP_DIR \
    dumpfile=apps_xx_%U.dmp
```

## 2. Во время внедрения

### 2.1. Установка в порядке

1. Индексы (`sql/indexes.sql`).
2. MV (`sql/mviews.sql`).
3. PL/SQL-пакет.
4. Конкурентная программа.
5. OAF-страница.
6. Oracle BI.
7. Python-скрипты.

`deploy/install_oebs.sh` делает шаги 1–4 автоматически.

### 2.2. Проверка после каждого шага

```sql
-- после индексов
SELECT index_name, status FROM user_indexes
 WHERE index_name LIKE 'XX_%';

-- после MV
SELECT mview_name, staleness FROM user_mviews
 WHERE mview_name LIKE 'XX_MV_%';

-- после пакета
SELECT object_name, status FROM user_objects
 WHERE object_name = 'XX_PROBLEM_ORDERS_PKG';
```

Все объекты — `VALID` / `FRESH` / `COMPILED`.

### 2.3. Smoke-тест

```sql
-- 1. Пакет работает
SELECT xx_problem_orders_pkg.count_problem_orders FROM dual;

-- 2. Функция возвращает данные
SELECT COUNT(*)
  FROM TABLE(xx_problem_orders_pkg.get_problem_orders());

-- 3. MV не пусты
SELECT COUNT(*) FROM xx_mv_problem_orders;
SELECT COUNT(*) FROM xx_mv_supplier_summary;
```

## 3. После внедрения

### 3.1. Мониторинг

Рекомендуется настроить:

- **OEM / Zabbix** — алерт на `status = 'INVALID'` у объектов `XX_PROBLEM%`.
- **Метрики refresh MV** — время выполнения job `XX_PROBLEM_ORDERS_DAILY`.
  Если > 10 мин, переходить на `FAST`.
- **Метрики BI** — время отклика дашборда. Если > 5 с — добавлять
  агрегаты в MV.
- **Python** — алерт на `requests.HTTPError` в `api_client.py` и
  `notify.py`.

### 3.2. Обучение пользователей

Закупщики и аналитики должны знать:

- OAF-страница «Problem Orders» — где искать (меню закупок).
- Кнопка «Обновить» инициирует refresh MV — не злоупотреблять.
- Дашборд «Procurement Delay» в Oracle BI — ежедневный обзор.
- Отчёт «Problem Orders Report» приходит на email в 03:00.
- CSV-экспорт — для офлайн-разбора.

### 3.3. Регламент обновления

| Что                    | Когда       | Кто                |
|------------------------|-------------|--------------------|
| MV                     | 02:15       | DBMS_SCHEDULER     |
| BI-дашборд             | 02:30       | BI Scheduler       |
| BI-отчёт (email)       | 03:00       | BI Scheduler       |
| Проверка логов         | 09:00       | Дежурный аналитик  |
| Эскалация при ошибках  | сразу       | DBA / разработчик  |

## 4. Развитие проекта

### 4.1. Краткосрочное (1–3 месяца)

- Перевести MV на `REFRESH FAST` с materialized view log.
- Добавить REST-эндпоинты в ORDS вместо Python-скриптов.
- Настроить Prometheus + Grafana по метрикам refresh.
- Покрыть PL/SQL-пакет unit-тестами (utPLSQL).

### 4.2. Среднесрочное (3–12 месяцев)

- Расширить правила: дубли заказов, аномальные цены, поставщики
  с высокой долей брака.
- Интегрировать с Oracle APEX — быстрые экраны для ad-hoc анализа.
- Добавить мобильную версию дашборда (BI Mobile App Designer).
- Автоматизировать деплой через GitHub Actions + adop.

### 4.3. Долгосрочное (12+ месяцев)

- ML-модель прогнозирования просрочек (логистическая регрессия на
  исторических данных; вынести в отдельный сервис).
- Интеграция с внешними API логистических провайдеров для
  оперативного отслеживания поставок.
- Переход на Oracle Fusion Cloud Procurement (если планируется миграция
  с EBS).

## 5. Антипаттерны, которых избегать

- **Не** запускать `refresh_problem_orders` вручную в рабочее время —
  блокировки на `PO_HEADERS_ALL`.
- **Не** добавлять новые правила в OAF-Java — все правила только в
  PL/SQL-пакете, OAF — тонкий клиент.
- **Не** хранить пароли в `config.yaml` на проде — использовать
  Oracle Wallet и переменные окружения.
- **Не** отключать `ENABLE QUERY REWRITE` у MV — сломает оптимизацию
  тяжёлых запросов.
- **Не** редактировать MV напрямую — только через `sql/mviews.sql`
  и патчи.

## 6. Контакты

- Разработчик: Игнат <i9296517650@yandex.ru>
- DBA: <dba@example.local>
- Аналитик закупок: <procurement@example.local>
