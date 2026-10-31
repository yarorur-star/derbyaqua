#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_report.py - формирование Excel-отчета по базе данных ФАО (аквакультура).

Что делает:
  1. Поднимает embedded-базу Apache Derby (схема FISHSTAT) в папке derby_db/
     и загружает в неё CSV дампы из папки /CSV (DDL и импорт - sql/derby_queries.sql,
     раздел A; при отсутствии Java/Derby работает режим "только pandas" - шаг 4).
  2. Выполняет SQL-запросы раздела B (sql/derby_queries.sql) - по одному на таблицу.
  3. Собирает финальный отчет report.xlsx: каждый лист = таблица 1..9 из задания
     (названия листов - как в запросах), числовые значения округлены до 3 знаков,
     служебные сортировочные колонки скрыты.
  4. Контроль: те же таблицы считаются независимым кодом на pandas по CSV
     и сравниваются с результатом SQL (несовпадения печатаются в консоль).

Зависимости: Python 3.9+ (pandas, openpyxl); для шага SQL - Java 8+ и Apache
Derby (библиотеки derby.jar, derbytools.jar, derbyoptionaltools.jar): задайте
DERBY_HOME или CLASSPATH, либо положите jar-файлы в ./lib.

Запуск:  python build_report.py [--no-sql]   (--no-sql - только pandas-режим)
"""

import io
import os
import re
import shutil
import subprocess
import sys
import zipfile
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
SQL_FILE = BASE_DIR / "sql" / "derby_queries.sql"
CSV_DIR = BASE_DIR / "CSV"
DB_DIR = BASE_DIR / "derby_db"
EXPORT_DIR = BASE_DIR / "db_export"
REPORT_FILE = BASE_DIR / "report.xlsx"

YEARS = [2020, 2021, 2022, 2023, 2024]
YCOLS = [f"VALUE_Y{y}" for y in YEARS]
GROUP_IDS = ("00000002", "00000003")   # используемые группы REF_YEARBOOK_GROUP

TOTAL_LABEL = "ВСЕГО"


def log(msg):
    print(msg, flush=True)


# ---------------------------------------------------------------------------
# Чтение CSV (BOM-safe, пустые поля -> NaN)
# ---------------------------------------------------------------------------
def read_csv(name):
    import pandas as pd
    return pd.read_csv(CSV_DIR / name, encoding="utf-8-sig", dtype=str)


def to_num(df, cols):
    import pandas as pd
    for c in cols:
        df[c] = pd.to_numeric(df[c], errors="coerce").fillna(0.0)
    return df


# ---------------------------------------------------------------------------
# Java / Derby
# ---------------------------------------------------------------------------
JAR_URLS = {
    "derby.jar": "https://repo1.maven.org/maven2/org/apache/derby/derby/10.14.2.0/derby-10.14.2.0.jar",
    "derbytools.jar": "https://repo1.maven.org/maven2/org/apache/derby/derbytools/10.14.2.0/derbytools-10.14.2.0.jar",
    "derbynet.jar": "https://repo1.maven.org/maven2/org/apache/derby/derbynet/10.14.2.0/derbynet-10.14.2.0.jar",
    "derbyoptionaltools.jar": "https://repo1.maven.org/maven2/org/apache/derby/derbyoptionaltools/10.14.2.0/derbyoptionaltools-10.14.2.0.jar",
}


def find_jars():
    lib_dir = BASE_DIR / "lib"
    lib_dir.mkdir(exist_ok=True)
    candidates = []
    derby_home = os.environ.get("DERBY_HOME")
    if derby_home:
        candidates.append(Path(derby_home) / "lib")
    cp = os.environ.get("CLASSPATH", "")
    for part in cp.split(os.pathsep):
        if part and "*" not in part:
            p = Path(part)
            if p.is_file() and p.suffix == ".jar":
                candidates.append(p.parent)
    candidates += [lib_dir, Path("/tmp")]
    jars = {}
    for need in JAR_URLS:
        for d in candidates:
            f = d / need
            if f.is_file():
                jars[need] = f
                break
    if len(jars) < 3:  # derby.jar + derbytools.jar обязательны, optionaltools для импорта
        return None
    # докачать недостающий optionaltools (для SYSCS_IMPORT_TABLE)
    if "derbyoptionaltools.jar" not in jars:
        try:
            import urllib.request
            with urllib.request.urlopen(JAR_URLS["derbyoptionaltools.jar"], timeout=30) as r:
                (lib_dir / "derbyoptionaltools.jar").write_bytes(r.read())
            jars["derbyoptionaltools.jar"] = lib_dir / "derbyoptionaltools.jar"
        except Exception:
            pass
    return list(jars.values())


def run_java(classpath, main_class, args, stdin_text=None, out_file=None):
    cmd = ["java", "-cp", classpath, main_class] + args
    proc = subprocess.run(cmd, input=stdin_text, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"java failed: {' '.join(cmd)}\n{proc.stdout}\n{proc.stderr}")
    if out_file is not None:
        Path(out_file).write_text(proc.stdout, encoding="utf-8")
    return proc.stdout


# ---------------------------------------------------------------------------
# Разбор sql-файла
# ---------------------------------------------------------------------------
QUERY_MARK_RE = re.compile(r"^-- @query (\d+)\|(.*)$", re.M)


def split_sql_statements(text):
    """Разбивает текст на операторы по ';' вне строк/комментариев."""
    stmts, buf, i, n = [], [], 0, len(text)
    while i < n:
        ch = text[i]
        if ch == "-" and text[i:i + 2] == "--":
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if ch == "'":
            j = i + 1
            while j < n:
                if text[j] == "'":
                    if j + 1 < n and text[j + 1] == "'":
                        j += 2
                        continue
                    break
                j += 1
            buf.append(text[i:j + 1])
            i = j + 1
            continue
        if ch == ";":
            s = "".join(buf).strip()
            if s:
                stmts.append(s)
            buf = []
            i += 1
            continue
        buf.append(ch)
        i += 1
    s = "".join(buf).strip()
    if s:
        stmts.append(s)
    return stmts


def load_sql_sections(csv_dir_abs):
    text = SQL_FILE.read_text(encoding="utf-8")
    head = text.split("-- @query 1|")[0]
    setup = [s for s in split_sql_statements(head)
             if not s.lower().startswith("create index")]  # индексы внутри CREATE TABLE не дублируем
    setup = [s.replace("{CSV}", str(csv_dir_abs)) for s in setup]
    queries = []
    marks = QUERY_MARK_RE.findall(text)
    chunks = re.split(r"^-- @query \d+\|.*$", text, flags=re.M)[1:]
    assert len(marks) == len(chunks) == 9, f"ожидалось 9 запросов, найдено {len(marks)}"
    for (num, meta), chunk in zip(marks, chunks):
        stmts = split_sql_statements(chunk)
        assert len(stmts) == 1, f"запрос {num} должен быть одним оператором"
        title, subtitle, *cols = meta.split("|")
        queries.append({"num": int(num), "title": title.strip(),
                        "subtitle": subtitle.strip(),
                        "columns": [c.strip() for c in cols],
                        "sql": stmts[0]})
    return setup, sorted(queries, key=lambda q: q["num"])


# ---------------------------------------------------------------------------
# SQL-режим: ij (создание БД + импорт) -> NetworkServerControl -> JDBC export
# ---------------------------------------------------------------------------
def build_database(jars, csv_dir_abs):
    cp = ";".join(str(j) for j in jars) if os.name == "nt" else ":".join(str(j) for j in jars)
    if DB_DIR.exists():
        shutil.rmtree(DB_DIR)
    if EXPORT_DIR.exists():
        shutil.rmtree(EXPORT_DIR)
    db_path = (DB_DIR / "aquadb").as_posix()
    setup, queries = load_sql_sections(csv_dir_abs)
    ij_script = f"connect 'jdbc:derby:{db_path};create=true';\n"
    ij_script += "\n".join(s + ";" for s in setup) + "\n"
    ij_script += "connect 'jdbc:derby:';\nexit;\n"
    log("[SQL] создание схемы и импорт CSV через ij ...")
    out = run_java(cp, "org.apache.derby.tools.ij", [], stdin_text=ij_script)
    if "ERROR" in out.upper():
        raise RuntimeError("ij errors:\n" + out[-4000:])

    # экспорт результата каждого запроса через sysinfo-совместимый DriverManager
    driver = r'''
import java.io.BufferedWriter;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.sql.*;
import java.util.*;

public class SqlExport {
    public static void main(String[] a) throws Exception {
        String url = a[0];
        String sqlFile = a[1];
        String outDir = a[2];
        String delim = new String(Base64.getDecoder().decode(a[3]), StandardCharsets.UTF_8);
        Properties props = new Properties();
        if (a.length > 5) { props.setProperty("user", a[4]); props.setProperty("password", a[5]); }
        List<String> raw = Files.readAllLines(Paths.get(sqlFile), StandardCharsets.UTF_8);
        String content = String.join("\n", raw);
        String[] parts = content.split("@@NEXT@@");
        DriverManager.registerDriver(new org.apache.derby.jdbc.EmbeddedDriver());
        Connection conn = DriverManager.getConnection(url, props);
        Statement st = conn.createStatement();
        for (int i = 0; i < parts.length; i++) {
            String sql = parts[i].trim();
            if (sql.isEmpty()) continue;
            ResultSet rs = st.executeQuery(sql);
            ResultSetMetaData md = rs.getMetaData();
            int nc = md.getColumnCount();
            BufferedWriter w = new BufferedWriter(new OutputStreamWriter(
                Files.newOutputStream(Paths.get(outDir, "q" + (i + 1) + ".txt")), StandardCharsets.UTF_8));
            StringBuilder hdr = new StringBuilder();
            for (int c = 1; c <= nc; c++) hdr.append(c > 1 ? delim : "").append(md.getColumnName(c));
            w.write(hdr.toString()); w.newLine();
            while (rs.next()) {
                StringBuilder line = new StringBuilder();
                for (int c = 1; c <= nc; c++) {
                    if (c > 1) line.append(delim);
                    Object v = rs.getObject(c);
                    line.append(v == null ? "" : String.valueOf(v));
                }
                w.write(line.toString()); w.newLine();
            }
            w.close();
            rs.close();
        }
        st.close();
        conn.close();
        try { DriverManager.getConnection("jdbc:derby:;shutdown=true"); } catch (SQLException ignore) {}
    }
}
'''
    tmp = BASE_DIR / ".sqltmp"
    tmp.mkdir(exist_ok=True)
    src = tmp / "SqlExport.java"
    src.write_text(driver, encoding="utf-8")
    log("[SQL] компиляция SqlExport ...")
    run_java(cp, "javac", ["-cp", cp, "-d", str(tmp), str(src)])
    # файлы запросов (без комментариев-заголовков)
    files_dir = tmp / "queries"
    files_dir.mkdir(exist_ok=True)
    for q in queries:
        body = re.sub(r"^--.*$", "", q["sql"], flags=re.M).strip().rstrip(";")
        (files_dir / f"q{q['num']}.sql").write_text(body, encoding="utf-8")
    joined = "\n@@NEXT@@\n".join((files_dir / f"q{n}.sql").read_text(encoding="utf-8")
                                  for n in range(1, 10))
    all_file = tmp / "all_queries.sql"
    all_file.write_text(joined, encoding="utf-8")
    EXPORT_DIR.mkdir(exist_ok=True)
    log("[SQL] выполнение 9 запросов и экспорт ...")
    cp2 = cp + os.pathsep + str(tmp)
    out = run_java(cp2, "SqlExport",
                   [f"jdbc:derby:{db_path}", str(all_file), str(EXPORT_DIR),
                    "wSQpdRWq7+"])
    return queries


def parse_export(qnum, delim="\x1f"):
    import pandas as pd
    f = EXPORT_DIR / f"q{qnum}.txt"
    txt = f.read_text(encoding="utf-8")
    first = txt.split("\n", 1)[0]
    if delim not in first:
        raise RuntimeError(f"экспорт q{qnum} повреждён (нет разделителя в заголовке)")
    return pd.read_csv(io.StringIO(txt), sep=delim, engine="python", dtype=str,
                       keep_default_na=False)


# ---------------------------------------------------------------------------
# Pandas-эталон (независимая реализация тех же 9 таблиц)
# ---------------------------------------------------------------------------
def ref_frames():
    import numpy as np
    import pandas as pd

    sp_all = read_csv("REF_SPECIES.csv")
    sp_all["NAME_EN"] = sp_all["NAME_EN"].fillna("")
    rel_yb = read_csv("REL_YEARBOOK_GROUP_SPECIES.csv")
    used_ids = set(rel_yb.loc[rel_yb.PARENT_ID.isin(GROUP_IDS), "CHILD_ID"])
    sp_used = sp_all[sp_all.ID.isin(used_ids)]
    a3_to_name = dict(zip(sp_used.ALPHA_3_CODE, sp_used.NAME_EN))
    id_to_a3 = dict(zip(sp_all.ID, sp_all.ALPHA_3_CODE))

    q = to_num(read_csv("TSD_AQUACULTURE_QUANTITY.csv"), YCOLS)
    q = q[q.MEASURE == "Q_tlw"]
    q = q[q.SPECIES.isin(a3_to_name)]
    v = to_num(read_csv("TSD_AQUACULTURE_VALUE.csv"), YCOLS)
    v = v[v.MEASURE == "V_USD_1000"]
    v = v[v.SPECIES.isin(a3_to_name)]

    country = read_csv("REF_COUNTRY.csv")
    un_to_name = dict(zip(country.UN_CODE, country.NAME_EN.fillna("")))
    species_tab = read_csv("REF_SPECIES.csv")
    iss_rel = read_csv("REL_ISSCAAP_GROUP_SPECIES.csv")
    grp_of = dict(zip(iss_rel.CHILD_ID, iss_rel.PARENT_ID))
    ig = read_csv("REF_ISSCAAP_GROUP.csv")
    ig["CODE"] = pd.to_numeric(ig.CODE, errors="coerce").fillna(0).astype(int)
    gid_to_name = dict(zip(ig.ID, ig.NAME_EN.fillna("")))
    gid_to_code = dict(zip(ig.ID, ig.CODE))
    env = read_csv("REF_ENVIRONMENT.csv")
    im = read_csv("REF_INLAND_MARINE.csv")
    im_name = dict(zip(im.ID, im.NAME_EN))
    rel_im = read_csv("REL_INLAND_MARINE_AREA.csv")
    area_id_to_waters = dict(zip(rel_im.CHILD_ID, rel_im.PARENT_ID))
    ref_area = read_csv("REF_AREA.csv")
    area_code_to_id = dict(zip(ref_area.CODE, ref_area.ID))
    yb = read_csv("REF_YEARBOOK_GROUP.csv")
    yb_name = dict(zip(yb.ID, yb.NAME_EN))

    def year_cols(df):
        return {str(y): round(float(df[f"VALUE_Y{y}"].sum()), 3) for y in YEARS}

    def nonzero_rows(g, label_key):
        rows = []
        for k, sub in g:
            yc = year_cols(sub)
            if any(abs(x) > 1e-9 for x in yc.values()):
                rows.append({"label": k, **yc})
        return rows

    frames = {}
    ycols_str = [str(y) for y in YEARS]

    def rows_t1_t2(dfin, col, mapping):
        tot = year_cols(dfin)
        rows = [[TOTAL_LABEL] + [tot[y] for y in ycols_str] + [1]]
        subs = []
        for k, sub in dfin.groupby(dfin[col].map(mapping)):
            yc = year_cols(sub)
            if any(abs(x) > 1e-9 for x in yc.values()):
                subs.append([k] + [yc[y] for y in ycols_str] + [0])
        subs.sort(key=lambda r: (-r[5], r[0]))
        return rows + subs

    # T1: страны, тонны
    frames[1] = (["Страна"] + ycols_str + ["TOTAL_ROW"],
                 rows_t1_t2(q, "COUNTRY", un_to_name))

    # T2: виды, тонны
    frames[2] = (["Species"] + ycols_str + ["TOTAL_ROW"],
                 rows_t1_t2(q, "SPECIES", a3_to_name))

    # T3: воды К/С по группам ежегодника
    qw = q.assign(waters=q.AREA.map(area_code_to_id).map(area_id_to_waters))
    vw = v.assign(waters=v.AREA.map(area_code_to_id).map(area_id_to_waters))
    sid_to_ybgid = {}
    for _, rr in rel_yb.iterrows():
        if rr.PARENT_ID in GROUP_IDS:
            sid_to_ybgid[rr.CHILD_ID] = rr.PARENT_ID
    a3_to_ybgid = {id_to_a3[s]: g for s, g in sid_to_ybgid.items()}
    wat_rank = {"Marine areas": 0, "Inland waters": 1}

    rows = []
    blocks = [(TOTAL_LABEL, None)] + [(yb_name[g], g) for g in GROUP_IDS]
    for block_label, gid in blocks:
        srt_grp = 0 if gid is None else (1 if gid == "00000002" else 2)
        codes_g = None if gid is None else {a3 for a3, g in a3_to_ybgid.items() if g == gid}
        for typ, dfin in (("К", qw), ("С", vw)):
            sub_all = dfin if gid is None else dfin[dfin.SPECIES.isin(codes_g)]
            for wid, sub in sub_all.groupby("waters"):
                yc = year_cols(sub)
                rows.append([block_label, typ, im_name[wid]] + [yc[str(y)] for y in YEARS] +
                           [1 if gid is None else 0, srt_grp, wat_rank.get(im_name[wid], 9)])
    rows.sort(key=lambda r: (r[7], r[1], -r[6], r[8]))
    frames[3] = (["Group", "Type", "Waters"] + [str(y) for y in YEARS] +
                 ["TOTAL_ROW", "SRT_GRP", "SRT_WAT"], rows)

    # T4: страны К/С
    rows = []
    names_kept = set()
    for dfin in (q, v):
        for cname, sub in dfin.groupby(dfin.COUNTRY.map(un_to_name)):
            if any(abs(x) > 1e-9 for x in year_cols(sub).values()):
                names_kept.add(cname)
    for typ, dfin in (("К", q), ("С", v)):
        for cname, sub in dfin.groupby(dfin.COUNTRY.map(un_to_name)):
            if cname in names_kept:
                yc = year_cols(sub)
                rows.append([cname, typ] + [yc[str(y)] for y in YEARS] + [0])

    for typ, dfin in (("К", q), ("С", v)):
        yc = year_cols(dfin)
        rows.append([TOTAL_LABEL, typ] + [yc[str(y)] for y in YEARS] + [1])
    rows.sort(key=lambda r: (-r[6], r[0], r[1]))
    frames[4] = (["Country", "Type"] + [str(y) for y in YEARS] + ["TOTAL_ROW"], rows)

    # T5: группы ISSCAAP К/С
    q5 = q.assign(gid=q.SPECIES.map(lambda a3: grp_of.get(id_to_a3.get(a3))))
    v5 = v.assign(gid=v.SPECIES.map(lambda a3: grp_of.get(id_to_a3.get(a3))))
    kept = set()
    for dfin in (q5, v5):
        for gid, sub in dfin.dropna(subset=["gid"]).groupby("gid"):
            if any(abs(x) > 1e-9 for x in year_cols(sub).values()):
                kept.add(gid)
    rows = []
    for typ, dfin in (("К", q5), ("С", v5)):
        for gid, sub in dfin.dropna(subset=["gid"]).groupby("gid"):
            if gid in kept:
                yc = year_cols(sub)
                rows.append([gid_to_name[gid], gid_to_code[gid], typ] + [yc[str(y)] for y in YEARS] + [0])
    for typ, dfin in (("К", q), ("С", v)):
        yc = year_cols(dfin)
        rows.append([TOTAL_LABEL, 0, typ] + [yc[str(y)] for y in YEARS] + [1])
    rows.sort(key=lambda r: (-r[10], r[1], r[2]))
    frames[5] = (["ISSCAAP_Group", "Code", "Type"] + [str(y) for y in YEARS] + ["TOTAL_ROW"], rows)

    # T6: страны x группы ISSCAAP, тонны
    rows = []
    yc = year_cols(q)
    rows.append([TOTAL_LABEL, TOTAL_LABEL, 0] + [yc[str(y)] for y in YEARS] + ["", 0, 0])
    kept_countries = set()
    for cc, sub in q.groupby(q.COUNTRY.map(un_to_name)):
        if any(abs(x) > 1e-9 for x in year_cols(sub).values()):
            kept_countries.add(cc)
    for cc in kept_countries:
        sub = q[q.COUNTRY.map(un_to_name) == cc]
        yc = year_cols(sub)
        rows.append([cc, "ИТОГО", 0] + [yc[str(y)] for y in YEARS] + [cc, 0, 0])
    pairs = q5.dropna(subset=["gid"]).assign(cc=lambda d: d.COUNTRY.map(un_to_name))
    for (cc, gid), sub in pairs[pairs.cc.isin(kept_countries)].groupby(["cc", "gid"]):
        yc = year_cols(sub)
        if any(abs(x) > 1e-9 for x in yc.values()):
            rows.append([cc, gid_to_name[gid], gid_to_code[gid]] + [yc[str(y)] for y in YEARS] + [cc, 1, gid_to_code[gid]])
    rows.sort(key=lambda r: (r[9], r[10], r[12], r[11]))
    frames[6] = (["Country", "ISSCAAP_Group", "Code"] + [str(y) for y in YEARS] +
                 ["SORT_COUNTRY", "SORT_LEVEL", "GRP_CODE"], rows)

    # T7: страны x виды, тонны
    rows = []
    yc = year_cols(q)
    rows.append([TOTAL_LABEL, TOTAL_LABEL] + [yc[str(y)] for y in YEARS] + ["", 0, ""])
    for cc in kept_countries:
        sub = q[q.COUNTRY.map(un_to_name) == cc]
        yc = year_cols(sub)
        rows.append([cc, "ИТОГО"] + [yc[str(y)] for y in YEARS] + [cc, 0, ""])
    pairs = q.assign(cc=q.COUNTRY.map(un_to_name))
    for (cc, a3), sub in pairs[pairs.cc.isin(kept_countries)].groupby(["cc", "SPECIES"]):
        yc = year_cols(sub)
        if any(abs(x) > 1e-9 for x in yc.values()):
            nm = a3_to_name[a3]
            rows.append([cc, nm] + [yc[str(y)] for y in YEARS] + [cc, 1, nm])
    rows.sort(key=lambda r: (r[8], r[9], r[10]))
    frames[7] = (["Country", "Species"] + [str(y) for y in YEARS] +
                 ["SORT_COUNTRY", "SORT_LEVEL", "SORT_SPECIES"], rows)

    # T8: виды x среда обитания, тонны
    qe = q5.assign(env=q.ENVIRONMENT)
    rows = []
    yc = year_cols(q)
    rows.append([TOTAL_LABEL, 0, TOTAL_LABEL, ""] + [yc[str(y)] for y in YEARS] + [1, 0, 0, 0])
    env_sort = {"IN": 0, "BW": 1, "MA": 2}
    for e, sub in q.groupby("ENVIRONMENT"):
        yc = year_cols(sub)
        rows.append(["Все группы", 0, "", e] + [yc[str(y)] for y in YEARS] + [1, 1, 0, env_sort[e]])
    kept_groups = set()
    for gid, sub in q5.dropna(subset=["gid"]).groupby("gid"):
        if any(abs(x) > 1e-9 for x in year_cols(sub).values()):
            kept_groups.add(gid)
    for gid in sorted(kept_groups, key=lambda g: gid_to_code[g]):
        subg = q5[q5.gid == gid]
        for e, sub in subg.groupby("ENVIRONMENT"):
            yc = year_cols(sub)
            if any(abs(x) > 1e-9 for x in yc.values()):
                rows.append([gid_to_name[gid], gid_to_code[gid], "ИТОГО группы", e] +
                            [yc[str(y)] for y in YEARS] + [0, 2, gid_to_code[gid], env_sort[e]])
        for (a3, e), sub in subg.groupby(["SPECIES", "ENVIRONMENT"]):
            yc = year_cols(sub)
            if any(abs(x) > 1e-9 for x in yc.values()):
                rows.append([gid_to_name[gid], gid_to_code[gid], a3_to_name[a3], e] +
                            [yc[str(y)] for y in YEARS] + [0, 3, gid_to_code[gid], 0])
    rows.sort(key=lambda r: (r[12], r[11], r[13], r[14], r[2], r[3]))
    frames[8] = (["ISSCAAP_Group", "Code", "Species", "Env"] + [str(y) for y in YEARS] +
                 ["TOTAL_ROW", "SRT_TYPE", "SRT_GRP", "SRT_ENV"], rows)

    # T9: видовой состав мирового производства
    rows = []
    yc = year_cols(q)
    rows.append([TOTAL_LABEL, 0, TOTAL_LABEL] + [yc[str(y)] for y in YEARS] + [0, 0, ""])
    for gid in sorted(kept_groups, key=lambda g: gid_to_code[g]):
        subg = q5[q5.gid == gid]
        yc = year_cols(subg)
        rows.append([gid_to_name[gid], gid_to_code[gid], "ИТОГО группы"] +
                    [yc[str(y)] for y in YEARS] + [1, gid_to_code[gid], ""])
        for a3, sub in subg.groupby("SPECIES"):
            yc = year_cols(sub)
            if any(abs(x) > 1e-9 for x in yc.values()):
                rows.append([gid_to_name[gid], gid_to_code[gid], a3_to_name[a3]] +
                            [yc[str(y)] for y in YEARS] + [2, gid_to_code[gid], a3_to_name[a3]])
    rows.sort(key=lambda r: (r[9], r[10], r[11]))
    frames[9] = (["ISSCAAP_Group", "Code", "Species"] + [str(y) for y in YEARS] +
                 ["SRT_TYPE", "SRT_GRP", "SRT_SPECIES"], rows)

    return frames


# ---------------------------------------------------------------------------
# Сравнение SQL-результата с эталоном
# ---------------------------------------------------------------------------
def normalize_val(x):
    if x is None:
        return ""
    s = str(x).strip()
    if s == "":
        return ""
    try:
        d = Decimal(s).quantize(Decimal("0.001"), rounding=ROUND_HALF_UP)
        return format(d.normalize(), "f")
    except Exception:
        return s


def compare_frames(ref_cols, ref_rows, sql_df, sql_cols):
    import numpy as np
    problems = []
    if [c.upper() for c in sql_cols] != [c.upper() for c in ref_cols]:
        problems.append(f"разные заголовки: sql={sql_cols} ref={ref_cols}")
        return problems
    if len(sql_df) != len(ref_rows):
        problems.append(f"число строк: sql={len(sql_df)} ref={len(ref_rows)}")
    for i in range(min(len(sql_df), len(ref_rows))):
        sql_row = [normalize_val(sql_df.iloc[i, j]) for j in range(len(sql_cols))]
        ref_row = [normalize_val(x) for x in ref_rows[i]]
        if sql_row != ref_row:
            problems.append(f"строка {i}: sql={sql_row} ref={ref_row}")
            if len(problems) > 5:
                break
    return problems


# ---------------------------------------------------------------------------
# Округление и запись Excel
# ---------------------------------------------------------------------------
def round_numbers_inplace(df, numeric_headers):
    for col in df.columns:
        if col in numeric_headers:
            vals = []
            for x in df[col].tolist():
                s = str(x).strip()
                if s == "":
                    vals.append(0.0)
                    continue
                try:
                    vals.append(float(Decimal(s).quantize(Decimal("0.001"), rounding=ROUND_HALF_UP)))
                except Exception:
                    vals.append(x)
            df[col] = vals
    return df


def write_excel(tables, path):
    from openpyxl import Workbook
    from openpyxl.styles import Font, PatternFill, Alignment
    from openpyxl.utils import get_column_letter

    wb = Workbook()
    ws = wb.active
    ws.title = "Описание"
    ws.append(["Отчет по мировому аквакультуре (база данных ФАО, схема FISHSTAT)"])
    ws.append([])
    ws.append(["Источник данных: CSV дампы /CSV (TSD_AQUACULTURE_QUANTITY - тонны Q_tlw,"])
    ws.append(["             TSD_AQUACULTURE_VALUE - тыс.долларов V_USD_1000)."])
    ws.append(["Годы: последние 5 лет (2020-2024). Пустые VALUE_Yxxxx приняты за 0,"])
    ws.append(["поля SYMBOL_Yxxxx проигнорированы. Имена стран/видов/групп взяты из базы as is."])
    ws.append(["Использованы виды групп REF_YEARBOOK_GROUP 00000002 и 00000003;"])
    ws.append(["группа 00000004 (Other aquatic animals & products) исключена."])
    ws.append(["Числа округлены до 3 знаков после запятой (десятичные дроби)."])
    ws.append([])
    ws.append(["Листы:"])
    for t in tables:
        hidden = [c for c in t["columns"] if c.startswith(("TOTAL_ROW", "SRT_", "SORT_", "GRP_CODE"))]
        ws.append([f"{t['sheet']} - {t['subtitle']}" +
                   (f" (служебные колонки {', '.join(hidden)} скрыты)" if hidden else "")])

    header_fill = PatternFill("solid", fgColor="DDEBF7")
    bold = Font(bold=True)
    for t in tables:
        ws = wb.create_sheet(title=t["sheet"][:31])
        ws.append(t["columns"])
        for c in ws[1]:
            c.font = bold
            c.fill = header_fill
            c.alignment = Alignment(horizontal="center")
        for row in t["rows"]:
            ws.append(row)
        ws.freeze_panes = "A2"
        numcols = {i + 1 for i, c in enumerate(t["columns"]) if c.isdigit()}
        for j in range(1, len(t["columns"]) + 1):
            letter = get_column_letter(j)
            if j in numcols:
                width = 16
            else:
                maxlen = max([len(str(t["columns"][j - 1]))] +
                             [len(str(r[j - 1])) for r in t["rows"][:200]] or [10])
                width = min(max(12, maxlen + 2), 48)
            ws.column_dimensions[letter].width = width
            if j in numcols:
                for i in range(2, len(t["rows"]) + 2):
                    ws.cell(row=i, column=j).number_format = "#,##0.000;-#,##0.000"
        for i, c in enumerate(t["columns"], start=1):
            if c.startswith(("TOTAL_ROW", "SRT_", "SORT_", "GRP_CODE")):
                ws.column_dimensions[get_column_letter(i)].hidden = True
    wb.save(path)


# ---------------------------------------------------------------------------
def main():
    no_sql = "--no-sql" in sys.argv
    setup, queries = load_sql_sections(CSV_DIR.resolve())
    ref = ref_frames()
    log(f"[pandas] эталонные таблицы построены: " +
        ", ".join(f"T{k}({len(v[1])} строк)" for k, v in ref.items()))

    tables = []
    if not no_sql:
        jars = find_jars()
        if jars is None:
            log("[SQL] Java/Apache Derby не найдены (задайте DERBY_HOME или CLASSPATH, "
                "или положите derby.jar/derbytools.jar/derbyoptionaltools.jar в ./lib). "
                "Отчет строится по pandas-этalonу.")
        else:
            build_database(jars, CSV_DIR.resolve())
            for q in queries:
                df = parse_export(q["num"])
                cols = list(df.columns)
                numeric = [c for c in cols if c.isdigit()]
                df = round_numbers_inplace(df, numeric)
                problems = compare_frames(q["columns"], ref[q["num"]][1], df, cols)
                status = "OK" if not problems else f"РАСХОЖДЕНИЯ ({len(problems)})"
                log(f"[SQL] Таблица {q['num']}: {len(df)} строк - сверка с эталоном: {status}")
                for p in problems[:6]:
                    log("      " + p)
                tables.append({"sheet": q["title"], "subtitle": q["subtitle"],
                               "columns": cols, "rows": df.values.tolist()})
    if not tables:
        for q in queries:
            cols, rows = ref[q["num"]]
            rows = [[round_num(x) for x in r] for r in rows]
            tables.append({"sheet": q["title"], "subtitle": q["subtitle"],
                           "columns": cols, "rows": rows})
    write_excel(tables, REPORT_FILE)
    log(f"[done] отчет сохранен: {REPORT_FILE}")


def round_num(x):
    if isinstance(x, float):
        return float(Decimal(repr(x)).quantize(Decimal("0.001"), rounding=ROUND_HALF_UP))
    return x


if __name__ == "__main__":
    main()
