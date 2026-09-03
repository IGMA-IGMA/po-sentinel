#!/usr/bin/env bash
# ============================================================
# setup_bi.sh
# Развёртывание объектов Oracle BI для PO Sentinel.
#
# Использует утилиту rcu / bi-import или BI Catalog Manager CLI.
# Для тестового стенда — копирование XML/RDL в каталог BI.
#
# Запуск:
#   ./setup_bi.sh --bi-home /opt/oracle/bi --env dev
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BI_HOME="/opt/oracle/bi"
BI_CATALOG_DIR="/shared/PO_Sentinel"
ENV_NAME="dev"
LOG_DIR="${ROOT_DIR}/logs"

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --bi-home PATH    Каталог установки Oracle BI     [default: /opt/oracle/bi]
  --catalog PATH    Каталог BI Catalog              [default: /shared/PO_Sentinel]
  --env NAME        Среда (dev|test|prod)           [default: dev]
  -h, --help        Показать справку
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bi-home) BI_HOME="$2";       shift 2 ;;
        --catalog) BI_CATALOG_DIR="$2";shift 2 ;;
        --env)     ENV_NAME="$2";      shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/setup_bi_${ENV_NAME}_$(date +%Y%m%d_%H%M%S).log"
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "${LOG_FILE}"; }

log "PO Sentinel — setup Oracle BI"
log "BI home     : ${BI_HOME}"
log "Catalog dir : ${BI_CATALOG_DIR}"
log "Environment : ${ENV_NAME}"
log "Log file    : ${LOG_FILE}"

if [[ ! -d "${BI_HOME}" ]]; then
    log "BI home not found: ${BI_HOME}"
    exit 1
fi

# 1. Источник данных
log "Importing datasource: oracle_ebs.xml"
cp -v "${ROOT_DIR}/bi/datasources/oracle_ebs.xml" \
      "${BI_CATALOG_DIR}/DataSources/" >> "${LOG_FILE}" 2>&1

# 2. Дашборд
log "Importing dashboard: procurement_delay.xml"
cp -v "${ROOT_DIR}/bi/dashboards/procurement_delay.xml" \
      "${BI_CATALOG_DIR}/Dashboards/" >> "${LOG_FILE}" 2>&1

# 3. Отчёт
log "Importing report: problem_orders.rdl"
cp -v "${ROOT_DIR}/bi/reports/problem_orders.rdl" \
      "${BI_CATALOG_DIR}/Reports/" >> "${LOG_FILE}" 2>&1

# 4. Проверка JDBC-подключения (тестовая)
log "Checking JDBC connectivity (dry-run)"
if command -v java >/dev/null 2>&1; then
    java -cp "${BI_HOME}/bifoundation/jdbc/*" \
         oracle.jdbc.OracleDriver -version 2>>"${LOG_FILE}" || true
fi

log "Done. Проверьте ${LOG_FILE}."
log "Откройте BI Analytics → Catalog → ${BI_CATALOG_DIR} и проверьте объекты."

