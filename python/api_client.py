"""
api_client.py

HTTP-клиент для обмена данными с внешними системами PO Sentinel.

Используется для:
- отправки агрегированных данных о проблемных заказах в корпоративный портал;
- получения справочной информации о поставщиках из внешнего реестра;
- health-check внешних сервисов перед выгрузкой.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

LOG = logging.getLogger("po_sentinel.api")


@dataclass
class ApiConfig:
    base_url: str
    token: str
    timeout: int = 30
    retries: int = 3


class ApiClient:
    """Тонкая обёртка над requests с ретраями и единой авторизацией."""

    def __init__(self, cfg: ApiConfig) -> None:
        self.cfg = cfg
        self.session = requests.Session()
        self.session.headers.update(
            {
                "Authorization": f"Bearer {cfg.token}",
                "Accept": "application/json",
                "User-Agent": "po-sentinel/1.0",
            }
        )
        retry = Retry(
            total=cfg.retries,
            backoff_factor=0.5,
            status_forcelist=(429, 500, 502, 503, 504),
            allowed_methods=("GET", "POST", "PUT", "PATCH"),
        )
        adapter = HTTPAdapter(max_retries=retry)
        self.session.mount("https://", adapter)
        self.session.mount("http://", adapter)

    def _url(self, path: str) -> str:
        return f"{self.cfg.base_url.rstrip('/')}/{path.lstrip('/')}"

    def get(self, path: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        LOG.debug("GET %s params=%s", path, params)
        resp = self.session.get(self._url(path), params=params, timeout=self.cfg.timeout)
        resp.raise_for_status()
        return resp.json()

    def post(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        LOG.debug("POST %s", path)
        resp = self.session.post(
            self._url(path), json=payload, timeout=self.cfg.timeout
        )
        resp.raise_for_status()
        return resp.json()

    def health(self) -> bool:
        try:
            self.get("/health")
            return True
        except requests.RequestException as exc:
            LOG.warning("Health check failed: %s", exc)
            return False

    def push_problem_orders(self, records: list[dict[str, Any]]) -> dict[str, Any]:
        """Отправить пачку проблемных заказов во внешнюю систему."""
        LOG.info("Pushing %s problem orders", len(records))
        return self.post("/v1/procurement/problem-orders", {"items": records})

    def push_supplier_summary(self, records: list[dict[str, Any]]) -> dict[str, Any]:
        """Отправить сводку по поставщикам."""
        LOG.info("Pushing %s supplier summary rows", len(records))
        return self.post("/v1/procurement/supplier-summary", {"items": records})
