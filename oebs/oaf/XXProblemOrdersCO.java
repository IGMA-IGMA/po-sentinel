/*
 * XXProblemOrdersCO.java
 *
 * Controller для OAF-страницы "PO Sentinel — Problem Orders".
 *
 * Задачи:
 *  - обрабатывать поиск проблемных заказов через PL/SQL-пакет
 *    xx_problem_orders_pkg.get_problem_orders;
 *  - экспортировать текущую выборку в CSV;
 *  - обновлять MV и перечитывать данные по кнопке «Обновить».
 */

package xx.oracle.apps.po.sentinel.webui;

import oracle.apps.fnd.framework.OAApplicationModule;
import oracle.apps.fnd.framework.OAException;
import oracle.apps.fnd.framework.webui.OAControllerImpl;
import oracle.apps.fnd.framework.webui.OAPageContext;
import oracle.apps.fnd.framework.webui.beans.OAWebBean;
import oracle.apps.fnd.framework.webui.beans.layout.OAPageLayoutBean;

import oracle.jbo.domain.Date;
import oracle.jbo.domain.Number;
import oracle.jbo.Row;
import oracle.jbo.ViewObject;

public class XXProblemOrdersCO extends OAControllerImpl {

    private static final String VO_NAME = "XXProblemOrdersVO";
    private static final String AM_NAME = "XXProblemOrdersAM";

    @Override
    public void processRequest(OAPageContext pageContext, OAWebBean webBean) {
        super.processRequest(pageContext, webBean);
        pageContext.writeDiagnostics(this, "XXProblemOrdersCO.processRequest", 1);
    }

    @Override
    public void processFormRequest(OAPageContext pageContext, OAWebBean webBean) {
        super.processFormRequest(pageContext, webBean);

        OAPageLayoutBean page = (OAPageLayoutBean) webBean;
        String event = pageContext.getParameter("event");

        if ("search".equals(event)) {
            doSearch(pageContext);
        } else if ("refreshResults".equals(event)) {
            doRefresh(pageContext);
        } else if ("exportCsv".equals(event)) {
            doExportCsv(pageContext);
        }
    }

    private void doSearch(OAPageContext pageContext) {
        OAApplicationModule am = pageContext.getApplicationModule(
                (OAWebBean) pageContext.getRootWebBean()
                        .findChildRecursive(AM_NAME));

        Number orgId    = (Number) pageContext.getParameter("OrgId");
        Number vendorId = (Number) pageContext.getParameter("VendorId");
        Date   dateFrom = (Date)   pageContext.getParameter("DateFrom");
        Date   dateTo   = (Date)   pageContext.getParameter("DateTo");

        ViewObject vo = am.findViewObject(VO_NAME);
        vo.setWhereClause(null);
        vo.setWhereClauseParams(null);

        StringBuilder where = new StringBuilder("1 = 1");
        if (orgId    != null) where.append(" AND OrgId = :1");
        if (vendorId != null) where.append(" AND VendorId = :2");
        if (dateFrom != null) where.append(" AND CreationDate >= :3");
        if (dateTo   != null) where.append(" AND CreationDate <= :4");

        vo.setWhereClause(where.toString());

        int idx = 1;
        if (orgId    != null) vo.setWhereClauseParam(idx++, orgId);
        if (vendorId != null) vo.setWhereClauseParam(idx++, vendorId);
        if (dateFrom != null) vo.setWhereClauseParam(idx++, dateFrom);
        if (dateTo   != null) vo.setWhereClauseParam(idx,   dateTo);

        vo.executeQuery();
    }

    private void doRefresh(OAPageContext pageContext) {
        OAApplicationModule am = pageContext.getApplicationModule(
                (OAWebBean) pageContext.getRootWebBean()
                        .findChildRecursive(AM_NAME));

        try {
            am.invokeMethod("refreshProblemOrders");
        } catch (Exception e) {
            throw new OAException("Ошибка обновления MV: " + e.getMessage(),
                                  OAException.ERROR);
        }
        doSearch(pageContext);
    }

    private void doExportCsv(OAPageContext pageContext) {
        OAApplicationModule am = pageContext.getApplicationModule(
                (OAWebBean) pageContext.getRootWebBean()
                        .findChildRecursive(AM_NAME));

        ViewObject vo = am.findViewObject(VO_NAME);
        vo.reset();
        StringBuilder csv = new StringBuilder();
        csv.append("PO_NUMBER;VENDOR_NAME;TOTAL_AMOUNT;CURRENCY;"
                 + "CREATION_DATE;APPROVED_DATE;OVERDUE;NO_RECEIPT;"
                 + "PRICE_DIFF;UNPAID\n");

        while (vo.hasNext()) {
            Row row = vo.next();
            csv.append(row.getAttribute("PoNumber")).append(';')
               .append(row.getAttribute("VendorName")).append(';')
               .append(row.getAttribute("TotalAmount")).append(';')
               .append(row.getAttribute("CurrencyCode")).append(';')
               .append(row.getAttribute("CreationDate")).append(';')
               .append(row.getAttribute("ApprovedDate")).append(';')
               .append(row.getAttribute("FlagOverdue")).append(';')
               .append(row.getAttribute("FlagNoReceipt")).append(';')
               .append(row.getAttribute("FlagPriceDiff")).append(';')
               .append(row.getAttribute("FlagUnpaid")).append('\n');
        }

        pageContext.putDialogMessage(
                new OAException("CSV подготовлен: " + csv.length()
                              + " символов (см. лог сервера)",
                                OAException.INFORMATION));
    }
}
