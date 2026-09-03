# Развёртывание PO Sentinel

Документ описывает установку PO Sentinel на тестовом стенде
(Arch Linux + Oracle DB XE + Oracle EBS + Oracle BI) и на продуктивной среде.

## Предварительные требования

### Хост
- Arch Linux (или совместимый дистрибутив).
- Oracle Instant Client 19c+ (`pacman -S oracle-instantclient-basic`).
- SQL*Plus (`pacman -S oracle-instantclient-sqlplus`).
- Python 3.11+ с `venv`.
- Git, `gh` (GitHub CLI).

### База данных
- Oracle Database 19c XE или выше.
- Схема `APPS` с правами на создание объектов.
- Установленный Oracle E-Business Suite 12.2.
- Настроенный `FND_CONCURRENT` (для регистрации конкурентной программы).

### BI
- Oracle BI Publisher / Oracle Analytics.
- Доступ к BI Catalog по пути `/Shared/PO_Sentinel`.
- JDBC-драйвер Oracle в classpath BI.

## Шаги установки

### 1. Клонирование репозитория

```bash
git clone git@github.com:<user>/po-sentinel.git
cd po-sentinel
```

### 2. Настройка конфигурации

```bash
cp config/config.example.yaml config/config.yaml
$EDITOR config/config.yaml
```

Заполнить:
- `oracle.user`, `oracle.password`, `oracle.dsn`;
- `api.base_url`, `api.token`;
- `smtp.*` и `webhook.*` — по необходимости.

Файл `config/config.yaml` добавлен в `.gitignore` — в git не попадёт.

### 3. Установка PL/SQL-объектов в EBS

```bash
chmod +x deploy/*.sh

./deploy/install_oebs.sh \
    --env dev \
    --apps-user apps \
    --apps-pass '****' \
    --db-conn '//oebs-db.example.local:1521/EBSDB'
```

Скрипт выполняет:
1. `sql/indexes.sql` — индексы.
2. `sql/mviews.sql` — материализованные представления.
3. `oebs/plsql/xx_problem_orders_pkg.sql` — спецификация пакета.
4. `oebs/plsql/xx_problem_orders_pkg_body.sql` — тело пакета.
5. `oebs/plsql/xx_problem_orders_conc.sql` — регистрация конкурентной программы.

Лог пишется в `logs/install_oebs_dev_<timestamp>.log`.

Проверка:

```sql
SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_name LIKE 'XX_PROBLEM%'
    OR object_name LIKE 'XX_MV%';
```

Все объекты должны быть в статусе `VALID`.

### 4. Развёртывание OAF-страницы

1. Скопировать файлы из `oebs/oaf/` в `$JAVA_TOP/xx/oracle/apps/po/sentinel/webui/`.
2. Загрузить page definition через XML Importer.
3. Зарегистрировать функцию в `FND_FORM_FUNCTIONS` с типом `OAF`.
4. Добавить функцию в меню закупок.

### 5. Развёртывание Oracle BI

```bash
./deploy/setup_bi.sh \
    --bi-home /opt/oracle/bi \
    --catalog /shared/PO_Sentinel \
    --env dev
```

Проверить в BI Analytics:
- `/Shared/PO_Sentinel/DataSources/oracle_ebs.xml`;
- `/Shared/PO_Sentinel/Dashboards/procurement_delay.xml`;
- `/Shared/PO_Sentinel/Reports/problem_orders.rdl`.

### 6. Настройка Python

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r python/requirements.txt
```

Первый прогон:

```bash
python python/extract_oracle.py \
    --config config/config.yaml \
    --output ./out
```

Ожидаемый результат: `out/problem_orders.csv`, `out/supplier_summary.csv`.

### 7. Проверка расписаний

Конкурентная программа в EBS:

```sql
SELECT job_name, enabled, repeat_interval
  FROM dba_scheduler_jobs
 WHERE job_name = 'XX_PROBLEM_ORDERS_DAILY';
```

Ожидается: `enabled = TRUE`, `repeat_interval = FREQ=DAILY; BYHOUR=2; BYMINUTE=15`.

## Обновление (патчи)

Патчи кладутся в `deploy/patches/` с именами `001_xxx.sql`, `002_xxx.sql`, ...

```bash
./deploy/apply_patches.sh \
    --env dev \
    --apps-user apps \
    --apps-pass '****' \
    --from 001
```

`--from` позволяет начать с конкретного патча (пропустив уже применённые).

## Откат

Для отката используется обратный скрипт из `deploy/patches/rollback/`
или восстановление из бэкапа:

```bash
sqlplus apps/****@//oebs-db.example.local:1521/EBSDB @deploy/patches/rollback/001_rollback.sql
```

Материализованные представления пересоздаются из `sql/mviews.sql`.

## Проверка после установки

```bash
# 1. Скомпилированные объекты
sqlplus -S apps/****@//oebs-db.example.local:1521/EBSDB <<SQL
SELECT object_name, status FROM user_objects
 WHERE object_name LIKE 'XX_PROBLEM%';
EXIT;
SQL

# 2. Данные в MV
sqlplus -S apps/****@//oebs-db.example.local:1521/EBSDB <<SQL
SELECT COUNT(*) FROM xx_mv_problem_orders;
SELECT COUNT(*) FROM xx_mv_supplier_summary;
EXIT;
SQL

# 3. Python
source .venv/bin/activate
python python/extract_oracle.py --config config/config.yaml --output ./out

# 4. Уведомления
python -c "from python.notify import dispatch; print('notify ok')"
```

## Прод

Для продакшена:
1. Использовать `--env prod`.
2. Не хранить пароли в командной строке — использовать Oracle Wallet
   или `.pgpass`-совместимый механизм (`~/.my.cnf` аналог для Oracle).
3. Запускать установку через CI (GitHub Actions) с ручным approval.
4. Перед деплоем — снять бэкап схемы `APPS` (RMAN / Data Pump).
5. После деплоя — прогнать smoke-тест (см. раздел «Проверка»).

## Известные ограничения

- OAF-файлы (`oebs/oaf/`) требуют ручной загрузки через XML Importer;
  автоматизация возможна через `adop`/`adpatch`, но в тестовом стенде
  не критична.
- Расписание `XX_PROBLEM_ORDERS_DAILY` создаётся в схеме, из которой
  запущен `install_oebs.sh` — убедитесь, что это `APPS` или схема с
  правами на `DBMS_SCHEDULER`.
