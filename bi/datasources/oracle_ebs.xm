<?xml version="1.0" encoding="UTF-8"?>
<!--
  oracle_ebs.xml
  Описание источника данных Oracle BI для PO Sentinel.

  Источник — схема APPS, объекты:
    - XX_MV_PROBLEM_ORDERS   (витрина проблемных заказов)
    - XX_MV_SUPPLIER_SUMMARY (сводка по поставщикам)
    - XX_PROBLEM_ORDERS_PKG  (PL/SQL-функция для live-выборок)

  Подключение: Oracle BI Publisher / Oracle Analytics.
-->
<dataSource name="PO_SENTINEL_EBS"
            type="JDBC"
            driver="oracle.jdbc.OracleDriver"
            url="jdbc:oracle:thin:@//oebs-db.example.local:1521/EBSDB"
            user="APPS"
            passwordRef="oebs-db/apps"/>

<dataModel name="PO_SENTINEL_DM">
    <dataSet name="ProblemOrders" type="SQL">
        <sql>
            SELECT
                po_header_id       AS "PO_HEADER_ID",
                po_number          AS "PO_NUMBER",
                org_id             AS "ORG_ID",
                vendor_id          AS "VENDOR_ID",
                vendor_name        AS "VENDOR_NAME",
                currency_code      AS "CURRENCY_CODE",
                total_amount       AS "TOTAL_AMOUNT",
                creation_date      AS "CREATION_DATE",
                approved_date      AS "APPROVED_DATE",
                flag_overdue       AS "FLAG_OVERDUE",
                flag_no_receipt    AS "FLAG_NO_RECEIPT",
                flag_price_diff    AS "FLAG_PRICE_DIFF",
                flag_unpaid        AS "FLAG_UNPAID"
            FROM xx_mv_problem_orders
            WHERE flag_overdue    = 'Y'
               OR flag_no_receipt = 'Y'
               OR flag_price_diff = 'Y'
               OR flag_unpaid     = 'Y'
        </sql>
    </dataSet>

    <dataSet name="SupplierSummary" type="SQL">
        <sql>
            SELECT
                vendor_id           AS "VENDOR_ID",
                vendor_name         AS "VENDOR_NAME",
                total_orders        AS "TOTAL_ORDERS",
                overdue_orders      AS "OVERDUE_ORDERS",
                no_receipt_orders   AS "NO_RECEIPT_ORDERS",
                price_diff_orders   AS "PRICE_DIFF_ORDERS",
                unpaid_orders       AS "UNPAID_ORDERS",
                total_amount        AS "TOTAL_AMOUNT",
                problem_amount      AS "PROBLEM_AMOUNT"
            FROM xx_mv_supplier_summary
        </sql>
    </dataSet>

    <parameter name="P_ORG_ID"    dataType="NUMBER" defaultValue=""/>
    <parameter name="P_DATE_FROM" dataType="DATE"   defaultValue=""/>
    <parameter name="P_DATE_TO"   dataType="DATE"   defaultValue=""/>
</dataModel>
