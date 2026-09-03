#!/usr/bin/env bash
# ============================================================
# apply_patches.sh
# Применение патчей/миграций PO Sentinel к среде Oracle EBS.
#
# Позволяет накатывать инкрементальные изменения поверх установки:
#   - новые колонки в MV;
#   - изменения PL/SQL-пакета;
#   - перерегистрация конкурентной программы.
#
# Патчи лежат в deploy/patches/ и нумеруются по возрастанию:
#   001_xxx.sql, 002_xxx.sql, ...
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PATCH_DIR="${SCRIPT_DIR}/patches"

ENV_NAME="dev"
APPS_USER="apps"
APPS_PASS=""
DB_CONN="//oebs-db.example.local:1521/EBSDB"
FROM_PATCH=""
LOG_DIR="${ROOT_DIR}/logs"

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --env NAME        Среда (dev|test|prod)                        [default: dev]
  --from PATCH      Начать с указанного патча (напр. 003)        [default: все]
  --apps-user USER  Пользователь Oracle                           [default: apps]
  --apps-pass PASS  Пароль пользователя Oracle
  --db-conn STR     Строка подключения                            [default: //oebs-db.example.local:1521/EBSDB]
  -h, --help        Показать справку
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env)        ENV_NAME="$2";  shift 2 ;;
        --from)       FROM_PATCH="$2"; shift 2 ;;
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

if [[ ! -d "${PATCH_DIR}" ]]; then
    echo "Patches directory not found: ${PATCH_DIR}" >&2
    exit 1
fi

mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/apply_patches_${ENV_NAME}_$(date +%Y%m%d_%H%M%S).log"
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "${LOG_FILE}"; }

log "PO Sentinel — apply patches"
log "Environment : ${ENV_NAME}"
log "DB          : ${DB_CONN}"
log "Schema      : ${APPS_USER}"
log "Patch dir   : ${PATCH_DIR}"
log "Log file    : ${LOG_FILE}"

mapfile -t patches < <(find "${PATCH_DIR}" -maxdepth 1 -type f -name '*.sql' | sort)

if [[ ${#patches[@]} -eq 0 ]]; then
    log "No patches found. Nothing to do."
    exit 0
fi

skip=true
if [[ -z "${FROM_PATCH}" ]]; then
    skip=false
fi

for p in "${patches[@]}"; do
    base="$(basename "$p")"
    if [[ "${skip}" == "true" ]]; then
        if [[ "${base}" == ${FROM_PATCH}* ]]; then
            skip=false
        else
            log "Skipping ${base}"
            continue
        fi
    fi

    log "Applying ${base}"
    sqlplus -S "${APPS_USER}/${APPS_PASS}@${DB_CONN}" @"${p}" >> "${LOG_FILE}" 2>&1
done

log "Compile check"
sqlplus -S "${APPS_USER}/${APPS_PASS}@${DB_CONN}" <<SQL >> "${LOG_FILE}" 2>&1
SELECT object_name, object_type, status
  FROM user_objects
 WHERE status = 'INVALID'
   AND (object_name LIKE 'XX_PROBLEM%' OR object_name LIKE 'XX_MV%');
EXIT;
SQL

log "Done. Проверьте ${LOG_FILE}."
