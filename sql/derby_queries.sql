-- ============================================================================
-- derby_queries.sql
-- Запросы к базе данных ФАО по мировому аквакультуре (схема FISHSTAT, Apache Derby)
--
-- Диалект: Apache Derby. Учтены ограничения диалекта:
--   * нет CTE (WITH), нет FILTER (WHERE ...), нет NULLS FIRST/LAST,
--     нет LIMIT/OFFSET (есть только FETCH FIRST n ROWS ONLY);
--   * в ORDER BY нельзя ссылаться на выражение, которого нет в списке выборки,
--     поэтому сортировочные служебные колонки выводятся отдельными столбцами;
--   * поля SYMBOL_Yxxxx (статус достоверности Eurostat) игнорируются, пустые
--     значения VALUE_Yxxxx трактуются как 0 через COALESCE(VALUE_Yxxxx, 0).
--
-- Правила отбора данных (см. README.md):
--   * используются только виды групп REF_YEARBOOK_GROUP с ID '00000002' и
--     '00000003'; группа '00000001' (All aquatic organisms) игнорируется,
--     группа '00000004' (Other aquatic animals & products) исключается;
--   * MEASURE таблицы количества = 'Q_tlw' (тонны живого веса),
--     MEASURE таблицы стоимости = 'V_USD_1000' (тыс. долл. США);
--   * "последние 5 лет" = 2020-2024 (колонки VALUE_Y2020..VALUE_Y2024);
--   * строки со всеми нулями за пять лет удаляются фильтром exists(... <> 0);
--   * имена стран/видов/групп - ровно как в базе (as is).
--
-- РАЗДЕЛ A - подготовка окружения (DDL + импорт CSV дампов из папки /CSV).
-- Выполняется программой build_report.py автоматически либо вручную из ij
-- (CLASSPATH должен включать derby.jar, derbytools.jar, derbyoptionaltools.jar):
--
--   java -cp "$DERBY_HOME/lib/*" org.apache.derby.tools.ij
--   ij> connect 'jdbc:derby:aquadb;create=true';
--   ij> run 'sql/derby_queries.sql';
--
-- После этого выполняются запросы раздела B (каждый - отдельным запросом;
-- ниже они размечены маркерами "-- @query N: ..." для программы сборки отчета).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- РАЗДЕЛ A. Создание схемы, таблиц, представлений и загрузка CSV дампов
-- ---------------------------------------------------------------------------

-- REF_AREA 28 районов ФАО мирового промысла (CODE -> TSD...AREA)
create table FISHSTAT.REF_AREA
(
    ID      VARCHAR(20) not null primary key,
    EBXID   BIGINT,
    CODE    VARCHAR(20),
    NAME_EN VARCHAR(80),
    NAME_FR VARCHAR(80),
    NAME_ES VARCHAR(80),
    NAME_AR VARCHAR(80),
    NAME_ZH VARCHAR(80),
    NAME_RU VARCHAR(80)
);

-- REF_COUNTRY список стран (UN_CODE -> TSD...COUNTRY)
create table FISHSTAT.REF_COUNTRY
(
    ID               VARCHAR(20) not null primary key,
    NAME_EN          VARCHAR(80),
    NAME_FR          VARCHAR(80),
    NAME_ES          VARCHAR(80),
    NAME_AR          VARCHAR(80),
    NAME_ZH          VARCHAR(80),
    NAME_RU          VARCHAR(80),
    ISO_3_CODE       VARCHAR(3),
    ISO_2_CODE       VARCHAR(2),
    EBXID            BIGINT,
    OFFICIAL_NAME_EN VARCHAR(80),
    OFFICIAL_NAME_FR VARCHAR(80),
    OFFICIAL_NAME_ES VARCHAR(80),
    OFFICIAL_NAME_AR VARCHAR(80),
    OFFICIAL_NAME_ZH VARCHAR(80),
    OFFICIAL_NAME_RU VARCHAR(80),
    UN_CODE          VARCHAR(3),
    ALPHA12_CODE     VARCHAR(12)
);

-- REF_ENVIRONMENT среда обитания (ALPHA_2_CODE -> TSD...ENVIRONMENT): IN, BW, MA
create table FISHSTAT.REF_ENVIRONMENT
(
    ID           VARCHAR(20) not null primary key,
    EBXID        BIGINT,
    ALPHA_2_CODE VARCHAR(2),
    NAME_EN      VARCHAR(80),
    NAME_FR      VARCHAR(80),
    NAME_ES      VARCHAR(80),
    NAME_AR      VARCHAR(80),
    NAME_ZH      VARCHAR(80),
    NAME_RU      VARCHAR(80)
);

-- REF_INLAND_MARINE внутренние/морские воды (состав районов - REL_INLAND_MARINE_AREA)
create table FISHSTAT.REF_INLAND_MARINE
(
    ID      VARCHAR(20) not null primary key,
    EBXID   BIGINT,
    CODE    BIGINT,
    NAME_EN VARCHAR(80),
    NAME_FR VARCHAR(80),
    NAME_ES VARCHAR(80),
    NAME_AR VARCHAR(80),
    NAME_ZH VARCHAR(80),
    NAME_RU VARCHAR(80)
);

-- REF_ISSCAAP_GROUP 50 групп видов ISSCAAP (CODE - двузначный номер группы)
create table FISHSTAT.REF_ISSCAAP_GROUP
(
    ID      VARCHAR(20) not null primary key,
    NAME_EN VARCHAR(80),
    NAME_FR VARCHAR(80),
    NAME_ES VARCHAR(80),
    NAME_AR VARCHAR(80),
    NAME_ZH VARCHAR(80),
    NAME_RU VARCHAR(80),
    EBXID   BIGINT,
    CODE    BIGINT
);

-- REF_MEASURE единицы измерения (в данных: Q_tlw - тонны, V_USD_1000 - тыс.долларов)
create table FISHSTAT.REF_MEASURE
(
    ID              VARCHAR(20) not null primary key,
    CODE            VARCHAR(60) not null,
    NAME_EN         VARCHAR(80),
    NAME_FR         VARCHAR(80),
    NAME_ES         VARCHAR(80),
    NAME_AR         VARCHAR(80),
    NAME_ZH         VARCHAR(80),
    NAME_RU         VARCHAR(80),
    UNIT            VARCHAR(20),
    UNIT_MULTIPLIER VARCHAR(20),
    SHORT_NAME      VARCHAR(30)
);

-- REF_SPECIES виды промысла (ALPHA_3_CODE -> TSD...SPECIES)
create table FISHSTAT.REF_SPECIES
(
    ID              VARCHAR(20) not null primary key,
    SCIENTIFIC_NAME VARCHAR(80),
    NAME_EN         VARCHAR(80),
    NAME_FR         VARCHAR(80),
    NAME_ES         VARCHAR(80),
    NAME_AR         VARCHAR(80),
    NAME_ZH         VARCHAR(80),
    NAME_RU         VARCHAR(80),
    EBXID           BIGINT,
    TAXONOMIC_CODE  VARCHAR(15),
    ALPHA_3_CODE    VARCHAR(3),
    AUTHOR          VARCHAR(200)
);

-- REF_YEARBOOK_GROUP 4 группы стат.ежегодника (используются только 00000002, 00000003)
create table FISHSTAT.REF_YEARBOOK_GROUP
(
    ID      VARCHAR(20) not null primary key,
    NAME_EN VARCHAR(80),
    NAME_FR VARCHAR(80),
    NAME_ES VARCHAR(80),
    NAME_AR VARCHAR(80),
    NAME_ZH VARCHAR(80),
    NAME_RU VARCHAR(80),
    CODE    BIGINT,
    EBXID   BIGINT
);

-- REL_INLAND_MARINE_AREA соответствие районов группам морских/внутренних вод
create table FISHSTAT.REL_INLAND_MARINE_AREA
(
    ID        VARCHAR(20) not null primary key,
    PARENT_ID VARCHAR(20),
    CHILD_ID  VARCHAR(20)
);

-- REL_ISSCAAP_GROUP_SPECIES наполнение групп ISSCAAP видами
create table FISHSTAT.REL_ISSCAAP_GROUP_SPECIES
(
    ID        VARCHAR(20) not null primary key,
    PARENT_ID VARCHAR(20),
    CHILD_ID  VARCHAR(20)
);

-- REL_YEARBOOK_GROUP_SPECIES наполнение групп ежегодника видами
create table FISHSTAT.REL_YEARBOOK_GROUP_SPECIES
(
    ID        VARCHAR(20) not null primary key,
    PARENT_ID VARCHAR(20),
    CHILD_ID  VARCHAR(20)
);

-- TSD_AQUACULTURE_QUANTITY данные по весу (тонны), годы 1950-2024
create table FISHSTAT.TSD_AQUACULTURE_QUANTITY
(
    ID           VARCHAR(20) not null primary key,
    COUNTRY      VARCHAR(3),
    SPECIES      VARCHAR(3),
    AREA         VARCHAR(20),
    ENVIRONMENT  VARCHAR(2),
    MEASURE      VARCHAR(20),
    VALUE_Y1950  DOUBLE, SYMBOL_Y1950 VARCHAR(20),
    VALUE_Y1951  DOUBLE, SYMBOL_Y1951 VARCHAR(20),
    VALUE_Y1952  DOUBLE, SYMBOL_Y1952 VARCHAR(20),
    VALUE_Y1953  DOUBLE, SYMBOL_Y1953 VARCHAR(20),
    VALUE_Y1954  DOUBLE, SYMBOL_Y1954 VARCHAR(20),
    VALUE_Y1955  DOUBLE, SYMBOL_Y1955 VARCHAR(20),
    VALUE_Y1956  DOUBLE, SYMBOL_Y1956 VARCHAR(20),
    VALUE_Y1957  DOUBLE, SYMBOL_Y1957 VARCHAR(20),
    VALUE_Y1958  DOUBLE, SYMBOL_Y1958 VARCHAR(20),
    VALUE_Y1959  DOUBLE, SYMBOL_Y1959 VARCHAR(20),
    VALUE_Y1960  DOUBLE, SYMBOL_Y1960 VARCHAR(20),
    VALUE_Y1961  DOUBLE, SYMBOL_Y1961 VARCHAR(20),
    VALUE_Y1962  DOUBLE, SYMBOL_Y1962 VARCHAR(20),
    VALUE_Y1963  DOUBLE, SYMBOL_Y1963 VARCHAR(20),
    VALUE_Y1964  DOUBLE, SYMBOL_Y1964 VARCHAR(20),
    VALUE_Y1965  DOUBLE, SYMBOL_Y1965 VARCHAR(20),
    VALUE_Y1966  DOUBLE, SYMBOL_Y1966 VARCHAR(20),
    VALUE_Y1967  DOUBLE, SYMBOL_Y1967 VARCHAR(20),
    VALUE_Y1968  DOUBLE, SYMBOL_Y1968 VARCHAR(20),
    VALUE_Y1969  DOUBLE, SYMBOL_Y1969 VARCHAR(20),
    VALUE_Y1970  DOUBLE, SYMBOL_Y1970 VARCHAR(20),
    VALUE_Y1971  DOUBLE, SYMBOL_Y1971 VARCHAR(20),
    VALUE_Y1972  DOUBLE, SYMBOL_Y1972 VARCHAR(20),
    VALUE_Y1973  DOUBLE, SYMBOL_Y1973 VARCHAR(20),
    VALUE_Y1974  DOUBLE, SYMBOL_Y1974 VARCHAR(20),
    VALUE_Y1975  DOUBLE, SYMBOL_Y1975 VARCHAR(20),
    VALUE_Y1976  DOUBLE, SYMBOL_Y1976 VARCHAR(20),
    VALUE_Y1977  DOUBLE, SYMBOL_Y1977 VARCHAR(20),
    VALUE_Y1978  DOUBLE, SYMBOL_Y1978 VARCHAR(20),
    VALUE_Y1979  DOUBLE, SYMBOL_Y1979 VARCHAR(20),
    VALUE_Y1980  DOUBLE, SYMBOL_Y1980 VARCHAR(20),
    VALUE_Y1981  DOUBLE, SYMBOL_Y1981 VARCHAR(20),
    VALUE_Y1982  DOUBLE, SYMBOL_Y1982 VARCHAR(20),
    VALUE_Y1983  DOUBLE, SYMBOL_Y1983 VARCHAR(20),
    VALUE_Y1984  DOUBLE, SYMBOL_Y1984 VARCHAR(20),
    VALUE_Y1985  DOUBLE, SYMBOL_Y1985 VARCHAR(20),
    VALUE_Y1986  DOUBLE, SYMBOL_Y1986 VARCHAR(20),
    VALUE_Y1987  DOUBLE, SYMBOL_Y1987 VARCHAR(20),
    VALUE_Y1988  DOUBLE, SYMBOL_Y1988 VARCHAR(20),
    VALUE_Y1989  DOUBLE, SYMBOL_Y1989 VARCHAR(20),
    VALUE_Y1990  DOUBLE, SYMBOL_Y1990 VARCHAR(20),
    VALUE_Y1991  DOUBLE, SYMBOL_Y1991 VARCHAR(20),
    VALUE_Y1992  DOUBLE, SYMBOL_Y1992 VARCHAR(20),
    VALUE_Y1993  DOUBLE, SYMBOL_Y1993 VARCHAR(20),
    VALUE_Y1994  DOUBLE, SYMBOL_Y1994 VARCHAR(20),
    VALUE_Y1995  DOUBLE, SYMBOL_Y1995 VARCHAR(20),
    VALUE_Y1996  DOUBLE, SYMBOL_Y1996 VARCHAR(20),
    VALUE_Y1997  DOUBLE, SYMBOL_Y1997 VARCHAR(20),
    VALUE_Y1998  DOUBLE, SYMBOL_Y1998 VARCHAR(20),
    VALUE_Y1999  DOUBLE, SYMBOL_Y1999 VARCHAR(20),
    VALUE_Y2000  DOUBLE, SYMBOL_Y2000 VARCHAR(20),
    VALUE_Y2001  DOUBLE, SYMBOL_Y2001 VARCHAR(20),
    VALUE_Y2002  DOUBLE, SYMBOL_Y2002 VARCHAR(20),
    VALUE_Y2003  DOUBLE, SYMBOL_Y2003 VARCHAR(20),
    VALUE_Y2004  DOUBLE, SYMBOL_Y2004 VARCHAR(20),
    VALUE_Y2005  DOUBLE, SYMBOL_Y2005 VARCHAR(20),
    VALUE_Y2006  DOUBLE, SYMBOL_Y2006 VARCHAR(20),
    VALUE_Y2007  DOUBLE, SYMBOL_Y2007 VARCHAR(20),
    VALUE_Y2008  DOUBLE, SYMBOL_Y2008 VARCHAR(20),
    VALUE_Y2009  DOUBLE, SYMBOL_Y2009 VARCHAR(20),
    VALUE_Y2010  DOUBLE, SYMBOL_Y2010 VARCHAR(20),
    VALUE_Y2011  DOUBLE, SYMBOL_Y2011 VARCHAR(20),
    VALUE_Y2012  DOUBLE, SYMBOL_Y2012 VARCHAR(20),
    VALUE_Y2013  DOUBLE, SYMBOL_Y2013 VARCHAR(20),
    VALUE_Y2014  DOUBLE, SYMBOL_Y2014 VARCHAR(20),
    VALUE_Y2015  DOUBLE, SYMBOL_Y2015 VARCHAR(20),
    VALUE_Y2016  DOUBLE, SYMBOL_Y2016 VARCHAR(20),
    VALUE_Y2017  DOUBLE, SYMBOL_Y2017 VARCHAR(20),
    VALUE_Y2018  DOUBLE, SYMBOL_Y2018 VARCHAR(20),
    VALUE_Y2019  DOUBLE, SYMBOL_Y2019 VARCHAR(20),
    VALUE_Y2020  DOUBLE, SYMBOL_Y2020 VARCHAR(20),
    VALUE_Y2021  DOUBLE, SYMBOL_Y2021 VARCHAR(20),
    VALUE_Y2022  DOUBLE, SYMBOL_Y2022 VARCHAR(20),
    VALUE_Y2023  DOUBLE, SYMBOL_Y2023 VARCHAR(20),
    VALUE_Y2024  DOUBLE, SYMBOL_Y2024 VARCHAR(20)
);

-- TSD_AQUACULTURE_VALUE данные по стоимости (тыс.долларов), годы 1984-2024
create table FISHSTAT.TSD_AQUACULTURE_VALUE
(
    ID           VARCHAR(20) not null primary key,
    COUNTRY      VARCHAR(3),
    SPECIES      VARCHAR(3),
    AREA         VARCHAR(20),
    ENVIRONMENT  VARCHAR(2),
    MEASURE      VARCHAR(20),
    VALUE_Y1984  DOUBLE, SYMBOL_Y1984 VARCHAR(20),
    VALUE_Y1985  DOUBLE, SYMBOL_Y1985 VARCHAR(20),
    VALUE_Y1986  DOUBLE, SYMBOL_Y1986 VARCHAR(20),
    VALUE_Y1987  DOUBLE, SYMBOL_Y1987 VARCHAR(20),
    VALUE_Y1988  DOUBLE, SYMBOL_Y1988 VARCHAR(20),
    VALUE_Y1989  DOUBLE, SYMBOL_Y1989 VARCHAR(20),
    VALUE_Y1990  DOUBLE, SYMBOL_Y1990 VARCHAR(20),
    VALUE_Y1991  DOUBLE, SYMBOL_Y1991 VARCHAR(20),
    VALUE_Y1992  DOUBLE, SYMBOL_Y1992 VARCHAR(20),
    VALUE_Y1993  DOUBLE, SYMBOL_Y1993 VARCHAR(20),
    VALUE_Y1994  DOUBLE, SYMBOL_Y1994 VARCHAR(20),
    VALUE_Y1995  DOUBLE, SYMBOL_Y1995 VARCHAR(20),
    VALUE_Y1996  DOUBLE, SYMBOL_Y1996 VARCHAR(20),
    VALUE_Y1997  DOUBLE, SYMBOL_Y1997 VARCHAR(20),
    VALUE_Y1998  DOUBLE, SYMBOL_Y1998 VARCHAR(20),
    VALUE_Y1999  DOUBLE, SYMBOL_Y1999 VARCHAR(20),
    VALUE_Y2000  DOUBLE, SYMBOL_Y2000 VARCHAR(20),
    VALUE_Y2001  DOUBLE, SYMBOL_Y2001 VARCHAR(20),
    VALUE_Y2002  DOUBLE, SYMBOL_Y2002 VARCHAR(20),
    VALUE_Y2003  DOUBLE, SYMBOL_Y2003 VARCHAR(20),
    VALUE_Y2004  DOUBLE, SYMBOL_Y2004 VARCHAR(20),
    VALUE_Y2005  DOUBLE, SYMBOL_Y2005 VARCHAR(20),
    VALUE_Y2006  DOUBLE, SYMBOL_Y2006 VARCHAR(20),
    VALUE_Y2007  DOUBLE, SYMBOL_Y2007 VARCHAR(20),
    VALUE_Y2008  DOUBLE, SYMBOL_Y2008 VARCHAR(20),
    VALUE_Y2009  DOUBLE, SYMBOL_Y2009 VARCHAR(20),
    VALUE_Y2010  DOUBLE, SYMBOL_Y2010 VARCHAR(20),
    VALUE_Y2011  DOUBLE, SYMBOL_Y2011 VARCHAR(20),
    VALUE_Y2012  DOUBLE, SYMBOL_Y2012 VARCHAR(20),
    VALUE_Y2013  DOUBLE, SYMBOL_Y2013 VARCHAR(20),
    VALUE_Y2014  DOUBLE, SYMBOL_Y2014 VARCHAR(20),
    VALUE_Y2015  DOUBLE, SYMBOL_Y2015 VARCHAR(20),
    VALUE_Y2016  DOUBLE, SYMBOL_Y2016 VARCHAR(20),
    VALUE_Y2017  DOUBLE, SYMBOL_Y2017 VARCHAR(20),
    VALUE_Y2018  DOUBLE, SYMBOL_Y2018 VARCHAR(20),
    VALUE_Y2019  DOUBLE, SYMBOL_Y2019 VARCHAR(20),
    VALUE_Y2020  DOUBLE, SYMBOL_Y2020 VARCHAR(20),
    VALUE_Y2021  DOUBLE, SYMBOL_Y2021 VARCHAR(20),
    VALUE_Y2022  DOUBLE, SYMBOL_Y2022 VARCHAR(20),
    VALUE_Y2023  DOUBLE, SYMBOL_Y2023 VARCHAR(20),
    VALUE_Y2024  DOUBLE, SYMBOL_Y2024 VARCHAR(20)
);

-- Индексы оригинальной DDL (для скорости joins/group by)
create index TSD_Q_COUNTRY_IDX on FISHSTAT.TSD_AQUACULTURE_QUANTITY (COUNTRY);
create index TSD_Q_SPECIES_IDX on FISHSTAT.TSD_AQUACULTURE_QUANTITY (SPECIES);
create index TSD_Q_ENV_IDX     on FISHSTAT.TSD_AQUACULTURE_QUANTITY (ENVIRONMENT);
create index TSD_V_COUNTRY_IDX on FISHSTAT.TSD_AQUACULTURE_VALUE (COUNTRY);
create index TSD_V_SPECIES_IDX on FISHSTAT.TSD_AQUACULTURE_VALUE (SPECIES);
create index TSD_V_ENV_IDX     on FISHSTAT.TSD_AQUACULTURE_VALUE (ENVIRONMENT);

-- Импорт CSV дампов (процедура SYSCS_UTIL.SYSCS_IMPORT_TABLE требует полного
-- пути к файлу; build_report.py подставляет абсолютный путь к папке /CSV):
CALL SYSCS_UTIL.SYSCS_IMPORT_TABLE ('FISHSTAT','REF_AREA','{CSV}/REF_AREA.csv',null,null,null,0);
CALL SYSCS_UTIL.SYSCS_IMPORT_TABLE ('FISHSTAT','REF_COUNTRY','{CSV}/REF_COUNTRY.csv',null,null,null,0);
CALL SYSCS_UTIL.SYSCS_IMPORT_TABLE ('FISHSTAT','REF_ENVIRONMENT','{CSV}/REF_ENVIRONMENT.csv',null,null,null,0);
CALL SYSCS_UTIL.SYSCS_IMPORT_TABLE ('FISHSTAT','REF_INLAND_MARINE','{CSV}/REF_INLAND_MARINE.csv',null,null,null,0);
CALL SYSCS_UTIL.SYSCS_IMPORT_TABLE ('FISHSTAT','REF_ISSCAAP_GROUP','{CSV}/REF_ISSCAAP_GROUP.csv',null,null,null,0);
CALL SYSCS_UTIL.SYSCS_IMPORT_TABLE ('FISHSTAT','REF_MEASURE','{CSV}/REF_MEASURE.csv',null,null,null,0);
CALL SYSCS_UTIL.SYSCS_IMPORT_TABLE ('FISHSTAT','REF_SPECIES','{CSV}/REF_SPECIES.csv',null,null,null,0);
CALL SYSCS_UTIL.SYSCS_IMPORT_TABLE ('FISHSTAT','REF_YEARBOOK_GROUP','{CSV}/REF_YEARBOOK_GROUP.csv',null,null,null,0);
CALL SYSCS_UTIL.SYSCS_IMPORT_TABLE ('FISHSTAT','REL_INLAND_MARINE_AREA','{CSV}/REL_INLAND_MARINE_AREA.csv',null,null,null,0);
CALL SYSCS_UTIL.SYSCS_IMPORT_TABLE ('FISHSTAT','REL_ISSCAAP_GROUP_SPECIES','{CSV}/REL_ISSCAAP_GROUP_SPECIES.csv',null,null,null,0);
CALL SYSCS_UTIL.SYSCS_IMPORT_TABLE ('FISHSTAT','REL_YEARBOOK_GROUP_SPECIES','{CSV}/REL_YEARBOOK_GROUP_SPECIES.csv',null,null,null,0);
CALL SYSCS_UTIL.SYSCS_IMPORT_TABLE ('FISHSTAT','TSD_AQUACULTURE_QUANTITY','{CSV}/TSD_AQUACULTURE_QUANTITY.csv',null,null,null,0);
CALL SYSCS_UTIL.SYSCS_IMPORT_TABLE ('FISHSTAT','TSD_AQUACULTURE_VALUE','{CSV}/TSD_AQUACULTURE_VALUE.csv',null,null,null,0);

-- ---------------------------------------------------------------------------
-- Представления: базовый фильтр по группам REF_YEARBOOK_GROUP (только 00000002+00000003)
-- ---------------------------------------------------------------------------

-- "Рабочие" виды: только входящие в группы 00000002 (рыба/ракообразные/моллюски и т.д.)
-- и 00000003 (водоросли). Группа 00000001 (All) в REL_YEARBOOK_GROUP_SPECIES
-- отсутствует по определению, группа 00000004 (Others) исключена намеренно.
create view FISHSTAT.V_SPECIES_USED as
select s.ID, s.ALPHA_3_CODE, s.NAME_EN
from FISHSTAT.REF_SPECIES s
where exists (select 1 from FISHSTAT.REL_YEARBOOK_GROUP_SPECIES r
              where r.CHILD_ID = s.ID
                and r.PARENT_ID in ('00000002','00000003'));

-- Количество (тонны) только по "рабочим" видам
create view FISHSTAT.V_QUAN as
select q.COUNTRY, q.SPECIES, q.AREA, q.ENVIRONMENT,
       q.VALUE_Y2020, q.VALUE_Y2021, q.VALUE_Y2022, q.VALUE_Y2023, q.VALUE_Y2024
from FISHSTAT.TSD_AQUACULTURE_QUANTITY q
join FISHSTAT.V_SPECIES_USED u on u.ALPHA_3_CODE = q.SPECIES
where q.MEASURE = 'Q_tlw';

-- Стоимость (тыс.долларов) только по "рабочим" видам
create view FISHSTAT.V_VALU as
select v.COUNTRY, v.SPECIES, v.AREA, v.ENVIRONMENT,
       v.VALUE_Y2020, v.VALUE_Y2021, v.VALUE_Y2022, v.VALUE_Y2023, v.VALUE_Y2024
from FISHSTAT.TSD_AQUACULTURE_VALUE v
join FISHSTAT.V_SPECIES_USED u on u.ALPHA_3_CODE = v.SPECIES
where v.MEASURE = 'V_USD_1000';

-- ---------------------------------------------------------------------------
-- РАЗДЕЛ B. Запросы финальных таблиц (лист Excel = таблица).
-- Сортировочные служебные колонки оставлены в выборке (ограничение Derby),
-- в отчете они скрыты.
-- ---------------------------------------------------------------------------

-- @query 1|Таблица 1|Страны, тонн|Страна|2020|2021|2022|2023|2024|TOTAL_ROW
-- ============================ ТАБЛИЦА 1 =====================================
-- Производство аквакультуры странами, тонн (TSD_AQUACULTURE_QUANTITY).
-- Строка ВСЕГО (TOTAL_ROW=1) первая, далее страны по убыванию последнего года.
select c.NAME_EN as "Country",
       coalesce(sum(q.VALUE_Y2020),0) as "Y2020",
       coalesce(sum(q.VALUE_Y2021),0) as "Y2021",
       coalesce(sum(q.VALUE_Y2022),0) as "Y2022",
       coalesce(sum(q.VALUE_Y2023),0) as "Y2023",
       coalesce(sum(q.VALUE_Y2024),0) as "Y2024",
       0 as "TOTAL_ROW"
from FISHSTAT.REF_COUNTRY c
join FISHSTAT.V_QUAN q on q.COUNTRY = c.UN_CODE
where exists (select 1 from FISHSTAT.V_QUAN x
              where x.COUNTRY = c.UN_CODE
                and (coalesce(x.VALUE_Y2020,0) <> 0 or coalesce(x.VALUE_Y2021,0) <> 0
                  or coalesce(x.VALUE_Y2022,0) <> 0 or coalesce(x.VALUE_Y2023,0) <> 0
                  or coalesce(x.VALUE_Y2024,0) <> 0))
group by c.NAME_EN
union all
select 'ВСЕГО',
       coalesce(sum(q.VALUE_Y2020),0),
       coalesce(sum(q.VALUE_Y2021),0),
       coalesce(sum(q.VALUE_Y2022),0),
       coalesce(sum(q.VALUE_Y2023),0),
       coalesce(sum(q.VALUE_Y2024),0),
       1
from FISHSTAT.V_QUAN q
order by 7 desc, 6 desc, 1 asc;

-- @query 2|Таблица 2|Виды, тонн|Species|2020|2021|2022|2023|2024|TOTAL_ROW
-- ============================ ТАБЛИЦА 2 =====================================
-- Производство объектов аквакультуры, тонн (TSD_AQUACULTURE_QUANTITY).
-- Виды только групп 00000002+00000003; ВСЕГО сверху; по убыванию Y2024.
select s.NAME_EN as "Species",
       coalesce(sum(q.VALUE_Y2020),0) as "Y2020",
       coalesce(sum(q.VALUE_Y2021),0) as "Y2021",
       coalesce(sum(q.VALUE_Y2022),0) as "Y2022",
       coalesce(sum(q.VALUE_Y2023),0) as "Y2023",
       coalesce(sum(q.VALUE_Y2024),0) as "Y2024",
       0 as "TOTAL_ROW"
from FISHSTAT.REF_SPECIES s
join FISHSTAT.V_QUAN q on q.SPECIES = s.ALPHA_3_CODE
where exists (select 1 from FISHSTAT.V_QUAN x
              where x.SPECIES = s.ALPHA_3_CODE
                and (coalesce(x.VALUE_Y2020,0) <> 0 or coalesce(x.VALUE_Y2021,0) <> 0
                  or coalesce(x.VALUE_Y2022,0) <> 0 or coalesce(x.VALUE_Y2023,0) <> 0
                  or coalesce(x.VALUE_Y2024,0) <> 0))
group by s.NAME_EN
union all
select 'ВСЕГО',
       coalesce(sum(q.VALUE_Y2020),0),
       coalesce(sum(q.VALUE_Y2021),0),
       coalesce(sum(q.VALUE_Y2022),0),
       coalesce(sum(q.VALUE_Y2023),0),
       coalesce(sum(q.VALUE_Y2024),0),
       1
from FISHSTAT.V_QUAN q
order by 7 desc, 6 desc, 1 asc;

-- @query 3|Таблица 3|Мировое производство: воды, К и С|Group|Type|Waters|2020|2021|2022|2023|2024|TOTAL_ROW|SRT_GRP|SRT_WAT
-- ============================ ТАБЛИЦА 3 =====================================
-- Мировое производство аквакультуры во внутренних и морских водах,
-- тонн (К) и тыс.долларов (С).
-- Морские районы = REF_AREA с PARENT_ID='00000002' в REL_INLAND_MARINE_AREA,
-- внутренние = PARENT_ID='00000001'. Названия типов вод - из REF_INLAND_MARINE (as is).
-- Порядок строк: блок ВСЕГО (К, затем С; внутри - Морские, Внутренние),
-- затем группа 00000002, затем группа 00000003 (та же структура).
select g.NAME_EN as "Group", 'К' as "Type", w.NAME_EN as "Waters",
       coalesce(sum(q.VALUE_Y2020),0) as "Y2020", coalesce(sum(q.VALUE_Y2021),0) as "Y2021",
       coalesce(sum(q.VALUE_Y2022),0) as "Y2022", coalesce(sum(q.VALUE_Y2023),0) as "Y2023",
       coalesce(sum(q.VALUE_Y2024),0) as "Y2024",
       0 as "TOTAL_ROW", case when g.ID='00000002' then 1 else 2 end as "SRT_GRP",
       case when w.ID='00000002' then 0 else 1 end as "SRT_WAT"
from FISHSTAT.V_QUAN q
join FISHSTAT.REF_SPECIES s on s.ALPHA_3_CODE = q.SPECIES
join FISHSTAT.REL_YEARBOOK_GROUP_SPECIES rs on rs.CHILD_ID = s.ID
join FISHSTAT.REF_YEARBOOK_GROUP g on g.ID = rs.PARENT_ID
join FISHSTAT.REF_AREA a on a.CODE = q.AREA
join FISHSTAT.REL_INLAND_MARINE_AREA rel on rel.CHILD_ID = a.ID
join FISHSTAT.REF_INLAND_MARINE w on w.ID = rel.PARENT_ID
where g.ID in ('00000002','00000003')
group by g.NAME_EN, g.ID, w.NAME_EN, w.ID
union all
select g.NAME_EN, 'С', w.NAME_EN,
       coalesce(sum(v.VALUE_Y2020),0), coalesce(sum(v.VALUE_Y2021),0),
       coalesce(sum(v.VALUE_Y2022),0), coalesce(sum(v.VALUE_Y2023),0),
       coalesce(sum(v.VALUE_Y2024),0),
       0, case when g.ID='00000002' then 1 else 2 end,
       case when w.ID='00000002' then 0 else 1 end
from FISHSTAT.V_VALU v
join FISHSTAT.REF_SPECIES s on s.ALPHA_3_CODE = v.SPECIES
join FISHSTAT.REL_YEARBOOK_GROUP_SPECIES rs on rs.CHILD_ID = s.ID
join FISHSTAT.REF_YEARBOOK_GROUP g on g.ID = rs.PARENT_ID
join FISHSTAT.REF_AREA a on a.CODE = v.AREA
join FISHSTAT.REL_INLAND_MARINE_AREA rel on rel.CHILD_ID = a.ID
join FISHSTAT.REF_INLAND_MARINE w on w.ID = rel.PARENT_ID
where g.ID in ('00000002','00000003')
group by g.NAME_EN, g.ID, w.NAME_EN, w.ID
union all
select 'ВСЕГО', 'К', w.NAME_EN,
       coalesce(sum(q.VALUE_Y2020),0), coalesce(sum(q.VALUE_Y2021),0),
       coalesce(sum(q.VALUE_Y2022),0), coalesce(sum(q.VALUE_Y2023),0),
       coalesce(sum(q.VALUE_Y2024),0),
       1, 0,
       case when w.ID='00000002' then 0 else 1 end
from FISHSTAT.V_QUAN q
join FISHSTAT.REF_AREA a on a.CODE = q.AREA
join FISHSTAT.REL_INLAND_MARINE_AREA rel on rel.CHILD_ID = a.ID
join FISHSTAT.REF_INLAND_MARINE w on w.ID = rel.PARENT_ID
group by w.NAME_EN, w.ID
union all
select 'ВСЕГО', 'С', w.NAME_EN,
       coalesce(sum(v.VALUE_Y2020),0), coalesce(sum(v.VALUE_Y2021),0),
       coalesce(sum(v.VALUE_Y2022),0), coalesce(sum(v.VALUE_Y2023),0),
       coalesce(sum(v.VALUE_Y2024),0),
       1, 0,
       case when w.ID='00000002' then 0 else 1 end
from FISHSTAT.V_VALU v
join FISHSTAT.REF_AREA a on a.CODE = v.AREA
join FISHSTAT.REL_INLAND_MARINE_AREA rel on rel.CHILD_ID = a.ID
join FISHSTAT.REF_INLAND_MARINE w on w.ID = rel.PARENT_ID
group by w.NAME_EN, w.ID
order by 10 asc, 2 asc, 9 desc, 11 asc;

-- @query 4|Таблица 4|Производство по странам, К и С|Country|Type|2020|2021|2022|2023|2024|TOTAL_ROW
-- ============================ ТАБЛИЦА 4 =====================================
-- Мировое производство аквакультуры по странам, тонн (К) и тыс.долларов (С).
-- Две строки (К и С) на страну; страна удалена, если нули в обеих строках.
-- Сортировка: блок ВСЕГО, затем страны по возрастанию имени.
select c.NAME_EN as "Country", 'К' as "Type",
       coalesce(sum(q.VALUE_Y2020),0) as "Y2020", coalesce(sum(q.VALUE_Y2021),0) as "Y2021",
       coalesce(sum(q.VALUE_Y2022),0) as "Y2022", coalesce(sum(q.VALUE_Y2023),0) as "Y2023",
       coalesce(sum(q.VALUE_Y2024),0) as "Y2024",
       0 as "TOTAL_ROW"
from FISHSTAT.REF_COUNTRY c
join FISHSTAT.V_QUAN q on q.COUNTRY = c.UN_CODE
where exists (select 1 from FISHSTAT.V_QUAN x
              where x.COUNTRY = c.UN_CODE
                and (coalesce(x.VALUE_Y2020,0) <> 0 or coalesce(x.VALUE_Y2021,0) <> 0
                  or coalesce(x.VALUE_Y2022,0) <> 0 or coalesce(x.VALUE_Y2023,0) <> 0
                  or coalesce(x.VALUE_Y2024,0) <> 0))
   or exists (select 1 from FISHSTAT.V_VALU y
              where y.COUNTRY = c.UN_CODE
                and (coalesce(y.VALUE_Y2020,0) <> 0 or coalesce(y.VALUE_Y2021,0) <> 0
                  or coalesce(y.VALUE_Y2022,0) <> 0 or coalesce(y.VALUE_Y2023,0) <> 0
                  or coalesce(y.VALUE_Y2024,0) <> 0))
group by c.NAME_EN
union all
select c.NAME_EN, 'С',
       coalesce(sum(v.VALUE_Y2020),0), coalesce(sum(v.VALUE_Y2021),0),
       coalesce(sum(v.VALUE_Y2022),0), coalesce(sum(v.VALUE_Y2023),0),
       coalesce(sum(v.VALUE_Y2024),0),
       0
from FISHSTAT.REF_COUNTRY c
join FISHSTAT.V_VALU v on v.COUNTRY = c.UN_CODE
where exists (select 1 from FISHSTAT.V_QUAN x
              where x.COUNTRY = c.UN_CODE
                and (coalesce(x.VALUE_Y2020,0) <> 0 or coalesce(x.VALUE_Y2021,0) <> 0
                  or coalesce(x.VALUE_Y2022,0) <> 0 or coalesce(x.VALUE_Y2023,0) <> 0
                  or coalesce(x.VALUE_Y2024,0) <> 0))
   or exists (select 1 from FISHSTAT.V_VALU y
              where y.COUNTRY = c.UN_CODE
                and (coalesce(y.VALUE_Y2020,0) <> 0 or coalesce(y.VALUE_Y2021,0) <> 0
                  or coalesce(y.VALUE_Y2022,0) <> 0 or coalesce(y.VALUE_Y2023,0) <> 0
                  or coalesce(y.VALUE_Y2024,0) <> 0))
group by c.NAME_EN
union all
select 'ВСЕГО', 'К',
       coalesce(sum(q.VALUE_Y2020),0), coalesce(sum(q.VALUE_Y2021),0),
       coalesce(sum(q.VALUE_Y2022),0), coalesce(sum(q.VALUE_Y2023),0),
       coalesce(sum(q.VALUE_Y2024),0),
       1
from FISHSTAT.V_QUAN q
union all
select 'ВСЕГО', 'С',
       coalesce(sum(v.VALUE_Y2020),0), coalesce(sum(v.VALUE_Y2021),0),
       coalesce(sum(v.VALUE_Y2022),0), coalesce(sum(v.VALUE_Y2023),0),
       coalesce(sum(v.VALUE_Y2024),0),
       1
from FISHSTAT.V_VALU v
order by 9 desc, 1 asc, 2 asc;

-- @query 5|Таблица 5|Группы ISSCAAP, К и С|ISSCAAP_Group|Code|Type|2020|2021|2022|2023|2024|TOTAL_ROW
-- ============================ ТАБЛИЦА 5 =====================================
-- Производство аквакультуры по группам ISSCAAP, тонн (К) и тыс.долларов (С).
-- Группы с нулями в обеих строках удалены; сортировка: ВСЕГО, затем код группы.
select ig.NAME_EN as "ISSCAAP_Group", ig.CODE as "Code", 'К' as "Type",
       coalesce(sum(q.VALUE_Y2020),0) as "Y2020", coalesce(sum(q.VALUE_Y2021),0) as "Y2021",
       coalesce(sum(q.VALUE_Y2022),0) as "Y2022", coalesce(sum(q.VALUE_Y2023),0) as "Y2023",
       coalesce(sum(q.VALUE_Y2024),0) as "Y2024",
       0 as "TOTAL_ROW"
from FISHSTAT.REF_ISSCAAP_GROUP ig
join FISHSTAT.REL_ISSCAAP_GROUP_SPECIES rel on rel.PARENT_ID = ig.ID
join FISHSTAT.REF_SPECIES s on s.ID = rel.CHILD_ID
join FISHSTAT.V_QUAN q on q.SPECIES = s.ALPHA_3_CODE
where exists (select 1 from FISHSTAT.V_QUAN x
              join FISHSTAT.REF_SPECIES sx on sx.ALPHA_3_CODE = x.SPECIES
              join FISHSTAT.REL_ISSCAAP_GROUP_SPECIES rx on rx.CHILD_ID = sx.ID
              where rx.PARENT_ID = ig.ID
                and (coalesce(x.VALUE_Y2020,0) <> 0 or coalesce(x.VALUE_Y2021,0) <> 0
                  or coalesce(x.VALUE_Y2022,0) <> 0 or coalesce(x.VALUE_Y2023,0) <> 0
                  or coalesce(x.VALUE_Y2024,0) <> 0))
   or exists (select 1 from FISHSTAT.V_VALU y
              join FISHSTAT.REF_SPECIES sy on sy.ALPHA_3_CODE = y.SPECIES
              join FISHSTAT.REL_ISSCAAP_GROUP_SPECIES ry on ry.CHILD_ID = sy.ID
              where ry.PARENT_ID = ig.ID
                and (coalesce(y.VALUE_Y2020,0) <> 0 or coalesce(y.VALUE_Y2021,0) <> 0
                  or coalesce(y.VALUE_Y2022,0) <> 0 or coalesce(y.VALUE_Y2023,0) <> 0
                  or coalesce(y.VALUE_Y2024,0) <> 0))
group by ig.NAME_EN, ig.CODE
union all
select ig.NAME_EN, ig.CODE, 'С',
       coalesce(sum(v.VALUE_Y2020),0), coalesce(sum(v.VALUE_Y2021),0),
       coalesce(sum(v.VALUE_Y2022),0), coalesce(sum(v.VALUE_Y2023),0),
       coalesce(sum(v.VALUE_Y2024),0),
       0
from FISHSTAT.REF_ISSCAAP_GROUP ig
join FISHSTAT.REL_ISSCAAP_GROUP_SPECIES rel on rel.PARENT_ID = ig.ID
join FISHSTAT.REF_SPECIES s on s.ID = rel.CHILD_ID
join FISHSTAT.V_VALU v on v.SPECIES = s.ALPHA_3_CODE
where exists (select 1 from FISHSTAT.V_QUAN x
              join FISHSTAT.REF_SPECIES sx on sx.ALPHA_3_CODE = x.SPECIES
              join FISHSTAT.REL_ISSCAAP_GROUP_SPECIES rx on rx.CHILD_ID = sx.ID
              where rx.PARENT_ID = ig.ID
                and (coalesce(x.VALUE_Y2020,0) <> 0 or coalesce(x.VALUE_Y2021,0) <> 0
                  or coalesce(x.VALUE_Y2022,0) <> 0 or coalesce(x.VALUE_Y2023,0) <> 0
                  or coalesce(x.VALUE_Y2024,0) <> 0))
   or exists (select 1 from FISHSTAT.V_VALU y
              join FISHSTAT.REF_SPECIES sy on sy.ALPHA_3_CODE = y.SPECIES
              join FISHSTAT.REL_ISSCAAP_GROUP_SPECIES ry on ry.CHILD_ID = sy.ID
              where ry.PARENT_ID = ig.ID
                and (coalesce(y.VALUE_Y2020,0) <> 0 or coalesce(y.VALUE_Y2021,0) <> 0
                  or coalesce(y.VALUE_Y2022,0) <> 0 or coalesce(y.VALUE_Y2023,0) <> 0
                  or coalesce(y.VALUE_Y2024,0) <> 0))
group by ig.NAME_EN, ig.CODE
union all
select 'ВСЕГО', 0, 'К',
       coalesce(sum(q.VALUE_Y2020),0), coalesce(sum(q.VALUE_Y2021),0),
       coalesce(sum(q.VALUE_Y2022),0), coalesce(sum(q.VALUE_Y2023),0),
       coalesce(sum(q.VALUE_Y2024),0),
       1
from FISHSTAT.V_QUAN q
union all
select 'ВСЕГО', 0, 'С',
       coalesce(sum(v.VALUE_Y2020),0), coalesce(sum(v.VALUE_Y2021),0),
       coalesce(sum(v.VALUE_Y2022),0), coalesce(sum(v.VALUE_Y2023),0),
       coalesce(sum(v.VALUE_Y2024),0),
       1
from FISHSTAT.V_VALU v
order by 11 desc, 2 asc, 3 asc;

-- @query 6|Таблица 6|Страны и группы ISSCAAP, тонн|Country|ISSCAAP_Group|Code|2020|2021|2022|2023|2024|SORT_COUNTRY|SORT_LEVEL|GRP_CODE
-- ============================ ТАБЛИЦА 6 =====================================
-- Производство аквакультуры по странам и группам ISSCAAP, тонн.
-- Первая строка каждой страны - итог по стране (код группы 0), далее группы.
-- Нулевые строки удалены. Сортировка: ВСЕГО, страна по алфавиту, код группы.
select 'ВСЕГО' as "Country", 'ВСЕГО' as "ISSCAAP_Group", 0 as "Code",
       coalesce(sum(q.VALUE_Y2020),0) as "Y2020", coalesce(sum(q.VALUE_Y2021),0) as "Y2021",
       coalesce(sum(q.VALUE_Y2022),0) as "Y2022", coalesce(sum(q.VALUE_Y2023),0) as "Y2023",
       coalesce(sum(q.VALUE_Y2024),0) as "Y2024",
       '' as "SORT_COUNTRY", 0 as "SORT_LEVEL", 0 as "GRP_CODE"
from FISHSTAT.V_QUAN q
union all
select cc.NAME_EN, 'ИТОГО', 0,
       coalesce(sum(q.VALUE_Y2020),0), coalesce(sum(q.VALUE_Y2021),0),
       coalesce(sum(q.VALUE_Y2022),0), coalesce(sum(q.VALUE_Y2023),0),
       coalesce(sum(q.VALUE_Y2024),0),
       cc.NAME_EN, 0, 0
from FISHSTAT.REF_COUNTRY cc
join FISHSTAT.V_QUAN q on q.COUNTRY = cc.UN_CODE
where exists (select 1 from FISHSTAT.V_QUAN x
              where x.COUNTRY = cc.UN_CODE
                and (coalesce(x.VALUE_Y2020,0) <> 0 or coalesce(x.VALUE_Y2021,0) <> 0
                  or coalesce(x.VALUE_Y2022,0) <> 0 or coalesce(x.VALUE_Y2023,0) <> 0
                  or coalesce(x.VALUE_Y2024,0) <> 0))
group by cc.NAME_EN
union all
select cc.NAME_EN, ig.NAME_EN, ig.CODE,
       coalesce(sum(q.VALUE_Y2020),0), coalesce(sum(q.VALUE_Y2021),0),
       coalesce(sum(q.VALUE_Y2022),0), coalesce(sum(q.VALUE_Y2023),0),
       coalesce(sum(q.VALUE_Y2024),0),
       cc.NAME_EN, 1, ig.CODE
from FISHSTAT.REF_COUNTRY cc
join FISHSTAT.V_QUAN q on q.COUNTRY = cc.UN_CODE
join FISHSTAT.REF_SPECIES s on s.ALPHA_3_CODE = q.SPECIES
join FISHSTAT.REL_ISSCAAP_GROUP_SPECIES rel on rel.CHILD_ID = s.ID
join FISHSTAT.REF_ISSCAAP_GROUP ig on ig.ID = rel.PARENT_ID
where exists (select 1 from FISHSTAT.V_QUAN x
              where x.COUNTRY = cc.UN_CODE
                and (coalesce(x.VALUE_Y2020,0) <> 0 or coalesce(x.VALUE_Y2021,0) <> 0
                  or coalesce(x.VALUE_Y2022,0) <> 0 or coalesce(x.VALUE_Y2023,0) <> 0
                  or coalesce(x.VALUE_Y2024,0) <> 0))
  and exists (select 1 from FISHSTAT.V_QUAN z
              join FISHSTAT.REF_SPECIES sz on sz.ALPHA_3_CODE = z.SPECIES
              join FISHSTAT.REL_ISSCAAP_GROUP_SPECIES rz on rz.CHILD_ID = sz.ID
              where z.COUNTRY = cc.UN_CODE and rz.PARENT_ID = ig.ID
                and (coalesce(z.VALUE_Y2020,0) <> 0 or coalesce(z.VALUE_Y2021,0) <> 0
                  or coalesce(z.VALUE_Y2022,0) <> 0 or coalesce(z.VALUE_Y2023,0) <> 0
                  or coalesce(z.VALUE_Y2024,0) <> 0))
group by cc.NAME_EN, ig.NAME_EN, ig.CODE
order by 12 asc, 10 asc, 13 asc, 11 asc;

-- @query 7|Таблица 7|Страны и виды, тонн|Country|Species|2020|2021|2022|2023|2024|SORT_COUNTRY|SORT_LEVEL|SORT_SPECIES
-- ============================ ТАБЛИЦА 7 =====================================
-- Производство аквакультуры по странам и видам, тонн.
-- Первая строка каждой страны - итог (вид "ИТОГО"), далее виды по алфавиту.
select 'ВСЕГО' as "Country", 'ВСЕГО' as "Species",
       coalesce(sum(q.VALUE_Y2020),0) as "Y2020", coalesce(sum(q.VALUE_Y2021),0) as "Y2021",
       coalesce(sum(q.VALUE_Y2022),0) as "Y2022", coalesce(sum(q.VALUE_Y2023),0) as "Y2023",
       coalesce(sum(q.VALUE_Y2024),0) as "Y2024",
       '' as "SORT_COUNTRY", 0 as "SORT_LEVEL", '' as "SORT_SPECIES"
from FISHSTAT.V_QUAN q
union all
select cc.NAME_EN, 'ИТОГО',
       coalesce(sum(q.VALUE_Y2020),0), coalesce(sum(q.VALUE_Y2021),0),
       coalesce(sum(q.VALUE_Y2022),0), coalesce(sum(q.VALUE_Y2023),0),
       coalesce(sum(q.VALUE_Y2024),0),
       cc.NAME_EN, 0, ''
from FISHSTAT.REF_COUNTRY cc
join FISHSTAT.V_QUAN q on q.COUNTRY = cc.UN_CODE
where exists (select 1 from FISHSTAT.V_QUAN x
              where x.COUNTRY = cc.UN_CODE
                and (coalesce(x.VALUE_Y2020,0) <> 0 or coalesce(x.VALUE_Y2021,0) <> 0
                  or coalesce(x.VALUE_Y2022,0) <> 0 or coalesce(x.VALUE_Y2023,0) <> 0
                  or coalesce(x.VALUE_Y2024,0) <> 0))
group by cc.NAME_EN
union all
select cc.NAME_EN, s.NAME_EN,
       coalesce(sum(q.VALUE_Y2020),0), coalesce(sum(q.VALUE_Y2021),0),
       coalesce(sum(q.VALUE_Y2022),0), coalesce(sum(q.VALUE_Y2023),0),
       coalesce(sum(q.VALUE_Y2024),0),
       cc.NAME_EN, 1, s.NAME_EN
from FISHSTAT.REF_COUNTRY cc
join FISHSTAT.V_QUAN q on q.COUNTRY = cc.UN_CODE
join FISHSTAT.REF_SPECIES s on s.ALPHA_3_CODE = q.SPECIES
where exists (select 1 from FISHSTAT.V_QUAN x
              where x.COUNTRY = cc.UN_CODE
                and (coalesce(x.VALUE_Y2020,0) <> 0 or coalesce(x.VALUE_Y2021,0) <> 0
                  or coalesce(x.VALUE_Y2022,0) <> 0 or coalesce(x.VALUE_Y2023,0) <> 0
                  or coalesce(x.VALUE_Y2024,0) <> 0))
  and exists (select 1 from FISHSTAT.V_QUAN z
              where z.COUNTRY = cc.UN_CODE and z.SPECIES = s.ALPHA_3_CODE
                and (coalesce(z.VALUE_Y2020,0) <> 0 or coalesce(z.VALUE_Y2021,0) <> 0
                  or coalesce(z.VALUE_Y2022,0) <> 0 or coalesce(z.VALUE_Y2023,0) <> 0
                  or coalesce(z.VALUE_Y2024,0) <> 0))
group by cc.NAME_EN, s.NAME_EN
order by 9 asc, 8 asc, 10 asc;

-- @query 8|Таблица 8|Виды и среда обитания, тонн|ISSCAAP_Group|Code|Species|Env|2020|2021|2022|2023|2024|TOTAL_ROW|SRT_TYPE|SRT_GRP|SRT_ENV
-- ============================ ТАБЛИЦА 8 =====================================
-- Производство аквакультуры по видам и среде обитания, тонн.
-- Блоки: ВСЕГО; итоги по всем группам для IN/BW/MA; по каждой группе - её итоги
-- IN/BW/MA и строки вид x среда (нулевые удалены).
-- SRT_TYPE: 0=ВСЕГО, 1=итоги по всем группам, 2=итог группы, 3=строки видов.
select 'ВСЕГО' as "ISSCAAP_Group", 0 as "Code", 'ВСЕГО' as "Species", '' as "Env",
       coalesce(sum(q.VALUE_Y2020),0) as "Y2020", coalesce(sum(q.VALUE_Y2021),0) as "Y2021",
       coalesce(sum(q.VALUE_Y2022),0) as "Y2022", coalesce(sum(q.VALUE_Y2023),0) as "Y2023",
       coalesce(sum(q.VALUE_Y2024),0) as "Y2024",
       1 as "TOTAL_ROW", 0 as "SRT_TYPE", 0 as "SRT_GRP", 0 as "SRT_ENV"
from FISHSTAT.V_QUAN q
union all
select 'Все группы', 0, '', e.ALPHA_2_CODE,
       coalesce(sum(q.VALUE_Y2020),0), coalesce(sum(q.VALUE_Y2021),0),
       coalesce(sum(q.VALUE_Y2022),0), coalesce(sum(q.VALUE_Y2023),0),
       coalesce(sum(q.VALUE_Y2024),0),
       1, 1, 0,
       case e.ALPHA_2_CODE when 'IN' then 0 when 'BW' then 1 when 'MA' then 2 else 9 end
from FISHSTAT.V_QUAN q
join FISHSTAT.REF_ENVIRONMENT e on e.ALPHA_2_CODE = q.ENVIRONMENT
group by e.ALPHA_2_CODE
union all
select ig.NAME_EN, ig.CODE, 'ИТОГО группы', e.ALPHA_2_CODE,
       coalesce(sum(q.VALUE_Y2020),0), coalesce(sum(q.VALUE_Y2021),0),
       coalesce(sum(q.VALUE_Y2022),0), coalesce(sum(q.VALUE_Y2023),0),
       coalesce(sum(q.VALUE_Y2024),0),
       0, 2, ig.CODE,
       case e.ALPHA_2_CODE when 'IN' then 0 when 'BW' then 1 when 'MA' then 2 else 9 end
from FISHSTAT.V_QUAN q
join FISHSTAT.REF_SPECIES s on s.ALPHA_3_CODE = q.SPECIES
join FISHSTAT.REL_ISSCAAP_GROUP_SPECIES rel on rel.CHILD_ID = s.ID
join FISHSTAT.REF_ISSCAAP_GROUP ig on ig.ID = rel.PARENT_ID
join FISHSTAT.REF_ENVIRONMENT e on e.ALPHA_2_CODE = q.ENVIRONMENT
where exists (select 1 from FISHSTAT.V_QUAN z
              join FISHSTAT.REF_SPECIES sz on sz.ALPHA_3_CODE = z.SPECIES
              join FISHSTAT.REL_ISSCAAP_GROUP_SPECIES rz on rz.CHILD_ID = sz.ID
              where rz.PARENT_ID = ig.ID and z.ENVIRONMENT = e.ALPHA_2_CODE
                and (coalesce(z.VALUE_Y2020,0) <> 0 or coalesce(z.VALUE_Y2021,0) <> 0
                  or coalesce(z.VALUE_Y2022,0) <> 0 or coalesce(z.VALUE_Y2023,0) <> 0
                  or coalesce(z.VALUE_Y2024,0) <> 0))
group by ig.NAME_EN, ig.CODE, e.ALPHA_2_CODE
union all
select ig.NAME_EN, ig.CODE, s.NAME_EN, e.ALPHA_2_CODE,
       coalesce(sum(q.VALUE_Y2020),0), coalesce(sum(q.VALUE_Y2021),0),
       coalesce(sum(q.VALUE_Y2022),0), coalesce(sum(q.VALUE_Y2023),0),
       coalesce(sum(q.VALUE_Y2024),0),
       0, 3, ig.CODE, 0
from FISHSTAT.V_QUAN q
join FISHSTAT.REF_SPECIES s on s.ALPHA_3_CODE = q.SPECIES
join FISHSTAT.REL_ISSCAAP_GROUP_SPECIES rel on rel.CHILD_ID = s.ID
join FISHSTAT.REF_ISSCAAP_GROUP ig on ig.ID = rel.PARENT_ID
join FISHSTAT.REF_ENVIRONMENT e on e.ALPHA_2_CODE = q.ENVIRONMENT
where exists (select 1 from FISHSTAT.V_QUAN z
              where z.SPECIES = s.ALPHA_3_CODE and z.ENVIRONMENT = e.ALPHA_2_CODE
                and (coalesce(z.VALUE_Y2020,0) <> 0 or coalesce(z.VALUE_Y2021,0) <> 0
                  or coalesce(z.VALUE_Y2022,0) <> 0 or coalesce(z.VALUE_Y2023,0) <> 0
                  or coalesce(z.VALUE_Y2024,0) <> 0))
group by ig.NAME_EN, ig.CODE, s.NAME_EN, e.ALPHA_2_CODE
order by 12 asc, 11 asc, 13 asc, 14 asc, 3 asc, 4 asc;

-- @query 9|Таблица 9|Видовой состав мирового производства, тонн|ISSCAAP_Group|Code|Species|2020|2021|2022|2023|2024|SRT_TYPE|SRT_GRP|SRT_SPECIES
-- ============================ ТАБЛИЦА 9 =====================================
-- Видовой состав мирового производства аквакультуры, тонн.
-- ВСЕГО, затем по каждой группе ISSCAAP её итог и список видов (по алфавиту).
select 'ВСЕГО' as "ISSCAAP_Group", 0 as "Code", 'ВСЕГО' as "Species",
       coalesce(sum(q.VALUE_Y2020),0) as "Y2020", coalesce(sum(q.VALUE_Y2021),0) as "Y2021",
       coalesce(sum(q.VALUE_Y2022),0) as "Y2022", coalesce(sum(q.VALUE_Y2023),0) as "Y2023",
       coalesce(sum(q.VALUE_Y2024),0) as "Y2024",
       0 as "SRT_TYPE", 0 as "SRT_GRP", '' as "SRT_SPECIES"
from FISHSTAT.V_QUAN q
union all
select ig.NAME_EN, ig.CODE, 'ИТОГО группы',
       coalesce(sum(q.VALUE_Y2020),0), coalesce(sum(q.VALUE_Y2021),0),
       coalesce(sum(q.VALUE_Y2022),0), coalesce(sum(q.VALUE_Y2023),0),
       coalesce(sum(q.VALUE_Y2024),0),
       1, ig.CODE, ''
from FISHSTAT.V_QUAN q
join FISHSTAT.REF_SPECIES s on s.ALPHA_3_CODE = q.SPECIES
join FISHSTAT.REL_ISSCAAP_GROUP_SPECIES rel on rel.CHILD_ID = s.ID
join FISHSTAT.REF_ISSCAAP_GROUP ig on ig.ID = rel.PARENT_ID
where exists (select 1 from FISHSTAT.V_QUAN z
              join FISHSTAT.REF_SPECIES sz on sz.ALPHA_3_CODE = z.SPECIES
              join FISHSTAT.REL_ISSCAAP_GROUP_SPECIES rz on rz.CHILD_ID = sz.ID
              where rz.PARENT_ID = ig.ID
                and (coalesce(z.VALUE_Y2020,0) <> 0 or coalesce(z.VALUE_Y2021,0) <> 0
                  or coalesce(z.VALUE_Y2022,0) <> 0 or coalesce(z.VALUE_Y2023,0) <> 0
                  or coalesce(z.VALUE_Y2024,0) <> 0))
group by ig.NAME_EN, ig.CODE
union all
select ig.NAME_EN, ig.CODE, s.NAME_EN,
       coalesce(sum(q.VALUE_Y2020),0), coalesce(sum(q.VALUE_Y2021),0),
       coalesce(sum(q.VALUE_Y2022),0), coalesce(sum(q.VALUE_Y2023),0),
       coalesce(sum(q.VALUE_Y2024),0),
       2, ig.CODE, s.NAME_EN
from FISHSTAT.V_QUAN q
join FISHSTAT.REF_SPECIES s on s.ALPHA_3_CODE = q.SPECIES
join FISHSTAT.REL_ISSCAAP_GROUP_SPECIES rel on rel.CHILD_ID = s.ID
join FISHSTAT.REF_ISSCAAP_GROUP ig on ig.ID = rel.PARENT_ID
where exists (select 1 from FISHSTAT.V_QUAN z
              where z.SPECIES = s.ALPHA_3_CODE
                and (coalesce(z.VALUE_Y2020,0) <> 0 or coalesce(z.VALUE_Y2021,0) <> 0
                  or coalesce(z.VALUE_Y2022,0) <> 0 or coalesce(z.VALUE_Y2023,0) <> 0
                  or coalesce(z.VALUE_Y2024,0) <> 0))
group by ig.NAME_EN, ig.CODE, s.NAME_EN
order by 9 asc, 10 asc, 11 asc;
