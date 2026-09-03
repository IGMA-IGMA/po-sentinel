#!/usr/bin/env bash
# ============================================================
# install_oebs.sh
# Установка PL/SQL-объектов PO Sentinel в среду Oracle EBS.
#
# Запуск:
#   ./install_oebs.sh --env dev --apps-user apps --apps-pass ****
#
# Среда: Arch Linux, Oracle Client 19c+.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENV_NAME="dev"
APPS_USER="apps"
APPS_PASS=""
DB_CONN="//oebs-db.example.local:1521/EBSDB"
LOG_DIR="${ROOT_DIR}/logs"

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --env NAME        Целевая среда (dev|test|prod)          [default: dev]
  --apps-user USER  Пользователь Oracle (обычно apps)      [default: apps]
  --apps-pass PASS  Пароль пользователя Oracle
  --db-conn STR     Строка подключения (host:port/service) [default: //oebs-db.example.local:1521/EBSDB]
  -h, --help        Показать эту справку
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env)        ENV_NAME="$2";  shift 2 ;;
        --apps-user)  APPS_USER="$2"; shift 2 ;;
        --apps-pass)  APPS_PASS="$2"; shift 2 ;;
        --db-conn)    DB_CONN="$2";   shift 2 ;;
        -h|--help)    usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ -z "${APPS_PASS}" ]]; then
    read -r -s -p "Oracle password for ${APPS_USER}: " APPS_PASS
    echo
fi

mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/install_oebs_${ENV_NAME}_$(date +%Y%m%d_%H%M%S).log"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "${LOG_FILE}"; }

log "PO Sentinel — install OeBS objects"
log "Environment : ${ENV_NAME}"
log "DB          : ${DB_CONN}"
log "Schema      : ${APPS_USER}"
log "Log file    : ${LOG_FILE}"

run_sql() {
    local file="$1"
    log "Running ${file}"
    sqlplus -S "${APPS_USER}/${APPS_PASS}@${DB_CONN}" @"${file}" \
        >> "${LOG_FILE}" 2>&1
}

# 1. Индексы
run_sql "${ROOT_DIR}/sql/indexes.sql"

# 2. Материализованные представления
run_sql "${ROOT_DIR}/sql/mviews.sql"

# 3. PL/SQL-пакет
run_sql "${ROOT_DIR}/oebs/plsql/xx_problem_orders_pkg.sql"
run_sql "${ROOT_DIR}/oebs/plsql/xx_problem_orders_pkg_body.sql"

# 4. Регистрация конкурентной программы в EBS
run_sql "${ROOT_DIR}/oebs/plsql/xx_problem_orders_conc.sql"

log "Compile check"
sqlplus -S "${APPS_USER}/${APPS_PASS}@${DB_CONN}" <<SQL >> "${LOG_FILE}" 2>&1
SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_name LIKE 'XX_PROBLEM%'
    OR object_name LIKE 'XX_MV%';
EXIT;
SQL

log "Done. Проверьте ${LOG_FILE} на ошибки."
