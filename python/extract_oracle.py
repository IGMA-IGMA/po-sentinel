"""
extract_oracle.py

Выгрузка данных о проблемных заказах на закупку из Oracle DB.

Читает материализованное представление XX_MV_PROBLEM_ORDERS,
формирует pandas.DataFrame и сохраняет результат в CSV/Parquet.

Использование:
    python extract_oracle.py --config ../config/config.yaml --output ../out
"""

from __future__ import annotations

import argparse
import logging
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import oracledb
import pandas as pd
import yaml

LOG = logging.getLogger("po_sentinel.extract")

QUERY_PROBLEM_ORDERS = """
SELECT
    po_header_id,
    po_number,
    org_id,
    vendor_id,
    vendor_name,
    currency_code,
    total_amount,
    creation_date,
    approved_date,
    flag_overdue,
    flag_no_receipt,
    flag_price_diff,
    flag_unpaid
FROM xx_mv_problem_orders
WHERE flag_overdue    = 'Y'
   OR flag_no_receipt = 'Y'
   OR flag_price_diff = 'Y'
   OR flag_unpaid     = 'Y'
ORDER BY creation_date DESC
"""

QUERY_SUPPLIER_SUMMARY = """
SELECT
    vendor_id,
    vendor_name,
    total_orders,
    overdue_orders,
    no_receipt_orders,
    price_diff_orders,
    unpaid_orders,
    total_amount,
    problem_amount
FROM xx_mv_supplier_summary
WHERE overdue_orders    > 0
   OR no_receipt_orders > 0
   OR price_diff_orders > 0
   OR unpaid_orders     > 0
ORDER BY problem_amount DESC
"""


@dataclass
class DbConfig:
    user: str
    password: str
    dsn: str


def load_config(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def connect(cfg: DbConfig) -> oracledb.Connection:
    LOG.info("Connecting to Oracle as %s@%s", cfg.user, cfg.dsn)
    return oracledb.connect(user=cfg.user, password=cfg.password, dsn=cfg.dsn)


def fetch_df(conn: oracledb.Connection, sql: str) -> pd.DataFrame:
    LOG.debug("Executing query: %s", sql.strip().splitlines()[0])
    return pd.read_sql(sql, conn)


def save_outputs(
    problem_orders: pd.DataFrame,
    supplier_summary: pd.DataFrame,
    out_dir: Path,
) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)

    po_csv = out_dir / "problem_orders.csv"
    sup_csv = out_dir / "supplier_summary.csv"

    problem_orders.to_csv(po_csv, index=False, encoding="utf-8")
    supplier_summary.to_csv(sup_csv, index=False, encoding="utf-8")

    LOG.info("Wrote %s rows -> %s", len(problem_orders), po_csv)
    LOG.info("Wrote %s rows -> %s", len(supplier_summary), sup_csv)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="PO Sentinel — Oracle extractor")
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--verbose", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)-7s %(name)s: %(message)s",
    )

    cfg = load_config(args.config)
    db = DbConfig(**cfg["oracle"])

    with connect(db) as conn:
        problem_orders = fetch_df(conn, QUERY_PROBLEM_ORDERS)
        supplier_summary = fetch_df(conn, QUERY_SUPPLIER_SUMMARY)

    save_outputs(problem_orders, supplier_summary, args.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
