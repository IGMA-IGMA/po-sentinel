"""
notify.py

Отправка уведомлений о проблемных заказах ответственным сотрудникам.

Поддерживает два канала:
- email через SMTP;
- webhook (Slack/Mattermost/корпоративный бот).

Уведомления формируются по результатам выгрузки extract_oracle.py.
"""

from __future__ import annotations

import logging
import smtplib
from dataclasses import dataclass, field
from email.message import EmailMessage
from typing import Any

import requests

LOG = logging.getLogger("po_sentinel.notify")


@dataclass
class SmtpConfig:
    host: str
    port: int
    user: str
    password: str
    sender: str
    recipients: list[str] = field(default_factory=list)
    use_tls: bool = True


@dataclass
class WebhookConfig:
    url: str
    token: str | None = None


class EmailNotifier:
    def __init__(self, cfg: SmtpConfig) -> None:
        self.cfg = cfg

    def send(self, subject: str, body: str) -> None:
        msg = EmailMessage()
        msg["From"] = self.cfg.sender
        msg["To"] = ", ".join(self.cfg.recipients)
        msg["Subject"] = subject
        msg.set_content(body)

        LOG.info("Sending email to %s", self.cfg.recipients)
        with smtplib.SMTP(self.cfg.host, self.cfg.port, timeout=30) as smtp:
            if self.cfg.use_tls:
                smtp.starttls()
            smtp.login(self.cfg.user, self.cfg.password)
            smtp.send_message(msg)


class WebhookNotifier:
    def __init__(self, cfg: WebhookConfig) -> None:
        self.cfg = cfg

    def send(self, text: str) -> None:
        headers = {"Content-Type": "application/json"}
        if self.cfg.token:
            headers["Authorization"] = f"Bearer {self.cfg.token}"

        payload = {"text": text}
        LOG.info("Sending webhook to %s", self.cfg.url)
        resp = requests.post(
            self.cfg.url, json=payload, headers=headers, timeout=30
        )
        resp.raise_for_status()


def format_summary_report(
    problem_orders: list[dict[str, Any]],
    supplier_summary: list[dict[str, Any]],
) -> str:
    """Сформировать текстовое тело отчёта для уведомления."""
    lines: list[str] = []
    lines.append("PO Sentinel — ежедневная сводка")
    lines.append("=" * 40)
    lines.append(f"Проблемных заказов: {len(problem_orders)}")
    lines.append("")

    lines.append("Топ-10 поставщиков по сумме проблем:")
    top10 = sorted(
        supplier_summary, key=lambda r: r.get("problem_amount", 0), reverse=True
    )[:10]
    for row in top10:
        lines.append(
            f"  - {row['vendor_name']}: "
            f"{row['problem_amount']:.2f} {row.get('currency_code', '')}"
        )

    lines.append("")
    lines.append("Проверьте дашборд Oracle BI для деталей.")
    return "\n".join(lines)


def dispatch(
    subject: str,
    body: str,
    smtp: SmtpConfig | None = None,
    webhook: WebhookConfig | None = None,
) -> None:
    if smtp and smtp.recipients:
        EmailNotifier(smtp).send(subject, body)
    else:
        LOG.info("SMTP not configured, skipping email")

    if webhook:
        WebhookNotifier(webhook).send(f"*{subject}*\n{body}")
    else:
        LOG.info("Webhook not configured, skipping webhook")
