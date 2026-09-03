# Changelog

Все значимые изменения PO Sentinel.
Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/),
версии — [Semantic Versioning](https://semver.org/lang/ru/).

## [1.0.0] — 2026-09-17

Первый стабильный релиз: полный цикл от SQL-запросов до развёртывания
в Oracle EBS и Oracle BI.

### Добавлено

- **SQL**:
  - `sql/01_po_headers.sql` — выборка заголовков заказов на закупку.
  - `sql/02_po_lines.sql` — выборка строк заказов и локаций поставки.
  - `sql/03_invoices.sql` — счета поставщиков и проводки.
  - `sql/04_suppliers.sql` — поставщики и площадки.
  - `sql/indexes.sql` — 11 индексов для ускорения выборок.
  - `sql/mviews.sql` — 2 материализованных представления + job обновления.
- **Python**:
  - `python/extract_oracle.py` — выгрузка проблемных заказов в CSV.
  - `python/api_client.py` — HTTP-клиент с ретраями и health-check.
  - `python/notify.py` — email + webhook уведомления.
- **OeBS (PL/SQL + OAF)**:
  - `oebs/plsql/xx_problem_orders_pkg.sql` — спецификация пакета.
  - `oebs/plsql/xx_problem_orders_pkg_body.sql` — тело пакета (4 правила).
  - `oebs/plsql/xx_problem_orders_conc.sql` — конкурентная программа и job.
  - `oebs/oaf/XXProblemOrdersPG.xml` — page definition.
  - `oebs/oaf/XXProblemOrdersCO.java` — controller.
  - `oebs/oaf/XXProblemOrdersVO.xml` — view object.
- **Oracle BI**:
  - `bi/datasources/oracle_ebs.xml` — JDBC-источник и data model.
  - `bi/dashboards/procurement_delay.xml` — дашборд «Procurement Delay».
  - `bi/reports/problem_orders.rdl` — отчёт BI Publisher.
- **Развёртывание**:
  - `deploy/install_oebs.sh` — установка PL/SQL-объектов в EBS.
  - `deploy/apply_patches.sh` — применение инкрементальных патчей.
  - `deploy/setup_bi.sh` — развёртывание объектов Oracle BI.
- **Документация**:
  - `docs/architecture.md` — архитектура проекта.
  - `docs/performance.md` — замеры и оптимизация.
  - `docs/deployment.md` — инструкция по развёртыванию.
  - `docs/analysis.md` — анализ найденных проблем.
  - `docs/recommendations.md` — рекомендации по внедрению.
  - `README.md` — общее описание и быстрый старт.

### Изменено

- `config/config.example.yaml` — добавлены секции `environment`, `bi`, `ebs`.
- `.gitignore` — исключены `out/`, `logs/`, `config/config.yaml`.

### Известные ограничения

- OAF-файлы требуют ручной загрузки через XML Importer.
- MV обновляются полностью (`REFRESH COMPLETE`); при объёме > 2 млн
  строк стоит перейти на `FAST` с materialized view log.

## [Unreleased]

### Планируется

- Переход на `REFRESH FAST` для MV.
- Интеграция с Oracle APEX для быстрого прототипирования.
- REST-эндпоинты в ORDS вместо Python-скриптов.
- Метрики Prometheus + Grafana по времени отклика.
