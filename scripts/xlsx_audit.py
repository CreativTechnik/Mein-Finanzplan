#!/usr/bin/env python3
import json
import re
import sys
import zipfile
from collections import Counter
from xml.etree import ElementTree as ET

NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}


def column_number(cell_ref: str) -> int:
    letters = re.match(r"[A-Z]+", cell_ref).group(0)
    number = 0
    for letter in letters:
        number = number * 26 + ord(letter) - 64
    return number


def read_workbook(path: str):
    with zipfile.ZipFile(path) as archive:
        strings_root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
        strings = []
        for item in strings_root.findall("m:si", NS):
            strings.append("".join(node.text or "" for node in item.iterfind(".//m:t", NS)))

        sheet_root = ET.fromstring(archive.read("xl/worksheets/sheet1.xml"))
        cells = {}
        formula_cells = {}
        type_counts = Counter()
        for cell in sheet_root.iterfind(".//m:c", NS):
            ref = cell.attrib["r"]
            raw = cell.findtext("m:v", default="", namespaces=NS)
            kind = cell.attrib.get("t")
            if kind == "s" and raw:
                value = strings[int(raw)]
            elif raw:
                try:
                    value = float(raw)
                    if value.is_integer():
                        value = int(value)
                except ValueError:
                    value = raw
            else:
                value = None
            cells[ref] = value
            type_counts[kind or "number/blank"] += 1
            formula = cell.find("m:f", NS)
            if formula is not None:
                formula_cells[ref] = {
                    "formula": formula.text,
                    "type": formula.attrib.get("t"),
                    "shared_index": formula.attrib.get("si"),
                    "cached": value,
                }

        merges = [item.attrib["ref"] for item in sheet_root.findall(".//m:mergeCell", NS)]
        hidden_columns = []
        for column in sheet_root.findall(".//m:cols/m:col", NS):
            if column.attrib.get("hidden") == "1":
                hidden_columns.append([int(column.attrib["min"]), int(column.attrib["max"])])

        chart = ET.fromstring(archive.read("xl/charts/chart1.xml"))
        chart_refs = sorted({node.text for node in chart.iter() if node.tag.endswith("}f") and node.text})

    return cells, formula_cells, merges, hidden_columns, chart_refs, type_counts


def cell(cells, column, row):
    return cells.get(f"{column}{row}")


def main():
    source = sys.argv[1]
    cells, formulas, merges, hidden_columns, chart_refs, type_counts = read_workbook(source)

    years = [
        (2026, "C", ["D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O"], "P"),
        (2027, "S", ["T", "U", "V", "W", "X", "Y", "Z", "AA", "AB", "AC", "AD", "AE"], "AF"),
        (2028, "AI", ["AJ", "AK", "AL", "AM", "AN", "AO", "AP", "AQ", "AR", "AS", "AT", "AU"], "AV"),
        (2029, "AY", ["AZ", "BA", "BB", "BC", "BD", "BE", "BF", "BG", "BH", "BI", "BJ", "BK"], "BL"),
    ]
    relevant_rows = list(range(7, 11)) + list(range(14, 40)) + list(range(42, 59)) + list(range(61, 64)) + list(range(68, 71))
    year_data = {}
    anomalies = []
    for year, label_col, month_cols, total_col in years:
        rows = []
        for row in relevant_rows:
            label = cell(cells, label_col, row)
            values = [cell(cells, column, row) for column in month_cols]
            total = cell(cells, total_col, row)
            if label is not None or any(value is not None for value in values) or total is not None:
                rows.append({"row": row, "label": label, "months": values, "total": total})
                numeric_sum = sum(value for value in values if isinstance(value, (int, float)))
                non_numeric = [value for value in values if value is not None and not isinstance(value, (int, float))]
                if isinstance(total, (int, float)) and abs(numeric_sum - total) > 0.01:
                    anomalies.append({
                        "year": year,
                        "row": row,
                        "label": label,
                        "monthly_numeric_sum": round(numeric_sum, 2),
                        "reported_total": round(total, 2),
                        "non_numeric_months": non_numeric,
                        "total_formula": formulas.get(f"{total_col}{row}"),
                    })
        year_data[str(year)] = rows

    output = {
        "dimensions": "B1:BL70",
        "sheet_count": 1,
        "sheet_name": "Tabelle1",
        "table_count": 1,
        "formula_count": len(formulas),
        "merge_ranges": merges,
        "hidden_column_ranges": hidden_columns,
        "chart_formula_refs": chart_refs,
        "cell_type_counts": type_counts,
        "anomalous_row_totals": anomalies,
        "years": year_data,
    }
    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
