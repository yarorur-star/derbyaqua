-- ============================================================================
-- derbyaqua: SQL-запросы для построения финальных таблиц (лист = таблица)
-- Диалект: Apache Derby 10.14 (Java DB). Schema FISHSTAT.
--
-- Общие ограничения диалекта Derby, учтенные в запросах:
--   * нет FILTER / PIVOT / LATERAL / GENERATE_SERIES - горизонтальный разворот
--     лет реализован явными SUM(CASE WHEN ... THEN col ELSE 0 END);
--   * агрегация по широкоформатной таблице (VALUE_Y1950..VALUE_{V4}) невозможна
--     без перечисления столбцов, поэтому годы "зашиты" в SELECT явно;
--   * последние 5 лет берутся из данных (см. query 0), на момент выгрузки это
--     2020-2024; в файле годы заданы плейсхолдерами VALUE_{V0}..VALUE_{V4}
--     и {Y0}..{Y4}, которые программа подставляет динамически;
--   * NULL трактуются как 0 (COALESCE), символы достоверности SYMBOL_* игнорируются;
--   * сортировка только по псевдонимамам/столбцам SELECT (ограничение ORDER BY Derby).
--
-- Группировки видов (REF_YEARBOOK_GROUP):
--   ID 00000001 "All aquatic organisms" - игнорируется (в REL нет наполнения);
--   ID 00000004 "Other aquatic animals & products" - исключается из расчетов;
--   используются только ID 00000002 (рыба и беспозвоночные) и ID 00000003 (водоросли).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Query 1. Таблица 1. Производство аквакультуры странами, тонн (TSD_AQUACULTURE_QUANTITY)
-- Колонки: №1 все страны (NAME_EN REF_COUNTRY), №2-№6 объемы за последние 5 лет.
-- Включаются ВСЕ страны справочника (248), даже с нулевыми данными - строки
-- со всеми нулями удаляются пост-обработкой Python.
-- ----------------------------------------------------------------------------
SELECT
    C.NAME_EN                                             AS COUNTRY_NAME,
    COALESCE(SUM(CASE WHEN Q.MEASURE = 'Q_tlw' THEN Q.VALUE_{V0} END), 0) AS {Y0},
    COALESCE(SUM(CASE WHEN Q.MEASURE = 'Q_tlw' THEN Q.VALUE_{V1} END), 0) AS {Y1},
    COALESCE(SUM(CASE WHEN Q.MEASURE = 'Q_tlw' THEN Q.VALUE_{V2} END), 0) AS {Y2},
    COALESCE(SUM(CASE WHEN Q.MEASURE = 'Q_tlw' THEN Q.VALUE_{V3} END), 0) AS {Y3},
    COALESCE(SUM(CASE WHEN Q.MEASURE = 'Q_tlw' THEN Q.VALUE_{V4} END), 0) AS {Y4}
FROM REF_COUNTRY C
LEFT JOIN TSD_AQUACULTURE_QUANTITY Q
       ON Q.COUNTRY = C.UN_CODE
GROUP BY C.NAME_EN
ORDER BY C.NAME_EN;

-- ----------------------------------------------------------------------------
-- Query 2. Таблица 2. Производство объектов аквакультуры, тонн (TSD_AQUACULTURE_QUANTITY)
-- Колонки: №1 все виды (NAME_EN REF_SPECIES), №2-№6 объемы за последние 5 лет.
-- Учитывается группировка REF_YEARBOOK_GROUP: виды группы ID 00000004 ("Other
-- aquatic animals & products") исключены; группа ID 00000001 ("All") не используется.
-- Виды с нулевыми данными во всех 5 столбцах удаляются пост-обработкой Python.
-- ----------------------------------------------------------------------------
SELECT
    S.NAME_EN                                                        AS SPECIES_NAME,
    COALESCE(SUM(CASE WHEN Q.VALUE_{V0} IS NULL THEN 0 ELSE Q.VALUE_{V0} END), 0) AS {Y0},
    COALESCE(SUM(CASE WHEN Q.VALUE_{V1} IS NULL THEN 0 ELSE Q.VALUE_{V1} END), 0) AS {Y1},
    COALESCE(SUM(CASE WHEN Q.VALUE_{V2} IS NULL THEN 0 ELSE Q.VALUE_{V2} END), 0) AS {Y2},
    COALESCE(SUM(CASE WHEN Q.VALUE_{V3} IS NULL THEN 0 ELSE Q.VALUE_{V3} END), 0) AS {Y3},
    COALESCE(SUM(CASE WHEN Q.VALUE_{V4} IS NULL THEN 0 ELSE Q.VALUE_{V4} END), 0) AS {Y4}
FROM REF_SPECIES S
JOIN REL_YEARBOOK_GROUP_SPECIES RYS
     ON RYS.CHILD_ID = S.ID
    AND RYS.PARENT_ID IN ('00000002', '00000003')
LEFT JOIN TSD_AQUACULTURE_QUANTITY Q
     ON Q.SPECIES = S.ALPHA_3_CODE
GROUP BY S.NAME_EN
ORDER BY S.NAME_EN;

-- ----------------------------------------------------------------------------
-- Query 3. Таблица 3. Мировое производство аквакультуры во внутренних и морских
-- водах, тонн и тыс.долларов (TSD_AQUACULTURE_QUANTITY + TSD_AQUACULTURE_VALUE)
-- Колонки: №1 группа REF_YEARBOOK_GROUP (ID 00000002/00000003, группы 00000001 и
-- 00000004 не используются), №2 тип вод REF_INLAND_MARINE (через REL_INLAND_MARINE_AREA
-- по коду района AREA), №3 тип данных К/С, №4-№8 данные за последние 5 лет.
-- Строки "ВСЕГО", "в том числе", итоговые группы формирует Python.
-- ----------------------------------------------------------------------------
SELECT
    YG.NAME_EN                                                        AS YB_GROUP,
    IM.NAME_EN                                                        AS WATER_TYPE,
    D.DATA_TYPE                                                       AS DATA_TYPE,
    COALESCE(SUM(CASE WHEN D.DATA_TYPE = 'K' AND Q.VALUE_{V0} IS NULL THEN 0
                      WHEN D.DATA_TYPE = 'K' THEN Q.VALUE_{V0}
                      WHEN D.DATA_TYPE = 'C' AND V.VALUE_{V0} IS NULL THEN 0
                      ELSE V.VALUE_{V0} END), 0)                    AS {Y0},
    COALESCE(SUM(CASE WHEN D.DATA_TYPE = 'K' AND Q.VALUE_{V1} IS NULL THEN 0
                      WHEN D.DATA_TYPE = 'K' THEN Q.VALUE_{V1}
                      WHEN D.DATA_TYPE = 'C' AND V.VALUE_{V1} IS NULL THEN 0
                      ELSE V.VALUE_{V1} END), 0)                    AS {Y1},
    COALESCE(SUM(CASE WHEN D.DATA_TYPE = 'K' AND Q.VALUE_{V2} IS NULL THEN 0
                      WHEN D.DATA_TYPE = 'K' THEN Q.VALUE_{V2}
                      WHEN D.DATA_TYPE = 'C' AND V.VALUE_{V2} IS NULL THEN 0
                      ELSE V.VALUE_{V2} END), 0)                    AS {Y2},
    COALESCE(SUM(CASE WHEN D.DATA_TYPE = 'K' AND Q.VALUE_{V3} IS NULL THEN 0
                      WHEN D.DATA_TYPE = 'K' THEN Q.VALUE_{V3}
                      WHEN D.DATA_TYPE = 'C' AND V.VALUE_{V3} IS NULL THEN 0
                      ELSE V.VALUE_{V3} END), 0)                    AS {Y3},
    COALESCE(SUM(CASE WHEN D.DATA_TYPE = 'K' AND Q.VALUE_{V4} IS NULL THEN 0
                      WHEN D.DATA_TYPE = 'K' THEN Q.VALUE_{V4}
                      WHEN D.DATA_TYPE = 'C' AND V.VALUE_{V4} IS NULL THEN 0
                      ELSE V.VALUE_{V4} END), 0)                    AS {Y4}
FROM REF_YEARBOOK_GROUP YG
JOIN REL_YEARBOOK_GROUP_SPECIES RYS
     ON RYS.PARENT_ID = YG.ID
    AND YG.ID IN ('00000002', '00000003')
JOIN REF_SPECIES S
     ON S.ID = RYS.CHILD_ID
CROSS JOIN (
    SELECT 'Inland waters' AS IM_NAME, 'K' AS DATA_TYPE FROM REF_INLAND_MARINE WHERE ID = '00000001'
    UNION ALL
    SELECT 'Inland waters', 'C' FROM REF_INLAND_MARINE WHERE ID = '00000001'
    UNION ALL
    SELECT 'Marine areas', 'K' FROM REF_INLAND_MARINE WHERE ID = '00000002'
    UNION ALL
    SELECT 'Marine areas', 'C' FROM REF_INLAND_MARINE WHERE ID = '00000002'
) D
JOIN REF_INLAND_MARINE IM
     ON IM.NAME_EN = D.IM_NAME
LEFT JOIN TSD_AQUACULTURE_QUANTITY Q
       ON Q.SPECIES = S.ALPHA_3_CODE
      AND Q.MEASURE = 'Q_tlw'
      AND D.DATA_TYPE = 'K'
      AND Q.AREA IN (SELECT A.CODE
                     FROM REF_AREA A
                     JOIN REL_INLAND_MARINE_AREA RIMA ON RIMA.CHILD_ID = A.ID
                     WHERE RIMA.PARENT_ID = IM.ID)
LEFT JOIN TSD_AQUACULTURE_VALUE V
       ON V.SPECIES = S.ALPHA_3_CODE
      AND V.MEASURE = 'V_USD_1000'
      AND D.DATA_TYPE = 'C'
      AND V.AREA IN (SELECT A2.CODE
                     FROM REF_AREA A2
                     JOIN REL_INLAND_MARINE_AREA RIMA2 ON RIMA2.CHILD_ID = A2.ID
                     WHERE RIMA2.PARENT_ID = IM.ID)
GROUP BY YG.NAME_EN, IM.NAME_EN, D.DATA_TYPE
ORDER BY YG.NAME_EN, IM.NAME_EN, D.DATA_TYPE;

-- ----------------------------------------------------------------------------
-- Query 4. Таблица 4. Мировое производство аквакультуры по странам, тонн и
-- тыс.долларов (TSD_AQUACULTURE_QUANTITY + TSD_AQUACULTURE_VALUE)
-- Колонки: №1 страны, №2 тип данных К/С, №3-№7 данные за последние 5 лет.
-- Только страны-производители (данные по группам 00000002/00000003 REF_YEARBOOK_GROUP);
-- строки стран с нулями в обоих типах удаляет Python. Итоговая строка "ВСЕГО" - Python.
-- ----------------------------------------------------------------------------
SELECT
    C.NAME_EN                                              AS COUNTRY_NAME,
    D.DATA_TYPE                                            AS DATA_TYPE,
    COALESCE(SUM(CASE WHEN D.DATA_TYPE = 'K' AND Q.VALUE_{V0} IS NULL THEN 0
                      WHEN D.DATA_TYPE = 'K' THEN Q.VALUE_{V0}
                      WHEN D.DATA_TYPE = 'C' AND V.VALUE_{V0} IS NULL THEN 0
                      ELSE V.VALUE_{V0} END), 0)          AS {Y0},
    COALESCE(SUM(CASE WHEN D.DATA_TYPE = 'K' AND Q.VALUE_{V1} IS NULL THEN 0
                      WHEN D.DATA_TYPE = 'K' THEN Q.VALUE_{V1}
                      WHEN D.DATA_TYPE = 'C' AND V.VALUE_{V1} IS NULL THEN 0
                      ELSE V.VALUE_{V1} END), 0)          AS {Y1},
    COALESCE(SUM(CASE WHEN D.DATA_TYPE = 'K' AND Q.VALUE_{V2} IS NULL THEN 0
                      WHEN D.DATA_TYPE = 'K' THEN Q.VALUE_{V2}
                      WHEN D.DATA_TYPE = 'C' AND V.VALUE_{V2} IS NULL THEN 0
                      ELSE V.VALUE_{V2} END), 0)          AS {Y2},
    COALESCE(SUM(CASE WHEN D.DATA_TYPE = 'K' AND Q.VALUE_{V3} IS NULL THEN 0
                      WHEN D.DATA_TYPE = 'K' THEN Q.VALUE_{V3}
                      WHEN D.DATA_TYPE = 'C' AND V.VALUE_{V3} IS NULL THEN 0
                      ELSE V.VALUE_{V3} END), 0)          AS {Y3},
    COALESCE(SUM(CASE WHEN D.DATA_TYPE = 'K' AND Q.VALUE_{V4} IS NULL THEN 0
                      WHEN D.DATA_TYPE = 'K' THEN Q.VALUE_{V4}
                      WHEN D.DATA_TYPE = 'C' AND V.VALUE_{V4} IS NULL THEN 0
                      ELSE V.VALUE_{V4} END), 0)          AS {Y4}
FROM REF_COUNTRY C
CROSS JOIN (
    SELECT 'K' AS DATA_TYPE FROM REF_INLAND_MARINE WHERE ID = '00000001'
    UNION ALL
    SELECT 'C' FROM REF_INLAND_MARINE WHERE ID = '00000001'
) D
LEFT JOIN TSD_AQUACULTURE_QUANTITY Q
       ON Q.COUNTRY = C.UN_CODE
      AND Q.MEASURE = 'Q_tlw'
      AND D.DATA_TYPE = 'K'
      AND Q.SPECIES IN (SELECT S1.ALPHA_3_CODE
                        FROM REF_SPECIES S1
                        JOIN REL_YEARBOOK_GROUP_SPECIES R1 ON R1.CHILD_ID = S1.ID
                        WHERE R1.PARENT_ID IN ('00000002', '00000003'))
LEFT JOIN TSD_AQUACULTURE_VALUE V
       ON V.COUNTRY = C.UN_CODE
      AND V.MEASURE = 'V_USD_1000'
      AND V.SPECIES IN (SELECT S2.ALPHA_3_CODE
                        FROM REF_SPECIES S2
                        JOIN REL_YEARBOOK_GROUP_SPECIES R2 ON R2.CHILD_ID = S2.ID
                        WHERE R2.PARENT_ID IN ('00000002', '00000003'))
WHERE EXISTS (SELECT 1 FROM TSD_AQUACULTURE_QUANTITY QE
              WHERE QE.COUNTRY = C.UN_CODE)
   OR EXISTS (SELECT 1 FROM TSD_AQUACULTURE_VALUE VE
              WHERE VE.COUNTRY = C.UN_CODE)
GROUP BY C.NAME_EN, D.DATA_TYPE
ORDER BY C.NAME_EN, D.DATA_TYPE;

-- ----------------------------------------------------------------------------
-- Query 5. Таблица 5. Производство аквакультуры по группам ISSCAAP
-- Колонки: №1 группы ISSCAAP (NAME_EN), №2 код группы (CODE), №3 тип данных К/С,
-- №4-№8 данные за последние 5 лет. Итог "ВСЕГО" - Python.
-- ----------------------------------------------------------------------------
SELECT
    IG.NAME_EN                                             AS ISSCAAP_GROUP,
    IG.CODE                                                AS GROUP_CODE,
    D.DATA_TYPE                                            AS DATA_TYPE,
    COALESCE(SUM(CASE WHEN D.DATA_TYPE = 'K' AND Q.VALUE_{V0} IS NULL THEN 0
                      WHEN D.DATA_TYPE = 'K' THEN Q.VALUE_{V0}
                      WHEN D.DATA_TYPE = 'C' AND V.VALUE_{V0} IS NULL THEN 0
                      ELSE V.VALUE_{V0} END), 0)          AS {Y0},
    COALESCE(SUM(CASE WHEN D.DATA_TYPE = 'K' AND Q.VALUE_{V1} IS NULL THEN 0
                      WHEN D.DATA_TYPE = 'K' THEN Q.VALUE_{V1}
                      WHEN D.DATA_TYPE = 'C' AND V.VALUE_{V1} IS NULL THEN 0
                      ELSE V.VALUE_{V1} END), 0)          AS {Y1},
    COALESCE(SUM(CASE WHEN D.DATA_TYPE = 'K' AND Q.VALUE_{V2} IS NULL THEN 0
                      WHEN D.DATA_TYPE = 'K' THEN Q.VALUE_{V2}
                      WHEN D.DATA_TYPE = 'C' AND V.VALUE_{V2} IS NULL THEN 0
                      ELSE V.VALUE_{V2} END), 0)          AS {Y2},
    COALESCE(SUM(CASE WHEN D.DATA_TYPE = 'K' AND Q.VALUE_{V3} IS NULL THEN 0
                      WHEN D.DATA_TYPE = 'K' THEN Q.VALUE_{V3}
                      WHEN D.DATA_TYPE = 'C' AND V.VALUE_{V3} IS NULL THEN 0
                      ELSE V.VALUE_{V3} END), 0)          AS {Y3},
    COALESCE(SUM(CASE WHEN D.DATA_TYPE = 'K' AND Q.VALUE_{V4} IS NULL THEN 0
                      WHEN D.DATA_TYPE = 'K' THEN Q.VALUE_{V4}
                      WHEN D.DATA_TYPE = 'C' AND V.VALUE_{V4} IS NULL THEN 0
                      ELSE V.VALUE_{V4} END), 0)          AS {Y4}
FROM REF_ISSCAAP_GROUP IG
JOIN REL_ISSCAAP_GROUP_SPECIES RIS
     ON RIS.PARENT_ID = IG.ID
JOIN REF_SPECIES S
     ON S.ID = RIS.CHILD_ID
CROSS JOIN (
    SELECT 'K' AS DATA_TYPE FROM REF_INLAND_MARINE WHERE ID = '00000001'
    UNION ALL
    SELECT 'C' FROM REF_INLAND_MARINE WHERE ID = '00000001'
) D
LEFT JOIN TSD_AQUACULTURE_QUANTITY Q
       ON Q.SPECIES = S.ALPHA_3_CODE
      AND Q.MEASURE = 'Q_tlw'
      AND D.DATA_TYPE = 'K'
LEFT JOIN TSD_AQUACULTURE_VALUE V
       ON V.SPECIES = S.ALPHA_3_CODE
      AND V.MEASURE = 'V_USD_1000'
      AND V.SPECIES NOT IN ('ZZZ')
      AND D.DATA_TYPE = 'C'
GROUP BY IG.NAME_EN, IG.CODE, D.DATA_TYPE
ORDER BY IG.CODE, D.DATA_TYPE;

-- ----------------------------------------------------------------------------
-- Query 6. Таблица 6. Производство аквакультуры по странам и группам ISSCAAP, тонн
-- Колонки: №1 страны, №2 группы ISSCAAP (NAME_EN), №3 код группы (CODE),
-- №4-№8 данные за последние 5 лет. Итоги - Python.
-- ----------------------------------------------------------------------------
SELECT
    C.NAME_EN                                              AS COUNTRY_NAME,
    IG.NAME_EN                                             AS ISSCAAP_GROUP,
    IG.CODE                                                AS GROUP_CODE,
    COALESCE(SUM(CASE WHEN Q.VALUE_{V0} IS NULL THEN 0 ELSE Q.VALUE_{V0} END), 0) AS {Y0},
    COALESCE(SUM(CASE WHEN Q.VALUE_{V1} IS NULL THEN 0 ELSE Q.VALUE_{V1} END), 0) AS {Y1},
    COALESCE(SUM(CASE WHEN Q.VALUE_{V2} IS NULL THEN 0 ELSE Q.VALUE_{V2} END), 0) AS {Y2},
    COALESCE(SUM(CASE WHEN Q.VALUE_{V3} IS NULL THEN 0 ELSE Q.VALUE_{V3} END), 0) AS {Y3},
    COALESCE(SUM(CASE WHEN Q.VALUE_{V4} IS NULL THEN 0 ELSE Q.VALUE_{V4} END), 0) AS {Y4}
FROM TSD_AQUACULTURE_QUANTITY Q
JOIN REF_COUNTRY C
     ON C.UN_CODE = Q.COUNTRY
JOIN REF_SPECIES S
     ON S.ALPHA_3_CODE = Q.SPECIES
JOIN REL_YEARBOOK_GROUP_SPECIES RYS
     ON RYS.CHILD_ID = S.ID
    AND RYS.PARENT_ID IN ('00000002', '00000003')
JOIN REL_ISSCAAP_GROUP_SPECIES RIS
     ON RIS.CHILD_ID = S.ID
JOIN REF_ISSCAAP_GROUP IG
     ON IG.ID = RIS.PARENT_ID
WHERE Q.MEASURE = 'Q_tlw'
GROUP BY C.NAME_EN, IG.NAME_EN, IG.CODE
ORDER BY C.NAME_EN, IG.CODE;

-- ----------------------------------------------------------------------------
-- Query 7. Таблица 7. Производство аквакультуры по странам и видам, тонн
-- Колонки: №1 страны, №2 виды (NAME_EN REF_SPECIES), №3-№7 данные за 5 лет.
-- Итоги - Python.
-- ----------------------------------------------------------------------------
SELECT
    C.NAME_EN                                              AS COUNTRY_NAME,
    S.NAME_EN                                              AS SPECIES_NAME,
    COALESCE(SUM(CASE WHEN Q.VALUE_{V0} IS NULL THEN 0 ELSE Q.VALUE_{V0} END), 0) AS {Y0},
    COALESCE(SUM(CASE WHEN Q.VALUE_{V1} IS NULL THEN 0 ELSE Q.VALUE_{V1} END), 0) AS {Y1},
    COALESCE(SUM(CASE WHEN Q.VALUE_{V2} IS NULL THEN 0 ELSE Q.VALUE_{V2} END), 0) AS {Y2},
    COALESCE(SUM(CASE WHEN Q.VALUE_{V3} IS NULL THEN 0 ELSE Q.VALUE_{V3} END), 0) AS {Y3},
    COALESCE(SUM(CASE WHEN Q.VALUE_{V4} IS NULL THEN 0 ELSE Q.VALUE_{V4} END), 0) AS {Y4}
FROM TSD_AQUACULTURE_QUANTITY Q
JOIN REF_COUNTRY C
     ON C.UN_CODE = Q.COUNTRY
JOIN REF_SPECIES S
     ON S.ALPHA_3_CODE = Q.SPECIES
JOIN REL_YEARBOOK_GROUP_SPECIES RYS
     ON RYS.CHILD_ID = S.ID
    AND RYS.PARENT_ID IN ('00000002', '00000003')
WHERE Q.MEASURE = 'Q_tlw'
GROUP BY C.NAME_EN, S.NAME_EN
ORDER BY C.NAME_EN, S.NAME_EN;

-- ----------------------------------------------------------------------------
-- Query 8. Таблица 8. Производство аквакультуры по видам и среде обитания, тонн
-- Колонки: №1 группы ISSCAAP (NAME_EN), №2 код группы (CODE), №3 вид (NAME_EN),
-- №4 среда обитания (ALPHA_2_CODE REF_ENVIRONMENT: IN/BW/MA), №5-№9 данные за 5 лет.
-- Итоги (общие, по средам, по группам) - Python.
-- ----------------------------------------------------------------------------
SELECT
    IG.NAME_EN                                             AS ISSCAAP_GROUP,
    IG.CODE                                                AS GROUP_CODE,
    S.NAME_EN                                              AS SPECIES_NAME,
    E.ALPHA_2_CODE                                         AS ENV_CODE,
    COALESCE(SUM(CASE WHEN Q.VALUE_{V0} IS NULL THEN 0 ELSE Q.VALUE_{V0} END), 0) AS {Y0},
    COALESCE(SUM(CASE WHEN Q.VALUE_{V1} IS NULL THEN 0 ELSE Q.VALUE_{V1} END), 0) AS {Y1},
    COALESCE(SUM(CASE WHEN Q.VALUE_{V2} IS NULL THEN 0 ELSE Q.VALUE_{V2} END), 0) AS {Y2},
    COALESCE(SUM(CASE WHEN Q.VALUE_{V3} IS NULL THEN 0 ELSE Q.VALUE_{V3} END), 0) AS {Y3},
    COALESCE(SUM(CASE WHEN Q.VALUE_{V4} IS NULL THEN 0 ELSE Q.VALUE_{V4} END), 0) AS {Y4}
FROM TSD_AQUACULTURE_QUANTITY Q
JOIN REF_SPECIES S
     ON S.ALPHA_3_CODE = Q.SPECIES
JOIN REL_YEARBOOK_GROUP_SPECIES RYS
     ON RYS.CHILD_ID = S.ID
    AND RYS.PARENT_ID IN ('00000002', '00000003')
JOIN REL_ISSCAAP_GROUP_SPECIES RIS
     ON RIS.CHILD_ID = S.ID
JOIN REF_ISSCAAP_GROUP IG
     ON IG.ID = RIS.PARENT_ID
JOIN REF_ENVIRONMENT E
     ON E.ALPHA_2_CODE = Q.ENVIRONMENT
WHERE Q.MEASURE = 'Q_tlw'
GROUP BY IG.NAME_EN, IG.CODE, S.NAME_EN, E.ALPHA_2_CODE
ORDER BY IG.CODE, S.NAME_EN, E.ALPHA_2_CODE;

-- ----------------------------------------------------------------------------
-- Query 9. Таблица 9. Видовой состав мирового производства аквакультуры, тонн
-- Колонки: №1 группы ISSCAAP (NAME_EN), №2 код группы (CODE), №3 вид (NAME_EN),
-- №4-№8 данные за последние 5 лет. Итоги - Python.
-- ----------------------------------------------------------------------------
SELECT
    IG.NAME_EN                                             AS ISSCAAP_GROUP,
    IG.CODE                                                AS GROUP_CODE,
    S.NAME_EN                                              AS SPECIES_NAME,
    COALESCE(SUM(CASE WHEN Q.VALUE_{V0} IS NULL THEN 0 ELSE Q.VALUE_{V0} END), 0) AS {Y0},
    COALESCE(SUM(CASE WHEN Q.VALUE_{V1} IS NULL THEN 0 ELSE Q.VALUE_{V1} END), 0) AS {Y1},
    COALESCE(SUM(CASE WHEN Q.VALUE_{V2} IS NULL THEN 0 ELSE Q.VALUE_{V2} END), 0) AS {Y2},
    COALESCE(SUM(CASE WHEN Q.VALUE_{V3} IS NULL THEN 0 ELSE Q.VALUE_{V3} END), 0) AS {Y3},
    COALESCE(SUM(CASE WHEN Q.VALUE_{V4} IS NULL THEN 0 ELSE Q.VALUE_{V4} END), 0) AS {Y4}
FROM TSD_AQUACULTURE_QUANTITY Q
JOIN REF_SPECIES S
     ON S.ALPHA_3_CODE = Q.SPECIES
JOIN REL_YEARBOOK_GROUP_SPECIES RYS
     ON RYS.CHILD_ID = S.ID
    AND RYS.PARENT_ID IN ('00000002', '00000003')
JOIN REL_ISSCAAP_GROUP_SPECIES RIS
     ON RIS.CHILD_ID = S.ID
JOIN REF_ISSCAAP_GROUP IG
     ON IG.ID = RIS.PARENT_ID
WHERE Q.MEASURE = 'Q_tlw'
GROUP BY IG.NAME_EN, IG.CODE, S.NAME_EN
ORDER BY IG.CODE, S.NAME_EN;
