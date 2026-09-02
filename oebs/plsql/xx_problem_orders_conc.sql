-- ============================================================
-- xx_problem_orders_conc.sql
-- Регистрация конкурентной программы PO Sentinel в Oracle EBS.
--
-- Запускает пересчёт витрины проблемных заказов и рассылку уведомлений.
-- Регистрируется в приложении "Purchasing" (или кастомном приложении).
-- ============================================================

-- ------------------------------------------------------------
-- 1. Исполняемый файл
-- ------------------------------------------------------------
DECLARE
    l_app_id      NUMBER;
    l_exec_id     NUMBER;
    l_exec_name   CONSTANT VARCHAR2(30)  := 'XX_PROBLEM_ORDERS';
    l_user_name   CONSTANT VARCHAR2(100) := 'XX_PROBLEM_ORDERS_PKG.REFRESH_AND_NOTIFY';
    l_description CONSTANT VARCHAR2(240) := 'PO Sentinel: refresh problem orders and send notifications';
BEGIN
    SELECT application_id
      INTO l_app_id
      FROM fnd_application
     WHERE application_short_name = 'PO';

    BEGIN
        SELECT executable_id
          INTO l_exec_id
          FROM fnd_executables
         WHERE executable_name = l_exec_name
           AND application_id  = l_app_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            l_exec_id := fnd_executables_s.NEXTVAL;

            INSERT INTO fnd_executables (
                application_id,
                executable_id,
                executable_name,
                executable_appl_name,
                user_name,
                description,
                execution_method_code,
                execution_file_name,
                icon_name,
                created_by,
                creation_date,
                last_update_by,
                last_update_date
            ) VALUES (
                l_app_id,
                l_exec_id,
                l_exec_name,
                'SQL*Plus',
                l_user_name,
                l_description,
                'I',            -- Immediate
                NULL,
                NULL,
                fnd_global.user_id,
                SYSDATE,
                fnd_global.user_id,
                SYSDATE
            );
    END;
END;
/

-- ------------------------------------------------------------
-- 2. Конкурентная программа
-- ------------------------------------------------------------
DECLARE
    l_app_id     NUMBER;
    l_conc_id    NUMBER;
    l_exec_id    NUMBER;
    l_conc_name  CONSTANT VARCHAR2(30) := 'XX Problem Orders Refresh';
BEGIN
    SELECT application_id
      INTO l_app_id
      FROM fnd_application
     WHERE application_short_name = 'PO';

    SELECT executable_id
      INTO l_exec_id
      FROM fnd_executables
     WHERE executable_name = 'XX_PROBLEM_ORDERS'
       AND application_id  = l_app_id;

    BEGIN
        SELECT concurrent_program_id
          INTO l_conc_id
          FROM fnd_concurrent_programs
         WHERE concurrent_program_name = 'XX_PROBLEM_ORDERS_REFRESH'
           AND application_id         = l_app_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            l_conc_id := fnd_concurrent_programs_s.NEXTVAL;

            INSERT INTO fnd_concurrent_programs (
                application_id,
                concurrent_program_id,
                concurrent_program_name,
                user_concurrent_program_name,
                description,
                executable_application_id,
                executable_id,
                execution_method_code,
                enabled_flag,
                created_by,
                creation_date,
                last_update_by,
                last_update_date
            ) VALUES (
                l_app_id,
                l_conc_id,
                'XX_PROBLEM_ORDERS_REFRESH',
                'PO Sentinel: Refresh Problem Orders',
                'Refresh XX_MV_PROBLEM_ORDERS and XX_MV_SUPPLIER_SUMMARY, then send notifications',
                l_app_id,
                l_exec_id,
                'I',
                'Y',
                fnd_global.user_id,
                SYSDATE,
                fnd_global.user_id,
                SYSDATE
            );
    END;
END;
/

-- ------------------------------------------------------------
-- 3. Параметры конкурентной программы
--    P_ORG_ID     — организация (необязательно)
--    P_NOTIFY     — отправлять уведомления (Y/N)
-- ------------------------------------------------------------
DECLARE
    l_app_id  NUMBER;
    l_conc_id NUMBER;
BEGIN
    SELECT application_id
      INTO l_app_id
      FROM fnd_application
     WHERE application_short_name = 'PO';

    SELECT concurrent_program_id
      INTO l_conc_id
      FROM fnd_concurrent_programs
     WHERE concurrent_program_name = 'XX_PROBLEM_ORDERS_REFRESH'
       AND application_id         = l_app_id;

    -- параметр 1: ORG_ID
    INSERT INTO fnd_descr_flex_col_usage (
        descriptive_flexfield_name,
        application_id,
        descriptive_flex_context_code,
        application_column_name,
        end_user_column_name,
        column_seq_num,
        enabled_flag,
        required_flag,
        created_by,
        creation_date,
        last_update_by,
        last_update_date
    ) VALUES (
        '$FLEX$.XX_PROBLEM_ORDERS_PARAMS',
        l_app_id,
        'GLOBAL',
        'P_ORG_ID',
        'Organization ID',
        1,
        'Y',
        'N',
        fnd_global.user_id,
        SYSDATE,
        fnd_global.user_id,
        SYSDATE
    );

    -- параметр 2: NOTIFY_FLAG
    INSERT INTO fnd_descr_flex_col_usage (
        descriptive_flexfield_name,
        application_id,
        descriptive_flex_context_code,
        application_column_name,
        end_user_column_name,
        column_seq_num,
        enabled_flag,
        required_flag,
        created_by,
        creation_date,
        last_update_by,
        last_update_date
    ) VALUES (
        '$FLEX$.XX_PROBLEM_ORDERS_PARAMS',
        l_app_id,
        'GLOBAL',
        'P_NOTIFY',
        'Send notifications (Y/N)',
        2,
        'Y',
        'N',
        fnd_global.user_id,
        SYSDATE,
        fnd_global.user_id,
        SYSDATE
    );
END;
/

-- ------------------------------------------------------------
-- 4. Расписание: ежедневно в 02:15
-- ------------------------------------------------------------
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'XX_PROBLEM_ORDERS_DAILY',
        job_type        => 'PLSQL_BLOCK',
        job_action      => q'[
            DECLARE
                l_conc_id NUMBER;
            BEGIN
                l_conc_id := fnd_request.submit_request(
                    application => 'PO',
                    program     => 'XX_PROBLEM_ORDERS_REFRESH',
                    description => 'PO Sentinel daily refresh',
                    start_time  => SYSDATE,
                    sub_request => FALSE,
                    argument1   => NULL,
                    argument2   => 'Y'
                );
                COMMIT;
            END;
        ]',
        start_date      => TRUNC(SYSDATE) + 1 + (2*60 + 15)/(24*60),
        repeat_interval => 'FREQ=DAILY; BYHOUR=2; BYMINUTE=15',
        enabled         => TRUE,
        comments        => 'PO Sentinel: daily problem orders refresh and notify'
    );
END;
/

COMMIT;
