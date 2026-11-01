#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_excel.py — формирование Excel-отчета по заданию "derbyaqua".

План работы (см. README.md):
  1. Поднимается локальная Apache Derby embedded база (./derbydb) — драйвер
     берется ТОЛЬКО из локального файла lib/derby.jar (загрузка из интернета
     в программе не выполняется).
  2. Создается схема FISHSTAT и таблицы по DDL из aqua_ddl.sql.
  3. Данные из дампов /CSV/*.csv загружаются в таблицы.
  4. Выполняются SQL-запросы в диалекте Derby из sql_queries.sql.
  5. Пост-обработка результатов (итоги "ВСЕГО", строки "в том числе",
     удаление полностью нулевых строк, округление до 2 знаков).
  6. Результат пишется в aquaculture_report.xlsx (лист = таблица 1..9).

Зависимости: jpype1, openpyxl (Java 8+ на PATH).
Запуск:     python3 build_excel.py
"""

import csv
import os
import shutil
import sys

BASE = os.path.dirname(os.path.abspath(__file__))
DERBY_JAR = os.path.join(BASE, "lib", "derby.jar")
DB_DIR = os.path.join(BASE, "derbydb")
DDL_FILE = os.path.join(BASE, "aqua_ddl.sql")
SQL_FILE = os.path.join(BASE, "sql_queries.sql")
CSV_DIR = os.path.join(BASE, "CSV")
OUT_XLSX = os.path.join(BASE, "aquaculture_report.xlsx")

YEARS = [2020, 2021, 2022, 2023, 2024]
YEAR_COLS = ["Y%d" % y for y in YEARS]

TABLES = [
    "REF_AREA", "REF_COUNTRY", "REF_ENVIRONMENT", "REF_INLAND_MARINE",
    "REF_ISSCAAP_GROUP", "REF_MEASURE", "REF_SPECIES", "REF_YEARBOOK_GROUP",
    "REL_INLAND_MARINE_AREA", "REL_ISSCAAP_GROUP_SPECIES",
    "REL_YEARBOOK_GROUP_SPECIES", "TSD_AQUACULTURE_QUANTITY",
    "TSD_AQUACULTURE_VALUE",
]

# ---------------------------------------------------------------- JVM / JDBC
import jpype
import jpype.imports  # noqa: F401

JString = None  # инициализируется после старта JVM


def pystr(v):
    """Гарантированно возвращает python-строку из java.lang.String / str."""
    if v is None:
        return None
    if isinstance(v, str):
        return v
    return str(JString(v))


def start_jvm():
    global JString
    if not jpype.isJVMStarted():
        jpype.startJVM(
            jpype.getDefaultJVMPath(),
            "-Dderby.stream.error.field=java.lang.System.out",
            classpath=[DERBY_JAR],
            convertStrings=True,
        )
    JString = jpype.JClass("java.lang.String")
    from java.sql import DriverManager  # noqa: F401
    # явная регистрация драйвера (гарантия для JPype)
    jpype.JClass("org.apache.derby.jdbc.EmbeddedDriver")()
    return DriverManager.getConnection(
        "jdbc:derby:%s;create=true" % DB_DIR
    )


# ---------------------------------------------------------------- DDL / CSV
def normalize_ident(name):
    """Идентификатор как в DDL: имя таблицы без схемы + суффикс уникальности."""
    name = name.strip().strip('"').upper()
    if "." in name:
        name = name.split(".")[-1]
    return name


def parse_ddl(ddl_text):
    """Разбор aqua_ddl.sql -> список CREATE TABLE и CREATE INDEX statements.

    Комментарии внутри определений вырезаются (в т.ч. многострочные), чтобы
    Derby корректно обрабатывала текст.
    """
    stmts = []
    i, n = 0, len(ddl_text)
    while i < n:
        up = ddl_text[i:i + 12].upper()
        if up.startswith("CREATE TABLE") or up.startswith("CREATE INDEX"):
            j = ddl_text.find(";", i)
            if j == -1:
                break
            raw = ddl_text[i:j]
            # вырезание комментариев (--... и /* ... */) вне строковых литералов
            out, k, m, in_str, in_cmt_line, in_cmt_blk = [], 0, len(raw), False, False, False
            while k < m:
                ch = raw[k]
                if in_cmt_line:
                    if ch == "\n":
                        in_cmt_line = False
                        out.append(ch)
                    k += 1
                    continue
                if in_cmt_blk:
                    if ch == "*" and k + 1 < m and raw[k + 1] == "/":
                        in_cmt_blk = False
                        k += 2
                        continue
                    k += 1
                    continue
                if in_str:
                    out.append(ch)
                    if ch == "'":
                        if k + 1 < m and raw[k + 1] == "'":
                            out.append("'")
                            k += 2
                            continue
                        in_str = False
                    k += 1
                    continue
                if ch == "'":
                    in_str = True
                    out.append(ch)
                    k += 1
                    continue
                if ch == "-" and k + 1 < m and raw[k + 1] == "-":
                    in_cmt_line = True
                    k += 2
                    continue
                if ch == "/" and k + 1 < m and raw[k + 1] == "*":
                    in_cmt_blk = True
                    k += 2
                    continue
                out.append(ch)
                k += 1
            stmt = "".join(out).strip()
            if stmt:
                stmts.append(stmt)
            i = j + 1
        else:
            i += 1
    return stmts


def table_columns(conn, table):
    md = conn.getMetaData()
    rs = md.getColumns(None, "FISHSTAT", table, None)
    cols = []
    types = {}
    while rs.next():
        col = pystr(rs.getString("COLUMN_NAME")).lower()
        cols.append(col)
        types[col] = rs.getInt("DATA_TYPE")
    rs.close()
    return cols, types


def load_csv(conn, table, path, cols, types):
    """Пакетная загрузка CSV в таблицу (колонки сопоставляются регистронезависимо)."""
    JInt = jpype.JClass("java.lang.Integer")
    T = jpype.JClass("java.sql.Types")
    java_types = {"str": T.VARCHAR, "num": T.DOUBLE, "int": T.BIGINT}
    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        header = [h.strip().lower() for h in next(reader)]
        idx = [header.index(c) if c in header else -1 for c in cols]
        placeholders = ",".join(["?"] * len(cols))
        sql = "INSERT INTO FISHSTAT.%s (%s) VALUES (%s)" % (
            table, ",".join(cols), placeholders)
        st = conn.prepareStatement(sql)
        count = 0
        for row in reader:
            if not row or all(not x.strip() for x in row):
                continue
            for p, (col, ci) in enumerate(zip(cols, idx), start=1):
                val = row[ci].strip() if 0 <= ci < len(row) else ""
                t = types.get(col, 12)
                if t == java_types["num"]:
                    if val:
                        st.setDouble(p, float(val))
                    else:
                        st.setNull(p, JInt(t))
                elif t == java_types["int"]:
                    if val:
                        try:
                            st.setLong(p, int(float(val)))
                        except ValueError:
                            st.setNull(p, JInt(t))
                    else:
                        st.setNull(p, JInt(t))
                else:
                    if val:
                        st.setString(p, val)
                    else:
                        st.setNull(p, JInt(t))
            st.addBatch()
            count += 1
            if count % 1000 == 0:
                st.executeBatch()
        st.executeBatch()
        st.close()
    return count


# ---------------------------------------------------------------- SQL file
def parse_sql_file(path):
    """{name: sql} из файла с маркерами '-- @QUERY name'."""
    queries, name, buf = {}, None, []
    with open(path, encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if s.upper().startswith("-- @QUERY"):
                if name and buf:
                    queries[name] = "\n".join(buf).strip()
                parts = s.split()
                if parts[1].upper() == "@QUERY":
                    name = parts[2].strip()
                else:
                    name = parts[1].strip()
                buf = []
            elif name is not None:
                if s.startswith("--"):
                    continue
                buf.append(line.rstrip())
    if name and buf:
        queries[name] = "\n".join(buf).strip()
    return {k: v.rstrip("; ") for k, v in queries.items()}


def run_query(conn, sql):
    st = conn.createStatement()
    rs = st.executeQuery(sql)
    md = rs.getMetaData()
    ncols = md.getColumnCount()
    rows = []
    while rs.next():
        row = []
        for i in range(1, ncols + 1):
            v = rs.getObject(i)
            if v is None:
                row.append(None)
            elif isinstance(v, (float, int)):
                row.append(float(v))
            else:
                try:
                    row.append(float(v))  # java.lang.Double/Integer etc.
                except (TypeError, ValueError):
                    row.append(pystr(v))
        rows.append(row)
    rs.close()
    st.close()
    return rows


# ------------------------------------------------------------- post-process
def round2(x):
    return round(x, 2) if isinstance(x, (int, float)) else x


def clean_row(row):
    return [round2(v) if isinstance(v, float) else v for v in row]


def all_zero(row, start):
    return all((row[j] is None or abs(row[j]) < 1e-9) for j in range(start, len(row)))


def fmt_num(v):
    return 0.0 if v is None else v


# ============================================================ sheet builders
def sheet_table1(rows):
    header = ["Страна"] + [str(y) for y in YEARS]
    data = [r for r in rows if not all_zero(r, 1)]
    total = ["ВСЕГО (итог)"] + [sum(fmt_num(r[i]) for r in rows) for i in range(1, 6)]
    return header, [["ВСЕГО (итог)"] + [round2(x) for x in total[1:]]] + \
        [clean_row(r) for r in sorted(data, key=lambda r: r[0])]


def sheet_table2(rows):
    header = ["Вид"] + [str(y) for y in YEARS]
    data = [r for r in rows if not all_zero(r, 1)]
    total = ["ВСЕГО (итог)"] + [round2(sum(fmt_num(r[i]) for r in rows))
                                for i in range(1, 6)]
    return header, [total] + [clean_row(r) for r in sorted(data, key=lambda r: r[0])]


WATERS_ORDER = ["Marine areas", "Inland waters"]


def _t3_totals(qrows, vrows):
    """Собирает блоки ВСЕГО/в том числе из строк [gid,gname,wname,y1..y5]."""
    def agg(rows, pred):
        res = [0.0] * 5
        for r in rows:
            if pred(r):
                for i in range(5):
                    res[i] += fmt_num(r[3 + i])
        return [round2(x) for x in res]

    blocks = []
    specs = [
        ("ВСЕГО (сумма ID 00000002 и ID 00000003 REF_YEARBOOK_GROUP)",
         lambda r: True),
        ("в том числе:", None),
        ("     Морские районы", lambda r: r[2] == "Marine areas"),
        ("     Внутренние районы", lambda r: r[2] == "Inland waters"),
        ("РЫБА И БЕСПОЗВОНОЧНЫЕ (группа ID 00000002 REF_YEARBOOK_GROUP)",
         lambda r: r[0] == "00000002"),
        ("в том числе:", None),
        ("     Морские районы", lambda r: r[0] == "00000002" and r[2] == "Marine areas"),
        ("     Внутренние районы", lambda r: r[0] == "00000002" and r[2] == "Inland waters"),
        ("ВОДОРОСЛИ (группа ID 00000003 REF_YEARBOOK_GROUP)",
         lambda r: r[0] == "00000003"),
        ("в том числе:", None),
        ("     Морские районы", lambda r: r[0] == "00000003" and r[2] == "Marine areas"),
        ("     Внутренние районы", lambda r: r[0] == "00000003" and r[2] == "Inland waters"),
    ]
    for label, pred in specs:
        if pred is None:
            blocks.append([label, "", "", None, None, None, None, None])
        else:
            blocks.append([label, "К", "", *agg(qrows, pred)])
            blocks.append([label if pred is not None else "", "С", "",
                           *agg(vrows, pred)])
    # для строк "в том числе:" значения не нужны — уже пустые
    return blocks


def _t3_group_rows(rows_q, rows_v, gid):
    out = []
    sub = [r for r in rows_q if r[0] == gid]
    subv = [r for r in rows_v if r[0] == gid]
    gname = sub[0][1] if sub else (subv[0][1] if subv else gid)
    tot_q = [round2(sum(fmt_num(r[3 + i]) for r in sub)) for i in range(5)]
    tot_v = [round2(sum(fmt_num(r[3 + i]) for r in subv)) for i in range(5)]
    out.append(["%s (ID %s)" % (gname, gid), "К", "", *tot_q])
    out.append(["", "С", "", *tot_v])
    for w in WATERS_ORDER:
        wq = [r for r in sub if r[2] == w]
        wv = [r for r in subv if r[2] == w]
        out.append(["     %s" % w, "К", "",
                    *[round2(sum(fmt_num(r[3 + i]) for r in wq)) for i in range(5)]])
        out.append(["", "С", "",
                    *[round2(sum(fmt_num(r[3 + i]) for r in wv)) for i in range(5)]])
    return out


def sheet_table3(qrows, vrows):
    header = ["Группа / воды", "Тип", "Примечание"] + [str(y) for y in YEARS]
    rows = []
    rows += _t3_totals(qrows, vrows)
    rows += _t3_group_rows(qrows, vrows, "00000002")
    rows += _t3_group_rows(qrows, vrows, "00000003")
    return header, rows


def sheet_table4(krows, srows):
    header = ["Страна", "Тип данных"] + [str(y) for y in YEARS]
    kmap = {r[0]: r[1:] for r in krows}
    smap = {r[0]: r[1:] for r in srows}
    names = sorted(set(kmap) | set(smap))
    out = []
    total_k = [round2(sum(fmt_num(v[i]) for v in kmap.values())) for i in range(5)]
    total_s = [round2(sum(fmt_num(v[i]) for v in smap.values())) for i in range(5)]
    out.append(["ВСЕГО (итог)", "К", *total_k])
    out.append(["", "С", *total_s])
    for nm in names:
        kv = kmap.get(nm, [0] * 5)
        sv = smap.get(nm, [0] * 5)
        if all_zero(list(kv), 0) and all_zero(list(sv), 0):
            continue
        out.append([nm, "К", *[round2(fmt_num(x)) for x in kv]])
        out.append(["", "С", *[round2(fmt_num(x)) for x in sv]])
    return header, out


def sheet_table5(krows, srows):
    header = ["Группа ISSCAAP", "Номер группы", "Тип данных"] + \
             [str(y) for y in YEARS]
    order, kmap, smap = [], {}, {}
    for r in krows + srows:
        key = (r[1], r[0])
        if key not in kmap and key not in smap and key not in order:
            order.append(key)
    for r in krows:
        kmap[(r[1], r[0])] = r[2:]
    for r in srows:
        smap[(r[1], r[0])] = r[2:]
    order.sort()
    out = []
    total_k = [round2(sum(fmt_num(v[i]) for v in kmap.values())) for i in range(5)]
    total_s = [round2(sum(fmt_num(v[i]) for v in smap.values())) for i in range(5)]
    out.append(["ВСЕГО (итог) сумма по всем группам", "", "К", *total_k])
    out.append(["", "", "С", *total_s])
    for code, name in order:
        kv = kmap.get((code, name), [0] * 5)
        sv = smap.get((code, name), [0] * 5)
        out.append([name, code, "К", *[round2(fmt_num(x)) for x in kv]])
        out.append(["", "", "С", *[round2(fmt_num(x)) for x in sv]])
    return header, out


def _sheet_country_subtotals(rows, dim_cols, label_total):
    """rows: [страна, *dims, y1..y5]; добавляет итоги по странам и общий итог."""
    ny = 5
    out = []
    total = [0.0] * ny
    by_country = {}
    for r in rows:
        c = r[0]
        vals = [fmt_num(x) for x in r[len(r) - ny:]]
        by_country.setdefault(c, [0.0] * ny)
        for i in range(ny):
            by_country[c][i] += vals[i]
            total[i] += vals[i]
    out.append([label_total] + [""] * dim_cols + [round2(x) for x in total])
    for c in sorted(by_country):
        body = sorted([r for r in rows if r[0] == c], key=lambda r: str(r[2]))
        for r in body:
            out.append(clean_row(r))
        out.append([c] + [""] * dim_cols +
                   [round2(x) for x in by_country[c]])
    header_dim = None
    return out, header_dim


def sheet_table6(rows):
    header = ["Страна", "Группа ISSCAAP", "Номер группы"] + [str(y) for y in YEARS]
    body, _ = _sheet_country_subtotals(rows, 2, "ВСЕГО (итог)")
    return header, body


def sheet_table7(rows):
    header = ["Страна", "Вид"] + [str(y) for y in YEARS]
    body, _ = _sheet_country_subtotals(rows, 1, "ВСЕГО (итог)")
    return header, body


ENV_NAMES = {"IN": "IN (Freshwater)", "BW": "BW (Brackishwater)",
             "MA": "MA (Marine)"}


def sheet_table8(rows):
    header = ["Группа ISSCAAP", "Номер группы", "Вид", "Среда обитания"] + \
             [str(y) for y in YEARS]
    ny = 5
    rows = [r for r in rows if not all_zero(r, 4)]
    # сортировка: номер группы (числ.), вид, среда
    rows.sort(key=lambda r: (int(float(r[1])), str(r[2]), str(r[3])))
    grand = [0.0] * ny
    env_tot = {e: [0.0] * ny for e in ("IN", "BW", "MA")}
    for r in rows:
        e = r[3]
        for i in range(ny):
            v = fmt_num(r[4 + i])
            grand[i] += v
            if e in env_tot:
                env_tot[e][i] += v
    out = [["ВСЕГО (итог)", "", "", ""] + [round2(x) for x in grand]]
    for e in ("IN", "BW", "MA"):
        out.append(["", "", "", ENV_NAMES[e]] + [round2(x) for x in env_tot[e]])
    groups = []
    for r in rows:
        if (r[1], r[0]) not in groups:
            groups.append((r[1], r[0]))
    for code, gname in groups:
        grows = [r for r in rows if r[1] == code]
        gtot = [round2(sum(fmt_num(r[4 + i]) for r in grows)) for i in range(ny)]
        out.append([gname, code, "ИТОГО ПО ГРУППЕ", ""] + gtot)
        getot = {e: [0.0] * ny for e in ("IN", "BW", "MA")}
        for r in grows:
            if r[3] in getot:
                for i in range(ny):
                    getot[r[3]][i] += fmt_num(r[4 + i])
        for e in ("IN", "BW", "MA"):
            out.append(["", "", "", ENV_NAMES[e]] + [round2(x) for x in getot[e]])
        for r in grows:
            out.append(clean_row(r))
    return header, out


def sheet_table9(rows):
    header = ["Группа ISSCAAP", "Номер группы", "Вид"] + [str(y) for y in YEARS]
    ny = 5
    rows = [r for r in rows if not all_zero(r, 3)]
    rows.sort(key=lambda r: (int(float(r[1])), str(r[2])))
    grand = [round2(sum(fmt_num(r[3 + i]) for r in rows)) for i in range(ny)]
    out = [["ВСЕГО (итог)", "", ""] + grand]
    groups = []
    for r in rows:
        if (r[1], r[0]) not in groups:
            groups.append((r[1], r[0]))
    for code, gname in groups:
        grows = [r for r in rows if r[1] == code]
        gtot = [round2(sum(fmt_num(r[3 + i]) for r in grows)) for i in range(ny)]
        out.append([gname, code, ""] + gtot)
        for r in grows:
            out.append(clean_row(r))
    return header, out


# ------------------------------------------------------------------- excel
def write_xlsx(sheets):
    from openpyxl import Workbook
    from openpyxl.styles import Font, Alignment
    from openpyxl.utils import get_column_letter

    wb = Workbook()
    wb.remove(wb.active)
    bold = Font(bold=True)
    for title, (header, rows) in sheets.items():
        ws = wb.create_sheet(title)
        ws.append(header)
        for c in range(1, len(header) + 1):
            cell = ws.cell(row=1, column=c)
            cell.font = bold
            cell.alignment = Alignment(horizontal="center", wrap_text=True)
        for r in rows:
            ws.append(list(r))
        ws.freeze_panes = "A2"
        widths = [max(14, min(45, len(str(header[0])) + 4))]
        for c in range(1, len(header)):
            widths.append(16)
        for i, w in enumerate(widths, start=1):
            ws.column_dimensions[get_column_letter(i)].width = w
        first_data_row = 2
        for row in ws.iter_rows(min_row=first_data_row, max_row=ws.max_row,
                                min_col=2, max_col=len(header)):
            for cell in row:
                if isinstance(cell.value, (int, float)):
                    cell.number_format = "#,##0.00"
        # выделяем жирным строки итогов
        for row in ws.iter_rows(min_row=2, max_row=ws.max_row, min_col=1,
                                max_col=1):
            v = row[0].value
            if v and isinstance(v, str) and (
                    v.startswith("ВСЕГО") or v.startswith("в том числе")
                    or "ИТОГО ПО ГРУППЕ" in v):
                for cell in ws[row[0].row]:
                    cell.font = bold
    wb.save(OUT_XLSX)


# --------------------------------------------------------------------- main
def main():
    if jpype.isJVMStarted():
        pass
    # Derby сам создает каталог БД при create=true — он должен отсутствовать
    if os.path.isdir(DB_DIR):
        print("Удаление старой базы %s" % DB_DIR)
        shutil.rmtree(DB_DIR)

    print("Запуск JVM и Derby embedded...")
    conn = start_jvm()
    st = conn.createStatement()

    print("Создание схемы FISHSTAT...")
    try:
        st.execute("CREATE SCHEMA FISHSTAT")
    except Exception as e:
        if "already exists" not in str(e):
            raise

    ddl_text = open(DDL_FILE, encoding="utf-8").read()
    stmts = parse_ddl(ddl_text)
    print("Выполнение DDL (%d операторов)..." % len(stmts))
    for s in stmts:
        st.execute(s)
    st.close()

    print("Загрузка CSV...")
    for t in TABLES:
        path = os.path.join(CSV_DIR, t + ".csv")
        cols, types = table_columns(conn, t)
        n = load_csv(conn, t, path, cols, types)
        print("  %-28s %6d строк" % (t, n))

    print("Выполнение SQL-запросов из sql_queries.sql...")
    queries = parse_sql_file(SQL_FILE)
    res = {}
    for name, sql in queries.items():
        res[name] = run_query(conn, sql)
        print("  %-28s %6d строк" % (name, len(res[name])))

    # ------------------------- пост-обработка и сборка листов
    sheets = {}
    sheets["Таблица 1"] = sheet_table1(res["t1_countries_quantity"])
    sheets["Таблица 2"] = sheet_table2(res["t2_species_quantity"])
    sheets["Таблица 3"] = sheet_table3(res["t3_world_group_env_quantity"],
                                       res["t3_world_group_env_value"])
    sheets["Таблица 4"] = sheet_table4(res["t4_countries_k"],
                                       res["t4_countries_s"])
    sheets["Таблица 5"] = sheet_table5(res["t5_isscaap_k"], res["t5_isscaap_s"])
    sheets["Таблица 6"] = sheet_table6(res["t6_country_isscaap"])
    sheets["Таблица 7"] = sheet_table7(res["t7_country_species"])
    sheets["Таблица 8"] = sheet_table8(res["t8_species_environment"])
    sheets["Таблица 9"] = sheet_table9(res["t9_world_species"])

    print("Запись %s ..." % OUT_XLSX)
    write_xlsx(sheets)

    # закрытие Derby
    try:
        jpype.JClass("java.sql.DriverManager").getConnection(
            "jdbc:derby:;shutdown=true")
    except Exception as e:
        if "Derby system shutdown" not in str(e):
            print("Shutdown notice:", e)
    print("Готово: %s" % OUT_XLSX)


if __name__ == "__main__":
    main()
