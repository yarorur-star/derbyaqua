-- REF_AREA 28 районов ФАО мирового промысла 
-- коды из поля CODE наполняют поле AREA в таблицах TSD_AQUACULTURE_VALUE и TSD_AQUACULTURE_QUANTITY
create table FISHSTAT.REF_AREA
(
    ID      VARCHAR(20) not null                           -- здесь и далее во всех таблицах, внутренний ID таблицы для индексирования (формат 00000001), используются только как индексы для REL_ реляционных таблиц соответствия одних терминов другим
        primary key,
    EBXID   BIGINT                                         -- здесь и далее во всех таблицах, EBXID - внутренний код (игнорируется)
        constraint UNQ_REF_AREA_EBXID
            unique,
    CODE    VARCHAR(20)                                    -- код района ФАО во внутренней нумерации (формат двухцифровой в текстовом формате, например 03 или 88)
        constraint UNQ_REF_AREA_CODE
            unique,
    NAME_EN VARCHAR(80),                                   -- название района промысла на английском языке
    NAME_FR VARCHAR(80),                                   -- здесь и далее во всех таблицах, поля с языками кроме английского (_EN) игнорируются
    NAME_ES VARCHAR(80),
    NAME_AR VARCHAR(80),
    NAME_ZH VARCHAR(80),
    NAME_RU VARCHAR(80)
);

-- REF_COUNTRY список 248 стран
-- коды из UN_CODE наполняют поле COUNTRY в таблицах TSD_AQUACULTURE_VALUE и TSD_AQUACULTURE_QUANTITY
create table FISHSTAT.REF_COUNTRY
(
    ID               VARCHAR(20) not null
        primary key,
    NAME_EN          VARCHAR(80),                          -- Название страны в стандарте ООН на английском языке
    NAME_FR          VARCHAR(80),
    NAME_ES          VARCHAR(80),
    NAME_AR          VARCHAR(80),
    NAME_ZH          VARCHAR(80),
    NAME_RU          VARCHAR(80),
    ISO_3_CODE       VARCHAR(3),                           -- не используется
    ISO_2_CODE       VARCHAR(2),                           -- не используется
    EBXID            BIGINT
        constraint UNQ_REF_COUNTRY_EBXID
            unique,
    OFFICIAL_NAME_EN VARCHAR(80),                          -- не используется
    OFFICIAL_NAME_FR VARCHAR(80),
    OFFICIAL_NAME_ES VARCHAR(80),
    OFFICIAL_NAME_AR VARCHAR(80),
    OFFICIAL_NAME_ZH VARCHAR(80),
    OFFICIAL_NAME_RU VARCHAR(80),
    UN_CODE          VARCHAR(3)                            -- код ООН страны (3 цифры, возможно с ведущим нулем)
        constraint UNQ_REF_COUNTRY_UN_CODE
            unique,
    ALPHA12_CODE     VARCHAR(12)                           -- не используется
);

-- REF_ENVIRONMENT среда обитания аквакультурного вида, 3 типа
-- коды из поля ALPHA_2_CODE наполняют поле AREA в таблицах TSD_AQUACULTURE_VALUE и TSD_AQUACULTURE_QUANTITY
create table FISHSTAT.REF_ENVIRONMENT
(
    ID           VARCHAR(20) not null
        primary key,
    EBXID        BIGINT
        constraint UNQ_REF_ENVIRONMENT_EBXID
            unique,
    ALPHA_2_CODE VARCHAR(2)                                -- код обозначения среды обитания (IN, BW, MA)
        constraint UNQ_REF_ENVIRONMENT_ALPHA_2_CODE
            unique,
    NAME_EN      VARCHAR(80),                              -- название среды обитания на английском языке
    NAME_FR      VARCHAR(80),
    NAME_ES      VARCHAR(80),
    NAME_AR      VARCHAR(80),
    NAME_ZH      VARCHAR(80),
    NAME_RU      VARCHAR(80)
);

-- REF_INLAND_MARINE список из 2 видов рыбопромысловых вод: морские и внутренние воды
-- районы REF_AREA составляющие группу морских и внутренних описаны в таблице REL_INLAND_MARINE_AREA
create table FISHSTAT.REF_INLAND_MARINE
(
    ID      VARCHAR(20) not null                           -- в данной таблице используется для кодировки морских и вунтренних вод 00000001-00000002
        primary key,
    EBXID   BIGINT
        constraint UNQ_REF_INLAND_MARINE_EBXID
            unique,
    CODE    BIGINT                                         -- код типа вод (не используется)
        constraint UNQ_REF_INLAND_MARINE_CODE
            unique,
    NAME_EN VARCHAR(80),                                   -- название типа вод на английском языке
    NAME_FR VARCHAR(80),
    NAME_ES VARCHAR(80),
    NAME_AR VARCHAR(80),
    NAME_ZH VARCHAR(80),
    NAME_RU VARCHAR(80)
);

-- REF_ISSCAAP_GROUP 50 групп видов промысла ISSCAAP 
-- виды REF_SPECIES составляющие группы REF_ISSCAAP_GROUP описаны в таблице REL_ISSCAAP_GROUP_SPECIES
create table FISHSTAT.REF_ISSCAAP_GROUP
(
    ID      VARCHAR(20) not null
        primary key,
    NAME_EN VARCHAR(80),                                   -- название группы видов на английском языке
    NAME_FR VARCHAR(80),
    NAME_ES VARCHAR(80),
    NAME_AR VARCHAR(80),
    NAME_ZH VARCHAR(80),
    NAME_RU VARCHAR(80),
    EBXID   BIGINT
        constraint UNQ_REF_ISSCAAP_GROUP_EBXID
            unique,
    CODE    BIGINT                                         -- 2-цифровой код ФАО групп ISSCAAP (формата 11 или 93)
        constraint UNQ_REF_ISSCAAP_GROUP_CODE
            unique
);

-- REF_MEASURE 11 единиц измерения (в данной базе используются только две, "V_USD_1000" - "тысяч долларов" и "Q_tpw" - "тонн")
-- коды из поля CODE наполняют поле MEASURE в таблицах TSD_AQUACULTURE_VALUE ("V_USD_1000") и TSD_AQUACULTURE_QUANTITY ("Q_tpw")
create table FISHSTAT.REF_MEASURE
(
    ID              VARCHAR(20) not null
        primary key,
    CODE            VARCHAR(60) not null                   -- код единицы измерения 
        constraint UNQ_REF_MEASURE_CODE
            unique,
    NAME_EN         VARCHAR(80),                           -- наименование единицы измерения на английском языке
    NAME_FR         VARCHAR(80),
    NAME_ES         VARCHAR(80),
    NAME_AR         VARCHAR(80),
    NAME_ZH         VARCHAR(80),
    NAME_RU         VARCHAR(80),
    UNIT            VARCHAR(20) not null,                  -- условное обозначение единицы измерения (не используется)
    UNIT_MULTIPLIER VARCHAR(20) not null,                  -- размерность (не используется)
    SHORT_NAME      VARCHAR(30)                            -- краткое обозначение (не используется)
);

-- REF_SPECIES 4065 видов промысла (из ASFIS List of Species for Fishery Statistics Purposes)
-- коды из поля ALPHA_3_CODE наполняют поле SPECIES в таблицах TSD_AQUACULTURE_VALUE и TSD_AQUACULTURE_QUANTITY
create table FISHSTAT.REF_SPECIES
(
    ID              VARCHAR(20) not null
        primary key,
    SCIENTIFIC_NAME VARCHAR(80),                           -- латинское название (не используется)
    NAME_EN         VARCHAR(80),                           -- название вида промысла на английском языке
    NAME_FR         VARCHAR(80),
    NAME_ES         VARCHAR(80),
    NAME_AR         VARCHAR(80),
    NAME_ZH         VARCHAR(80),
    NAME_RU         VARCHAR(80),
    EBXID           BIGINT
        constraint UNQ_REF_SPECIES_EBXID
            unique,
    TAXONOMIC_CODE  VARCHAR(15)                            -- не используется
        constraint UNQ_REF_SPECIES_TAXONOMIC_CODE
            unique,
    ALPHA_3_CODE    VARCHAR(3)                             -- 3-буквенный код вида 
        constraint UNQ_REF_SPECIES_ALPHA_3_CODE
            unique,
    AUTHOR          VARCHAR(200)                           -- описавший вид автор (не используется)
);

-- REF_YEARBOOK_GROUP 4 группы видов для стат.ежегодника ФАО Yearbook/SOFIA (All - группа не описана, не считается в REL_YEARBOOK_GROUP_SPECIES и формально должна являться суммой оставшихся трех групп - "Fish, crustaceans and molluscs", "Aquatic plants" и "Others")
-- группа с ID 00000001 (All) игнорируется и не используется, группа с ID 00000004 (Others) исключается из расчетов, используются только ID 00000002 и ID 00000003
-- наполнение групп REF_YEARBOOK_GROUP видами REF_SPECIES описано в таблице REL_YEARBOOK_GROUP_SPECIES
create table FISHSTAT.REF_YEARBOOK_GROUP
(
    ID      VARCHAR(20) not null                           -- в данной таблице используется как индекс 00000001-00000004
        primary key,
    NAME_EN VARCHAR(80),                                   -- наименование группы на английском языке
    NAME_FR VARCHAR(80),
    NAME_ES VARCHAR(80),
    NAME_AR VARCHAR(80),
    NAME_ZH VARCHAR(80),
    NAME_RU VARCHAR(80),
    CODE    BIGINT                                         -- 4-цифровой внутренний код 1801-1806 (не используется)
        constraint UNQ_REF_YEARBOOK_GROUP_CODE
            unique,
    EBXID   BIGINT
        constraint UNQ_REF_YEARBOOK_GROUP_EBXID
            unique
);

-- REL_INLAND_MARINE_AREA таблица соответствия районов промысла ФАО группам морских и внутренних вод 
create table FISHSTAT.REL_INLAND_MARINE_AREA
(
    ID        VARCHAR(20) not null
        primary key,
    PARENT_ID VARCHAR(20)                                  -- код поля ID из REF_INLAND_MARINE
        constraint REL_INLAND_MARINE_AREA_PARENT_FK
            references FISHSTAT.REF_INLAND_MARINE
            on delete cascade,
    CHILD_ID  VARCHAR(20)                                  -- код поля ID из REF_AREA
        constraint REL_INLAND_MARINE_AREA_CHILD_FK
            references FISHSTAT.REF_AREA
            on delete cascade
);

create index FISHSTAT.REL_INLAND_MARINE_AREA_IDX
    on FISHSTAT.REL_INLAND_MARINE_AREA (PARENT_ID, CHILD_ID);

-- REL_ISSCAAP_GROUP_SPECIES таблица наполнения групп видов REF_ISSCAAP_GROUP и видами из списка REF_SPECIES 
create table FISHSTAT.REL_ISSCAAP_GROUP_SPECIES
(
    ID        VARCHAR(20) not null
        primary key,
    PARENT_ID VARCHAR(20)                                  -- код поля ID из REF_ISSCAAP_GROUP
        constraint REL_ISSCAAP_GROUP_SPECIES_PARENT_FK
            references FISHSTAT.REF_ISSCAAP_GROUP
            on delete cascade,
    CHILD_ID  VARCHAR(20)                                  -- код поля ID из REF_SPECIES
        constraint REL_ISSCAAP_GROUP_SPECIES_CHILD_FK
            references FISHSTAT.REF_SPECIES
            on delete cascade
);

create index FISHSTAT.REL_ISSCAAP_GROUP_SPECIES_IDX
    on FISHSTAT.REL_ISSCAAP_GROUP_SPECIES (PARENT_ID, CHILD_ID);

-- REL_YEARBOOK_GROUP_SPECIES таблица наполнения групп REF_YEARBOOK_GROUP видами из списка REF_SPECIES 
-- индекса ID 00000001 (все виды) из REF_YEARBOOK_GROUP в данной таблице нет
create table FISHSTAT.REL_YEARBOOK_GROUP_SPECIES
(
    ID        VARCHAR(20) not null
        primary key,
    PARENT_ID VARCHAR(20)                                  -- код поля ID из REF_YEARBOOK_GROUP
        constraint REL_YEARBOOK_GROUP_SPECIES_PARENT_FK
            references FISHSTAT.REF_YEARBOOK_GROUP
            on delete cascade,
    CHILD_ID  VARCHAR(20)                                  -- код поля ID из REF_SPECIES
        constraint REL_YEARBOOK_GROUP_SPECIES_CHILD_FK
            references FISHSTAT.REF_SPECIES
            on delete cascade
);

create index FISHSTAT.REL_YEARBOOK_GROUP_SPECIES_IDX
    on FISHSTAT.REL_YEARBOOK_GROUP_SPECIES (PARENT_ID, CHILD_ID);

-- TSD_AQUACULTURE_QUANTITY основная таблица данных об аквакультура в весе аквакультурного вида
create table FISHSTAT.TSD_AQUACULTURE_QUANTITY
(
    ID           VARCHAR(20) not null
        primary key,
    COUNTRY      VARCHAR(3),                               -- код страны (поле UN_CODE таблицы списка стран REF_COUNTRY)
    SPECIES      VARCHAR(3),                               -- 3-буквенный код промыслового вида (поле ALPHA_3_CODE списка видов REF_SPECIES)
    AREA         VARCHAR(20),                              -- код района промысла (поле CODE из списка районов промысла REF_AREA)
    ENVIRONMENT  VARCHAR(2),                               -- код среды обитания (поле ALPHA_2_CODE из списка REF_ENVIRONMENT)
    MEASURE      VARCHAR(20),                              -- код единицы измерения данных (поле CODE из списка REF_MEASURE)
    VALUE_Y1950  DOUBLE,                                   -- c VALUE_Y1950 до VALUE_Y2024 - данные в единице измерения MEASURE (тонн "Q_tpw")
    SYMBOL_Y1950 VARCHAR(20),                              -- с SYMBOL_Y1950 до SYMBOL_Y2024 - статус достоверности данных соответствующего поля VALUE_Yxxxx в формате Eurostat, эти поля игнорируются и все значения полей VALUE_Yxxxx принимаются за абсолютно точные
    VALUE_Y1951  DOUBLE,
    SYMBOL_Y1951 VARCHAR(20),
    VALUE_Y1952  DOUBLE,
    SYMBOL_Y1952 VARCHAR(20),
    VALUE_Y1953  DOUBLE,
    SYMBOL_Y1953 VARCHAR(20),
    VALUE_Y1954  DOUBLE,
    SYMBOL_Y1954 VARCHAR(20),
    VALUE_Y1955  DOUBLE,
    SYMBOL_Y1955 VARCHAR(20),
    VALUE_Y1956  DOUBLE,
    SYMBOL_Y1956 VARCHAR(20),
    VALUE_Y1957  DOUBLE,
    SYMBOL_Y1957 VARCHAR(20),
    VALUE_Y1958  DOUBLE,
    SYMBOL_Y1958 VARCHAR(20),
    VALUE_Y1959  DOUBLE,
    SYMBOL_Y1959 VARCHAR(20),
    VALUE_Y1960  DOUBLE,
    SYMBOL_Y1960 VARCHAR(20),
    VALUE_Y1961  DOUBLE,
    SYMBOL_Y1961 VARCHAR(20),
    VALUE_Y1962  DOUBLE,
    SYMBOL_Y1962 VARCHAR(20),
    VALUE_Y1963  DOUBLE,
    SYMBOL_Y1963 VARCHAR(20),
    VALUE_Y1964  DOUBLE,
    SYMBOL_Y1964 VARCHAR(20),
    VALUE_Y1965  DOUBLE,
    SYMBOL_Y1965 VARCHAR(20),
    VALUE_Y1966  DOUBLE,
    SYMBOL_Y1966 VARCHAR(20),
    VALUE_Y1967  DOUBLE,
    SYMBOL_Y1967 VARCHAR(20),
    VALUE_Y1968  DOUBLE,
    SYMBOL_Y1968 VARCHAR(20),
    VALUE_Y1969  DOUBLE,
    SYMBOL_Y1969 VARCHAR(20),
    VALUE_Y1970  DOUBLE,
    SYMBOL_Y1970 VARCHAR(20),
    VALUE_Y1971  DOUBLE,
    SYMBOL_Y1971 VARCHAR(20),
    VALUE_Y1972  DOUBLE,
    SYMBOL_Y1972 VARCHAR(20),
    VALUE_Y1973  DOUBLE,
    SYMBOL_Y1973 VARCHAR(20),
    VALUE_Y1974  DOUBLE,
    SYMBOL_Y1974 VARCHAR(20),
    VALUE_Y1975  DOUBLE,
    SYMBOL_Y1975 VARCHAR(20),
    VALUE_Y1976  DOUBLE,
    SYMBOL_Y1976 VARCHAR(20),
    VALUE_Y1977  DOUBLE,
    SYMBOL_Y1977 VARCHAR(20),
    VALUE_Y1978  DOUBLE,
    SYMBOL_Y1978 VARCHAR(20),
    VALUE_Y1979  DOUBLE,
    SYMBOL_Y1979 VARCHAR(20),
    VALUE_Y1980  DOUBLE,
    SYMBOL_Y1980 VARCHAR(20),
    VALUE_Y1981  DOUBLE,
    SYMBOL_Y1981 VARCHAR(20),
    VALUE_Y1982  DOUBLE,
    SYMBOL_Y1982 VARCHAR(20),
    VALUE_Y1983  DOUBLE,
    SYMBOL_Y1983 VARCHAR(20),
    VALUE_Y1984  DOUBLE,
    SYMBOL_Y1984 VARCHAR(20),
    VALUE_Y1985  DOUBLE,
    SYMBOL_Y1985 VARCHAR(20),
    VALUE_Y1986  DOUBLE,
    SYMBOL_Y1986 VARCHAR(20),
    VALUE_Y1987  DOUBLE,
    SYMBOL_Y1987 VARCHAR(20),
    VALUE_Y1988  DOUBLE,
    SYMBOL_Y1988 VARCHAR(20),
    VALUE_Y1989  DOUBLE,
    SYMBOL_Y1989 VARCHAR(20),
    VALUE_Y1990  DOUBLE,
    SYMBOL_Y1990 VARCHAR(20),
    VALUE_Y1991  DOUBLE,
    SYMBOL_Y1991 VARCHAR(20),
    VALUE_Y1992  DOUBLE,
    SYMBOL_Y1992 VARCHAR(20),
    VALUE_Y1993  DOUBLE,
    SYMBOL_Y1993 VARCHAR(20),
    VALUE_Y1994  DOUBLE,
    SYMBOL_Y1994 VARCHAR(20),
    VALUE_Y1995  DOUBLE,
    SYMBOL_Y1995 VARCHAR(20),
    VALUE_Y1996  DOUBLE,
    SYMBOL_Y1996 VARCHAR(20),
    VALUE_Y1997  DOUBLE,
    SYMBOL_Y1997 VARCHAR(20),
    VALUE_Y1998  DOUBLE,
    SYMBOL_Y1998 VARCHAR(20),
    VALUE_Y1999  DOUBLE,
    SYMBOL_Y1999 VARCHAR(20),
    VALUE_Y2000  DOUBLE,
    SYMBOL_Y2000 VARCHAR(20),
    VALUE_Y2001  DOUBLE,
    SYMBOL_Y2001 VARCHAR(20),
    VALUE_Y2002  DOUBLE,
    SYMBOL_Y2002 VARCHAR(20),
    VALUE_Y2003  DOUBLE,
    SYMBOL_Y2003 VARCHAR(20),
    VALUE_Y2004  DOUBLE,
    SYMBOL_Y2004 VARCHAR(20),
    VALUE_Y2005  DOUBLE,
    SYMBOL_Y2005 VARCHAR(20),
    VALUE_Y2006  DOUBLE,
    SYMBOL_Y2006 VARCHAR(20),
    VALUE_Y2007  DOUBLE,
    SYMBOL_Y2007 VARCHAR(20),
    VALUE_Y2008  DOUBLE,
    SYMBOL_Y2008 VARCHAR(20),
    VALUE_Y2009  DOUBLE,
    SYMBOL_Y2009 VARCHAR(20),
    VALUE_Y2010  DOUBLE,
    SYMBOL_Y2010 VARCHAR(20),
    VALUE_Y2011  DOUBLE,
    SYMBOL_Y2011 VARCHAR(20),
    VALUE_Y2012  DOUBLE,
    SYMBOL_Y2012 VARCHAR(20),
    VALUE_Y2013  DOUBLE,
    SYMBOL_Y2013 VARCHAR(20),
    VALUE_Y2014  DOUBLE,
    SYMBOL_Y2014 VARCHAR(20),
    VALUE_Y2015  DOUBLE,
    SYMBOL_Y2015 VARCHAR(20),
    VALUE_Y2016  DOUBLE,
    SYMBOL_Y2016 VARCHAR(20),
    VALUE_Y2017  DOUBLE,
    SYMBOL_Y2017 VARCHAR(20),
    VALUE_Y2018  DOUBLE,
    SYMBOL_Y2018 VARCHAR(20),
    VALUE_Y2019  DOUBLE,
    SYMBOL_Y2019 VARCHAR(20),
    VALUE_Y2020  DOUBLE,
    SYMBOL_Y2020 VARCHAR(20),
    VALUE_Y2021  DOUBLE,
    SYMBOL_Y2021 VARCHAR(20),
    VALUE_Y2022  DOUBLE,
    SYMBOL_Y2022 VARCHAR(20),
    VALUE_Y2023  DOUBLE,
    SYMBOL_Y2023 VARCHAR(20),
    VALUE_Y2024  DOUBLE,
    SYMBOL_Y2024 VARCHAR(20),
    constraint TSD_AQUACULTURE_QUANTITY_KEYS_IDX
        unique (COUNTRY, SPECIES, AREA, ENVIRONMENT, MEASURE)
);

create index FISHSTAT.TSD_AQUACULTURE_QUANTITY_AREA_IDX
    on FISHSTAT.TSD_AQUACULTURE_QUANTITY (AREA);

create index FISHSTAT.TSD_AQUACULTURE_QUANTITY_COUNTRY_IDX
    on FISHSTAT.TSD_AQUACULTURE_QUANTITY (COUNTRY);

create index FISHSTAT.TSD_AQUACULTURE_QUANTITY_ENVIRONMENT_IDX
    on FISHSTAT.TSD_AQUACULTURE_QUANTITY (ENVIRONMENT);

create index FISHSTAT.TSD_AQUACULTURE_QUANTITY_MEASURE_IDX
    on FISHSTAT.TSD_AQUACULTURE_QUANTITY (MEASURE);

create index FISHSTAT.TSD_AQUACULTURE_QUANTITY_SPECIES_IDX
    on FISHSTAT.TSD_AQUACULTURE_QUANTITY (SPECIES);

-- TSD_AQUACULTURE_VALUE основная таблица данных об аквакультура в стоимости аквакультурного вида
-- в отличие от данных по весу, в силу ряда причин эта таблица ведется не с 1950, а с 1984 года
create table FISHSTAT.TSD_AQUACULTURE_VALUE
(
    ID           VARCHAR(20) not null
        primary key,
    COUNTRY      VARCHAR(3),                               -- код страны (поле UN_CODE таблицы списка стран REF_COUNTRY)
    SPECIES      VARCHAR(3),                               -- 3-буквенный код промыслового вида (поле ALPHA_3_CODE списка видов REF_SPECIES)
    AREA         VARCHAR(20),                              -- код района промысла (поле CODE из списка районов промысла REF_AREA)
    ENVIRONMENT  VARCHAR(2),                               -- код среды обитания (поле ALPHA_2_CODE из списка REF_ENVIRONMENT)
    MEASURE      VARCHAR(20),                              -- код единицы измерения данных (поле CODE из списка REF_MEASURE)
    VALUE_Y1984  DOUBLE,                                   -- c VALUE_Y1984 до VALUE_Y2024 - данные в единице измерения MEASURE (тыс.долларов "V_USD_1000")
    SYMBOL_Y1984 VARCHAR(20),                              -- -- с SYMBOL_Y1984 до SYMBOL_Y2024 - статус достоверности данных соответствующего поля VALUE_Yxxxx в формате Eurostat, эти поля игнорируются и все значения полей VALUE_Yxxxx принимаются за абсолютно точные
    VALUE_Y1985  DOUBLE,
    SYMBOL_Y1985 VARCHAR(20),
    VALUE_Y1986  DOUBLE,
    SYMBOL_Y1986 VARCHAR(20),
    VALUE_Y1987  DOUBLE,
    SYMBOL_Y1987 VARCHAR(20),
    VALUE_Y1988  DOUBLE,
    SYMBOL_Y1988 VARCHAR(20),
    VALUE_Y1989  DOUBLE,
    SYMBOL_Y1989 VARCHAR(20),
    VALUE_Y1990  DOUBLE,
    SYMBOL_Y1990 VARCHAR(20),
    VALUE_Y1991  DOUBLE,
    SYMBOL_Y1991 VARCHAR(20),
    VALUE_Y1992  DOUBLE,
    SYMBOL_Y1992 VARCHAR(20),
    VALUE_Y1993  DOUBLE,
    SYMBOL_Y1993 VARCHAR(20),
    VALUE_Y1994  DOUBLE,
    SYMBOL_Y1994 VARCHAR(20),
    VALUE_Y1995  DOUBLE,
    SYMBOL_Y1995 VARCHAR(20),
    VALUE_Y1996  DOUBLE,
    SYMBOL_Y1996 VARCHAR(20),
    VALUE_Y1997  DOUBLE,
    SYMBOL_Y1997 VARCHAR(20),
    VALUE_Y1998  DOUBLE,
    SYMBOL_Y1998 VARCHAR(20),
    VALUE_Y1999  DOUBLE,
    SYMBOL_Y1999 VARCHAR(20),
    VALUE_Y2000  DOUBLE,
    SYMBOL_Y2000 VARCHAR(20),
    VALUE_Y2001  DOUBLE,
    SYMBOL_Y2001 VARCHAR(20),
    VALUE_Y2002  DOUBLE,
    SYMBOL_Y2002 VARCHAR(20),
    VALUE_Y2003  DOUBLE,
    SYMBOL_Y2003 VARCHAR(20),
    VALUE_Y2004  DOUBLE,
    SYMBOL_Y2004 VARCHAR(20),
    VALUE_Y2005  DOUBLE,
    SYMBOL_Y2005 VARCHAR(20),
    VALUE_Y2006  DOUBLE,
    SYMBOL_Y2006 VARCHAR(20),
    VALUE_Y2007  DOUBLE,
    SYMBOL_Y2007 VARCHAR(20),
    VALUE_Y2008  DOUBLE,
    SYMBOL_Y2008 VARCHAR(20),
    VALUE_Y2009  DOUBLE,
    SYMBOL_Y2009 VARCHAR(20),
    VALUE_Y2010  DOUBLE,
    SYMBOL_Y2010 VARCHAR(20),
    VALUE_Y2011  DOUBLE,
    SYMBOL_Y2011 VARCHAR(20),
    VALUE_Y2012  DOUBLE,
    SYMBOL_Y2012 VARCHAR(20),
    VALUE_Y2013  DOUBLE,
    SYMBOL_Y2013 VARCHAR(20),
    VALUE_Y2014  DOUBLE,
    SYMBOL_Y2014 VARCHAR(20),
    VALUE_Y2015  DOUBLE,
    SYMBOL_Y2015 VARCHAR(20),
    VALUE_Y2016  DOUBLE,
    SYMBOL_Y2016 VARCHAR(20),
    VALUE_Y2017  DOUBLE,
    SYMBOL_Y2017 VARCHAR(20),
    VALUE_Y2018  DOUBLE,
    SYMBOL_Y2018 VARCHAR(20),
    VALUE_Y2019  DOUBLE,
    SYMBOL_Y2019 VARCHAR(20),
    VALUE_Y2020  DOUBLE,
    SYMBOL_Y2020 VARCHAR(20),
    VALUE_Y2021  DOUBLE,
    SYMBOL_Y2021 VARCHAR(20),
    VALUE_Y2022  DOUBLE,
    SYMBOL_Y2022 VARCHAR(20),
    VALUE_Y2023  DOUBLE,
    SYMBOL_Y2023 VARCHAR(20),
    VALUE_Y2024  DOUBLE,
    SYMBOL_Y2024 VARCHAR(20),
    constraint TSD_AQUACULTURE_VALUE_KEYS_IDX
        unique (COUNTRY, SPECIES, AREA, ENVIRONMENT, MEASURE)
);

create index FISHSTAT.TSD_AQUACULTURE_VALUE_AREA_IDX
    on FISHSTAT.TSD_AQUACULTURE_VALUE (AREA);

create index FISHSTAT.TSD_AQUACULTURE_VALUE_COUNTRY_IDX
    on FISHSTAT.TSD_AQUACULTURE_VALUE (COUNTRY);

create index FISHSTAT.TSD_AQUACULTURE_VALUE_ENVIRONMENT_IDX
    on FISHSTAT.TSD_AQUACULTURE_VALUE (ENVIRONMENT);

create index FISHSTAT.TSD_AQUACULTURE_VALUE_MEASURE_IDX
    on FISHSTAT.TSD_AQUACULTURE_VALUE (MEASURE);

create index FISHSTAT.TSD_AQUACULTURE_VALUE_SPECIES_IDX
    on FISHSTAT.TSD_AQUACULTURE_VALUE (SPECIES);
