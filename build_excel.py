#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
derbyaqua: формирование Excel-файла с итоговыми таблицами 1-9 по базе
аквакультуры ФАО (Apache Derby embedded).

Порядок работы:
  1. создается/переиспользуется встроенная база Apache Derby (embedded) со
     схемой FISHSTAT (DDL - aqua_ddl.sql);
  2. таблицы наполняются из CSV-дампов в папке /CSV;
  3. выполняются SQL-запросы диалекта Derby из sql_queries.sql (по одному
     на каждую финальную таблицу);
  4. пост-обработка результатов (заголовки, строки "ВСЕГО", удаление нулевых
     строк, группировка) и запись результата в Excel (лист = таблица).

Требования: Java (JDK/JRE), pip install jaydebeapi pandas openpyxl,
jar-файлы Apache Derby в ./lib (скачиваются автоматически при первом запуске).

Запуск:  python3 build_excel.py [-o result.xlsx] [--years 2020 2021 2022 2023 2024]
"""

import argparse
import io
import os
import re
import shutil
import subprocess
import sys
import urllib.request

import pandas as pd

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CSV_DIR = os.path.join(BASE_DIR, "CSV")
SQL_FILE = os.path.join(BASE_DIR, "sql_queries.sql")
DDL_FILE = os.path.join(BASE_DIR, "aqua_ddl.sql")
DB_DIR = os.path.join(BASE_DIR, "derbydb")
LIB_DIR = os.path.join(BASE_DIR, "lib")

DERBY_VERSION = "10.14.2.0"
DERBY_JARS = ["derby", "derbyshared", "derbytools"]
MAVEN_URL = ("https://repo1.maven.org/maven2/org/apache/derby/{jar}/{ver}/{jar}-{ver}.jar")

SCHEMA = "FISHSTAT"

TABLES = [
    "REF_AREA", "REF_COUNTRY", "REF_ENVIRONMENT", "REF_INLAND_MARINE",
    "REF_ISSCAAP_GROUP", "REF_MEASURE", "REF_SPECIES", "REF_YEARBOOK_GROUP",
    "REL_INLAND_MARINE_AREA", "REL_ISSCAAP_GROUP_SPECIES",
    "REL_YEARBOOK_GROUP_SPECIES", "TSD_AQUACULTURE_QUANTITY",
    "TSD_AQUACULTURE_VALUE",
]

# годовой столбец TSD-таблицы по году
def value_col(year):
    return "VALUE_Y%d" % year


# ---------------------------------------------------------------------------
# Подготовка окружения Derby
# ---------------------------------------------------------------------------
def ensure_jars():
    """Проверяем наличие jar Apache Derby в ./lib, при отсутствии скачиваем."""
    missing = []
    for jar in DERBY_JARS:
        path = os.path.join(LIB_DIR, "%s-%s.jar" % (jar, DERBY_VERSION))
        if not os.path.exists(path) or os.path.getsize(path) < 10000:
            missing.append((jar, path))
    if not missing:
        return
    print("Скачивание jar Apache Derby %s ..." % DERBY_VERSION)
    os.makedirs(LIB_DIR, exist_ok=True)
    for jar, path in missing:
        url = MAVEN_URL.format(jar=jar, ver=DERBY_VERSION)
        print("  %s" % url)
        urllib.request.urlretrieve(url, path)


def classpath():
    return os.pathsep.join(
        os.path.join(LIB_DIR, "%s-%s.jar" % (j, DERBY_VERSION)) for j in DERBY_JARS
    )


def get_connection(create_db):
    """Подключение к embedded Derby через JDBC (jaydebeapi)."""
    import jaydebeapi

    url = "jdbc:derby:%s;user=%s;password=%s;%s" % (
        DB_DIR, SCHEMA, SCHEMA,
        "create=true" if create_db else "create=false")
    conn = jaydebeapi.connect(
        "org.apache.derby.jdbc.EmbeddedDriver", url, classpath())
    return conn


def drop_schema(conn):
    """Удаление всех объектов схемы FISHSTAT (для пересоздания БД из CSV)."""
    cur = conn.cursor()
    rs = conn.jconn.getMetaData().getTables(None, SCHEMA, None, None)
    objs = []
    while rs.next():
        objs.append((rs.getString(3), rs.getString(4)))  # имя, тип
    rs.close()
    for name, otype in objs:
        if otype == "TABLE":
            try:
                cur.execute("ALTER TABLE %s.%s DROP CONSTRAINT ALL" % (SCHEMA, name))
            except Exception:
                pass
    for name, otype in objs:
        try:
            if otype == "TABLE":
                cur.execute("DROP TABLE %s.%s" % (SCHEMA, name))
            elif otype == "INDEX":
                cur.execute("DROP INDEX %s.%s" % (SCHEMA, name))
        except Exception:
            pass
    cur.close()
    conn.commit()


# ---------------------------------------------------------------------------
# Создание БД и загрузка CSV
# ---------------------------------------------------------------------------
def db_exists():
    return os.path.exists(os.path.join(DB_DIR, "db.lck")) or os.path.exists(
        os.path.join(DB_DIR, "log", "log1.dat")
    ) or os.path.isdir(os.path.join(DB_DIR, "seg0"))


def table_count(conn, name):
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM %s.%s" % (SCHEMA, name))
    n = cur.fetchone()[0]
    cur.close()
    return n


TYPE_CODES = {4: "int", 5: "int", 8: "double", -5: "long", 7: "float"}


def load_csv_to_table(conn, table):
    """Загрузка CSV дампа в таблицу Derby. CSV - дамп той же таблицы (имена
    столбцов совпадают с DDL); пустые значения -> NULL; числовые столбцы
    приводятся к типу колонки по метаданным JDBC."""
    path = os.path.join(CSV_DIR, table + ".csv")
    df = pd.read_csv(path, dtype=str, keep_default_na=False, na_values=[""])
    rs = conn.jconn.getMetaData().getColumns(None, SCHEMA, table, None)
    coltypes = {}
    while rs.next():
        coltypes[rs.getString(4).upper()] = TYPE_CODES.get(rs.getInt(6), "str")
    rs.close()
    cols = list(df.columns)
    stmt = "INSERT INTO %s.%s (%s) VALUES (%s)" % (
        SCHEMA, table, ", ".join(cols), ", ".join(["?"] * len(cols)))
    types = [coltypes.get(c.upper(), "str") for c in cols]

    def conv(x, t):
        if x is None or (isinstance(x, str) and (x == "" or x == '""')):
            return None
        if t == "double":
            return float(x)
        if t in ("int",):
            return int(float(x))
        if t == "long":
            return int(x)
        return str(x)

    cur = conn.cursor()
    CHUNK = 1000
    batch = []
    total = 0
    for row in df.itertuples(index=False, name=None):
        batch.append([conv(x, t) for x, t in zip(row, types)])
        if len(batch) >= CHUNK:
            cur.executemany(stmt, batch)
            total += len(batch)
            batch = []
    if batch:
        cur.executemany(stmt, batch)
        total += len(batch)
    conn.commit()
    cur.close()
    print("  %-32s %6d строк загружено" % (table, total))


def prepare_database(force=False):
    """Создание БД (если нужно) и загрузка данных. Возвращает открытое соединение."""
    create = not db_exists()
    conn = get_connection(create)
    if force and not create:
        print("Пересоздание таблиц из CSV (--rebuild-db) ...")
        drop_schema(conn)
    if create or force:
        if create:
            print("Создание базы Derby embedded в %s ..." % DB_DIR)
        # выполняем DDL по операторно (разделитель ';' в конце строки)
        with io.open(DDL_FILE, encoding="utf-8") as f:
            ddl = f.read()
        # убираем комментарии, режем по ';'
        stmts = []
        buf = []
        for line in ddl.splitlines():
            line_wo = re.sub(r"--.*$", "", line).strip()
            if not line_wo:
                continue
            buf.append(line_wo)
            if line_wo.endswith(";"):
                stmts.append(" ".join(buf).rstrip(";"))
                buf = []
        cur = conn.cursor()
        for s in stmts:
            try:
                cur.execute(s)
            except Exception as e:
                msg = str(e)
                # повторное создание схемы/индексов допустимо пропустить
                if "already exists" not in msg and "SQLState: X0Y32" not in msg:
                    raise
        conn.commit()
        cur.close()
        print("Загрузка CSV-дампов в таблицы ...")
        for t in TABLES:
            if table_count(conn, t) == 0:
                load_csv_to_table(conn, t)
        # служебная таблица последних лет формируется в run_queries
    else:
        print("Использование существующей базы Derby в %s" % DB_DIR)
    return conn


# ---------------------------------------------------------------------------
# Определение последних 5 лет и параметризация запросов
# ---------------------------------------------------------------------------
def detect_last_years(conn, n=5):
    """Последние n лет, в которых в основных таблицах есть ненулевые данные.
    Derby не поддерживает динамический список столбцов, поэтому годы определяются
    перебором годовых столбцов TSD-таблиц (столбцы берутся из метаданных JDBC)."""
    cur = conn.cursor()
    yearcols = set()
    for table in ("TSD_AQUACULTURE_QUANTITY", "TSD_AQUACULTURE_VALUE"):
        rs = conn.jconn.getMetaData().getColumns(None, SCHEMA, table, None)
        while rs.next():
            name = rs.getString(4).upper()
            m = re.match(r"^VALUE_Y(\d{4})$", name)
            if m:
                yearcols.add(int(m.group(1)))
        rs.close()
    years = []
    for y in sorted(yearcols, reverse=True):
        if len(years) >= n:
            break
        col = value_col(y)
        found = False
        for table in ("TSD_AQUACULTURE_QUANTITY", "TSD_AQUACULTURE_VALUE"):
            cur.execute("SELECT COUNT(*) FROM %s.%s WHERE COALESCE(%s,0) <> 0"
                        % (SCHEMA, table, col))
            if cur.fetchone()[0] > 0:
                found = True
                break
        if found:
            years.append(y)
    cur.close()
    return sorted(years)[-n:]


def parametrize(sql, years):
    """Подстановка фактических последних лет вместо плейсхолдеров шаблона:
    VALUE_{Vi} -> VALUE_Y<год>, {Yi} -> Y<год> (псевдонимы столбцов результата)."""
    out = sql
    for i, y in enumerate(years):
        out = out.replace("{V%d}" % i, "Y%d" % y)
        out = out.replace("{Y%d}" % i, "Y%d" % y)
    return out


# ---------------------------------------------------------------------------
# Выполнение запросов
# ---------------------------------------------------------------------------
def read_queries(path):
    with io.open(path, encoding="utf-8") as f:
        text = f.read()
    # запросы разделены ';', комментарии '--' удаляем
    chunks = []
    for raw in text.split(";"):
        lines = [re.sub(r"--.*$", "", ln) for ln in raw.splitlines()]
        body = "\n".join(lines).strip()
        if body.upper().startswith("SELECT"):
            chunks.append(body)
    return chunks


def fetch_df(conn, sql):
    cur = conn.cursor()
    cur.execute(sql)
    cols = [d[0] for d in cur.description]
    rows = cur.fetchall()
    cur.close()
    df = pd.DataFrame.from_records(rows, columns=cols)
    return _norm_cols(df)


def _norm_cols(df):
    """Гарантирует псевдонимы Y#### для годовых столбцов результата."""
    new = []
    for c in df.columns:
        m = re.match(r"^.*Y(\d{4})$", str(c))
        if m and not re.match(r"^Y\d{4}$", str(c)):
            new.append("Y" + m.group(1))
        else:
            new.append(str(c))
    df.columns = new
    return df


# ---------------------------------------------------------------------------
# Пост-обработка и сборка листов
# ---------------------------------------------------------------------------
TOTAL = "ВСЕГО (итог)"


def num_cols(df):
    return [c for c in df.columns if re.match(r"^Y\d{4}$", c)]


def write_sheet(writer, sheet_name, title, header, rows):
    """Лист Excel: строка 1 - верхняя строка заголовка таблицы,
    строка 2 - шапка колонок, далее строки данных/итогов."""
    from openpyxl.styles import Font, Alignment
    from openpyxl.utils import get_column_letter

    grid = [header] + rows
    ncols = max(len(r) for r in grid)
    grid = [list(r) + [None] * (ncols - len(r)) for r in grid]

    wb = writer.book
    ws = wb.create_sheet(sheet_name)
    # верхняя строка заголовка
    c = ws.cell(row=1, column=1, value=title)
    c.font = Font(bold=True, size=12)
    c.alignment = Alignment(horizontal="center")
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=ncols)
    # шапка колонок
    for j, h in enumerate(grid[0], start=1):
        ws.cell(row=2, column=j, value=h).font = Font(bold=True)
    # данные
    for i, row in enumerate(grid[1:], start=3):
        bold = any(isinstance(v, str) and (v.startswith("ВСЕГО") or v.startswith("ИТОГ"))
                   for v in row[:3] if v is not None)
        for j, val in enumerate(row, start=1):
            cell = ws.cell(row=i, column=j)
            if isinstance(val, (int, float)):
                cell.value = round(val, 3) if isinstance(val, float) else val
                cell.number_format = "#,##0.###"
            elif val is not None:
                cell.value = val
            if bold:
                cell.font = Font(bold=True)
    # ширины колонок
    widths = {}
    for row in grid:
        for j, val in enumerate(row, start=1):
            ln = len(str(val)) if val is not None else 0
            widths[j] = min(48, max(widths.get(j, 9), ln + 2))
    for j, w in widths.items():
        ws.column_dimensions[get_column_letter(j)].width = w
    ws.freeze_panes = "A3"


def fmt_years(years):
    return ["%d" % y for y in years]


def post_t1(raw, years, title):
    """Таблица 1: страны; убрать строки с нулями во всех столбцах данных;
    добавить итог под заголовком."""
    ys = num_cols(raw)
    data = raw[raw[ys].abs().sum(axis=1) > 0].copy()
    total = [TOTAL] + [float(data[c].sum()) for c in ys]
    rows = [total] + [[r[0]] + [float(v) for v in r[1:]] for r in data.itertuples(index=False)]
    header = ["COUNTRY_NAME"] + fmt_years(years)
    return header, rows, title


def post_t2(raw, years, title):
    ys = num_cols(raw)
    data = raw[raw[ys].abs().sum(axis=1) > 0].copy()
    total = [TOTAL] + [float(data[c].sum()) for c in ys]
    rows = [total] + [[r[0]] + [float(v) for v in r[1:]] for r in data.itertuples(index=False)]
    header = ["SPECIES_NAME"] + fmt_years(years)
    return header, rows, title


IM_LABEL = {"Inland waters": "Внутренние районы", "Marine areas": "Морские районы"}
YB_LABEL = {"00000002": "РЫБА И БЕСПОЗВОНОЧНЫЕ", "00000003": "ВОДОРОСЛИ"}


def post_t3(raw, years, title):
    """raw: YB_GROUP, WATER_TYPE, DATA_TYPE(K/C), Y.... ->
    структура листа по заданию:
      ВСЕГО (сумма групп 00000002+00000003) - строки К и С
      в том числе: Морские районы (К/С), Внутренние районы (К/С)
      РЫБА И БЕСПОЗВОНОЧНЫЕ (К/С) + в т.ч. морские/внутренние (К/С)
      ВОДОРОСЛИ (К/С) + в т.ч. морские/внутренние (К/С)."""
    ys = num_cols(raw)
    idx = {(r.YB_GROUP, r.WATER_TYPE, r.DATA_TYPE):
           [float(x or 0) for x in (getattr(r, c) for c in ys)]
           for r in raw.itertuples(index=False)}
    groups = sorted({k[0] for k in idx})

    def sum_where(pred):
        acc = [0.0] * len(ys)
        for k, vals in idx.items():
            if pred(k):
                for i, v in enumerate(vals):
                    acc[i] += v
        return acc

    rows = []
    rows.append(["ВСЕГО", "", "К"] + sum_where(lambda k: k[2] == "K"))
    rows.append(["ВСЕГО", "", "С"] + sum_where(lambda k: k[2] == "C"))
    rows.append(["в том числе:", "", None] + [None] * len(ys))
    rows.append(["", "Морские районы", "К"] + sum_where(lambda k: k[1] == "Marine areas" and k[2] == "K"))
    rows.append(["", "Морские районы", "С"] + sum_where(lambda k: k[1] == "Marine areas" and k[2] == "C"))
    rows.append(["", "Внутренние районы", "К"] + sum_where(lambda k: k[1] == "Inland waters" and k[2] == "K"))
    rows.append(["", "Внутренние районы", "С"] + sum_where(lambda k: k[1] == "Inland waters" and k[2] == "C"))
    for g in groups:
        rows.append([g, "", "К"] + sum_where(lambda k, g=g: k[0] == g and k[2] == "K"))
        rows.append([g, "", "С"] + sum_where(lambda k, g=g: k[0] == g and k[2] == "C"))
        rows.append(["в том числе:", "", None] + [None] * len(ys))
        rows.append(["", "Морские районы", "К"] + sum_where(lambda k, g=g: k[0] == g and k[1] == "Marine areas" and k[2] == "K"))
        rows.append(["", "Морские районы", "С"] + sum_where(lambda k, g=g: k[0] == g and k[1] == "Marine areas" and k[2] == "C"))
        rows.append(["", "Внутренние районы", "К"] + sum_where(lambda k, g=g: k[0] == g and k[1] == "Inland waters" and k[2] == "K"))
        rows.append(["", "Внутренние районы", "С"] + sum_where(lambda k, g=g: k[0] == g and k[1] == "Inland waters" and k[2] == "C"))
    header = ["REF_YEARBOOK_GROUP", "REF_INLAND_MARINE", "DATA_TYPE"] + fmt_years(years)
    return header, rows, title


def post_t4(raw, years, title):
    """raw: COUNTRY_NAME, DATA_TYPE, Y..."""
    ys = num_cols(raw)
    piv = {}
    for r in raw.itertuples(index=False):
        piv.setdefault(r.COUNTRY_NAME, {})[r.DATA_TYPE] = [float(x or 0) for x in r[2:]]
    countries = sorted(piv)
    kept = []
    tot_k = [0.0] * len(ys)
    tot_c = [0.0] * len(ys)
    for cn in countries:
        kv = piv[cn].get("K", [0.0] * len(ys))
        cv = piv[cn].get("C", [0.0] * len(ys))
        if sum(map(abs, kv)) == 0 and sum(map(abs, cv)) == 0:
            continue
        kept.append((cn, kv, cv))
        tot_k = [a + b for a, b in zip(tot_k, kv)]
        tot_c = [a + b for a, b in zip(tot_c, cv)]
    rows = [[TOTAL, "К"] + tot_k, [TOTAL, "С"] + tot_c]
    for cn, kv, cv in kept:
        rows.append([cn, "К"] + kv)
        rows.append([cn, "С"] + cv)
    header = ["COUNTRY_NAME", "DATA_TYPE"] + fmt_years(years)
    return header, rows, title


def post_t5(raw, years, title):
    """raw: ISSCAAP_GROUP, GROUP_CODE, DATA_TYPE, Y..."""
    ys = num_cols(raw)
    recs = list(raw.itertuples(index=False))
    tot_k = [0.0] * len(ys)
    tot_c = [0.0] * len(ys)
    for r in recs:
        tgt = tot_k if r.DATA_TYPE == "K" else tot_c
        for i, c in enumerate(ys):
            tgt[i] += float(getattr(r, c) or 0)
    rows = [[TOTAL, "", "К"] + tot_k, [TOTAL, "", "С"] + tot_c]
    for r in sorted(recs, key=lambda x: (str(x.GROUP_CODE), x.DATA_TYPE)):
        rows.append([r.ISSCAAP_GROUP, r.GROUP_CODE, r.DATA_TYPE] +
                    [float(getattr(r, c) or 0) for c in ys])
    header = ["ISSCAAP_GROUP", "GROUP_CODE", "DATA_TYPE"] + fmt_years(years)
    return header, rows, title


def post_country_group(raw, years, title, extra_label_cols=2):
    """Общая пост-обработка таблиц 6-9: строки данных + итоги по каждой стране
    (для Т6) с нулями в служебных колонках, и общий итог под заголовком.
    Используется для Таблицы 6 (страна+группа)."""
    ys = num_cols(raw)
    recs = list(raw.itertuples(index=False))
    total = [0.0] * len(ys)
    by_country = {}
    for r in recs:
        vals = [float(getattr(r, c) or 0) for c in ys]
        for i, v in enumerate(vals):
            total[i] += v
        by_country.setdefault(r[0], []).append(list(vals))
    rows = [[TOTAL] + [None] * (extra_label_cols) + total]
    for r in recs:
        rows.append(list(r[:len(r) - len(ys)]) + [float(getattr(r, c) or 0) for c in ys])
    # итоги по странам: вставка после последней строки страны (сортировка обеспечивается
    # нулями/пустыми метками в служебных колонках при сортировке листа)
    return rows, total, by_country, ys


def build_t6(raw, years, title):
    """Таблица 6: страна x группа ISSCAAP + итоги по каждой стране (служебные
    колонки №2-№3 = 0 для сортировки) + общий итог."""
    ys = num_cols(raw)
    recs = list(raw.itertuples(index=False))
    total = [0.0] * len(ys)
    for r in recs:
        for i, c in enumerate(ys):
            total[i] += float(getattr(r, c) or 0)
    rows = [[TOTAL, "", ""] + total]
    last_country = None
    country_sum = [0.0] * len(ys)
    for r in sorted(recs, key=lambda x: (x.COUNTRY_NAME, str(x.GROUP_CODE))):
        if last_country is not None and r.COUNTRY_NAME != last_country:
            rows.append([last_country, 0, 0] + country_sum)
            country_sum = [0.0] * len(ys)
        last_country = r.COUNTRY_NAME
        vals = [float(getattr(r, c) or 0) for c in ys]
        rows.append([r.COUNTRY_NAME, r.ISSCAAP_GROUP, r.GROUP_CODE] + vals)
        for i, v in enumerate(vals):
            country_sum[i] += v
    if last_country is not None:
        rows.append([last_country, 0, 0] + country_sum)
    header = ["COUNTRY_NAME", "ISSCAAP_GROUP", "GROUP_CODE"] + fmt_years(years)
    return header, rows, title


def build_t7(raw, years, title):
    """Таблица 7: страна x вид + итоги по каждой стране (колонки №2-№3 = 0 для
    сортировки согласно заданию) + общий итог."""
    ys = num_cols(raw)
    recs = list(raw.itertuples(index=False))
    total = [0.0] * len(ys)
    for r in recs:
        for i, c in enumerate(ys):
            total[i] += float(getattr(r, c) or 0)
    rows = [[TOTAL, "", None] + total]
    last_country = None
    country_sum = [0.0] * len(ys)
    for r in sorted(recs, key=lambda x: (x.COUNTRY_NAME, x.SPECIES_NAME)):
        if last_country is not None and r.COUNTRY_NAME != last_country:
            rows.append([last_country, 0, 0] + country_sum)
            country_sum = [0.0] * len(ys)
        last_country = r.COUNTRY_NAME
        vals = [float(getattr(r, c) or 0) for c in ys]
        rows.append([r.COUNTRY_NAME, r.SPECIES_NAME] + vals)
        for i, v in enumerate(vals):
            country_sum[i] += v
    if last_country is not None:
        rows.append([last_country, 0, 0] + country_sum)
    header = ["COUNTRY_NAME", "SPECIES_NAME"] + fmt_years(years)
    return header, rows, title


def build_t8(raw, years, title):
    """Таблица 8: группа ISSCAAP x вид x среда обитания.
    Общий итог + итоги по средам IN/BW/MA; внутри каждой группы - итог по группе
    и итоги по средам; удалить видовые строки с нулями во всех столбцах данных."""
    ys = num_cols(raw)
    recs = list(raw.itertuples(index=False))
    envs = ["IN", "BW", "MA"]

    def svals(items):
        acc = [0.0] * len(ys)
        for r in items:
            for i, c in enumerate(ys):
                acc[i] += float(getattr(r, c) or 0)
        return acc

    nonzero = [r for r in recs if any(float(getattr(r, c) or 0) != 0 for c in ys)]
    groups = {}
    for r in nonzero:
        groups.setdefault((str(r.GROUP_CODE), r.ISSCAAP_GROUP), []).append(r)
    rows = [["", "", TOTAL, ""] + svals(nonzero)]
    for e in envs:
        rows.append(["", "", "итог по среде " + e, ""] + svals([r for r in nonzero if r.ENV_CODE == e]))
    for (code, gname) in sorted(groups):
        items = groups[(code, gname)]
        rows.append([gname, code, "ИТОГ ПО ГРУППЕ", ""] + svals(items))
        for e in envs:
            sub = [r for r in items if r.ENV_CODE == e]
            if sub:
                rows.append([gname, code, "итог по среде " + e, ""] + svals(sub))
        for r in sorted(items, key=lambda x: (x.SPECIES_NAME, x.ENV_CODE)):
            rows.append([r.ISSCAAP_GROUP, r.GROUP_CODE, r.SPECIES_NAME, r.ENV_CODE] +
                        [float(getattr(r, c) or 0) for c in ys])
    header = ["ISSCAAP_GROUP", "GROUP_CODE", "SPECIES_NAME", "ENV_CODE"] + fmt_years(years)
    return header, rows, title


def build_t9(raw, years, title):
    """Таблица 9: группа ISSCAAP x вид + общий итог + итоги по каждой группе
    (в задании ошибочно упоминается 'по каждой стране'; структура таблицы -
    группы и виды, поэтому итоги формируются по группе-аналогу)."""
    ys = num_cols(raw)
    recs = list(raw.itertuples(index=False))
    total = [0.0] * len(ys)
    for r in recs:
        for i, c in enumerate(ys):
            total[i] += float(getattr(r, c) or 0)
    rows = [[TOTAL, "", None] + total]
    last_group = None
    group_sum = [0.0] * len(ys)
    for r in sorted(recs, key=lambda x: (str(x.GROUP_CODE), x.SPECIES_NAME)):
        if last_group is not None and (r.GROUP_CODE, r.ISSCAAP_GROUP) != last_group:
            rows.append([last_group[1], 0, 0] + group_sum)
            group_sum = [0.0] * len(ys)
        last_group = (r.GROUP_CODE, r.ISSCAAP_GROUP)
        vals = [float(getattr(r, c) or 0) for c in ys]
        rows.append([r.ISSCAAP_GROUP, r.GROUP_CODE, r.SPECIES_NAME] + vals)
        for i, v in enumerate(vals):
            group_sum[i] += v
    if last_group is not None:
        rows.append([last_group[1], 0, 0] + group_sum)
    header = ["ISSCAAP_GROUP", "GROUP_CODE", "SPECIES_NAME"] + fmt_years(years)
    return header, rows, title


# ---------------------------------------------------------------------------
# Основная программа
# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description="Формирование Excel по базе аквакультуры ФАО (Derby)")
    ap.add_argument("-o", "--output", default=os.path.join(BASE_DIR, "aquaculture_result.xlsx"))
    ap.add_argument("--rebuild-db", action="store_true", help="пересоздать базу из CSV")
    ap.add_argument("--years", nargs="+", type=int, default=None,
                    help="явное перечисление лет (по умолчанию - последние 5 лет данных)")
    args = ap.parse_args()

    ensure_jars()
    conn = prepare_database(force=args.rebuild_db)
    try:
        years = args.years or detect_last_years(conn, 5)
        if len(years) != 5:
            raise SystemExit("Не удалось определить 5 последних лет: %s" % years)
        print("Расчетные годы (последние 5 лет данных): %s" % years)

        queries = read_queries(SQL_FILE)
        if len(queries) != 9:
            raise SystemExit("Ожидалось 9 запросов в %s, найдено %d" % (SQL_FILE, len(queries)))
        raws = []
        for i, q in enumerate(queries, start=1):
            sql = parametrize(q, years)
            df = fetch_df(conn, sql)
            print("  Query %d -> %d строк" % (i, len(df)))
            raws.append(df)

        titles = [
            "Таблица 1. Производство аквакультуры странами, тонн",
            "Таблица 2. Производство объектов аквакультуры, тонн",
            "Таблица 3. Мировое производство аквакультуры во внутренних и морских водах, тонн (К) и тыс.долларов (С)",
            "Таблица 4. Мировое производство аквакультуры по странам, тонн (К) и тыс.долларов (С)",
            "Таблица 5. Производство аквакультуры по группам ISSCAAP, тонн (К) и тыс.долларов (С)",
            "Таблица 6. Производство аквакультуры по странам и группам ISSCAAP, тонн",
            "Таблица 7. Производство аквакультуры по странам и видам, тонн",
            "Таблица 8. Производство аквакультуры по видам и среде обитания, тонн",
            "Таблица 9. Видовой состав мирового производства аквакультуры, тонн",
        ]
        sheets = ["Таблица 1", "Таблица 2", "Таблица 3", "Таблица 4", "Таблица 5",
                  "Таблица 6", "Таблица 7", "Таблица 8", "Таблица 9"]

        processed = []
        processed.append(post_t1(raws[0], years, titles[0]))
        processed.append(post_t2(raws[1], years, titles[1]))
        processed.append(post_t3(raws[2], years, titles[2]))
        processed.append(post_t4(raws[3], years, titles[3]))
        processed.append(post_t5(raws[4], years, titles[4]))
        processed.append(build_t6(raws[5], years, titles[5]))
        processed.append(build_t7(raws[6], years, titles[6]))
        processed.append(build_t8(raws[7], years, titles[7]))
        processed.append(build_t9(raws[8], years, titles[8]))

        with pd.ExcelWriter(args.output, engine="openpyxl") as writer:
            for name, (header, rows, title) in zip(sheets, processed):
                write_sheet(writer, name, title, header, rows)
        print("Готово: %s" % args.output)
    finally:
        try:
            conn.close()
        except Exception:
            pass


if __name__ == "__main__":
    main()
