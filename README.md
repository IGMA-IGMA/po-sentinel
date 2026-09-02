# PO Sentinel

Расширение Oracle E-Business Suite для мониторинга и анализа проблемных
заказов на закупку.

## О проекте

PO Sentinel — кастомное расширение OeBS, которое собирает данные о заказах
на закупку, выявляет отклонения по заданным правилам (просрочка поставки,
отсутствие поступления, расхождение цены, задолженность по счетам) и
отображает проблемные позиции в Oracle BI.

Python-скрипты автоматизируют выгрузку данных из Oracle DB, обмен с
внешними API и отправку уведомлений ответственным сотрудникам.

## Стек

- Oracle E-Business Suite (PL/SQL, OAF/ADF)
- Oracle Database (SQL, индексы, материализованные представления)
- Oracle BI (Publisher, Analytics)
- Python 3.11+ (oracledb, requests, pandas)
- Bash (скрипты развёртывания)

## Архитектура

Подробное описание — в [docs/architecture.md](docs/architecture.md).

## SQL-запросы

Базовые запросы к таблицам Oracle EBS лежат в каталоге `sql/`:

| Файл                | Назначение                                             |
|---------------------|--------------------------------------------------------|
| `01_po_headers.sql` | Заголовки заказов на закупку (PO_HEADERS_ALL)          |
| `02_po_lines.sql`   | Строки заказов и локации поставки (PO_LINES_ALL, ...)  |
| `03_invoices.sql`   | Счета поставщиков и проводки (AP_INVOICES_ALL, ...)    |
| `04_suppliers.sql`  | Поставщики и площадки (PO_VENDORS, PO_VENDOR_SITES_ALL)|
| `indexes.sql`       | Индексы для ускорения выборок                          |
| `mviews.sql`        | Материализованные представления и job обновления       |

Эти запросы — основа для правил выявления проблемных заказов
(просрочка, отсутствие поступления, расхождение цены, задолженность).

## Производительность

Детали оптимизации — в [docs/performance.md](docs/performance.md).
Кратко: добавлены индексы и материализованные представления, тяжёлые
запросы ускорены в 4–25 раз.

## Python-автоматизация

Каталог `python/`:

| Файл                 | Назначение                                                  |
|----------------------|-------------------------------------------------------------|
| `extract_oracle.py`  | Выгрузка проблемных заказов из MV в CSV                     |
| `api_client.py`      | HTTP-клиент для обмена с внешним порталом и health-check    |
| `notify.py`          | Уведомления по email и webhook (Slack/Mattermost)           |
| `requirements.txt`   | Зависимости Python                                          |

### Быстрый старт

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r python/requirements.txt

cp config/config.example.yaml config/config.yaml
$EDITOR config/config.yaml          # подставить реальные значения

python python/extract_oracle.py \
    --config config/config.yaml \
    --output ./out
```

Результат: `out/problem_orders.csv` и `out/supplier_summary.csv`.

## Расширение OeBS (PL/SQL)

Каталог `oebs/plsql/`:

| Файл                             | Назначение                                                 |
|----------------------------------|------------------------------------------------------------|
| `xx_problem_orders_pkg.sql`      | Спецификация пакета: API для OAF и конкурентной программы  |
| `xx_problem_orders_pkg_body.sql` | Тело пакета: правила выявления проблемных заказов          |
| `xx_problem_orders_conc.sql`     | Регистрация конкурентной программы и расписания в EBS      |

### Установка

```sql
-- под SYSDBA или APPS
@oebs/plsql/xx_problem_orders_pkg.sql
@oebs/plsql/xx_problem_orders_pkg_body.sql
@oebs/plsql/xx_problem_orders_conc.sql
```

После установки конкурентная программа `XX_PROBLEM_ORDERS_REFRESH`
запускается ежедневно в 02:15 job-ом `XX_PROBLEM_ORDERS_DAILY`.

### API пакета

- `get_problem_orders(p_org_id, p_date_from, p_date_to, p_vendor_id)` —
  пайплайновая функция, возвращает коллекцию проблемных заказов.
- `evaluate_order(p_po_header_id)` — проверяет один заказ по всем правилам.
- `refresh_problem_orders` — обновляет материализованные представления.
- `notify_responsible(p_org_id)` — инициирует отправку уведомлений.
- `count_problem_orders(p_org_id)` — количество проблемных заказов.
- `get_supplier_problem_amount(p_vendor_id)` — сумма проблем по поставщику.

## Планируемые этапы

1. ✅ Каркас репозитория и документация
2. ✅ SQL-запросы к таблицам закупок
3. ✅ Оптимизация запросов: индексы и материализованные представления
4. ✅ Python-скрипты для выгрузки и интеграции
5. ✅ PL/SQL-пакет и конкурентная программа в OeBS
6. OAF-страница для отображения проблемных заказов
7. Дашборды и отчёты Oracle BI
8. Скрипты развёртывания и настройки среды
9. Итоговая документация и рекомендации

## Лицензия

MIT — см. [LICENSE](LICENSE).
