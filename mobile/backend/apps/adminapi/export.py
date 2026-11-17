"""Downloads from the admin app: real Excel files (?format=xlsx), or CSV for older app versions.

In Excel files dates are real date cells in a wide enough column (CSV dates showed as ##### in
Excel when the column was too narrow), headings are in the app language, Arabic sheets read
right-to-left, and amounts have thousands separators.
"""

import csv
import io
from datetime import date, datetime
from decimal import Decimal

from django.http import HttpResponse
from django.utils import timezone

XLSX_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

# Column kinds: how a value is written and how wide the column is
TEXT, DATETIME, DATE, SYP, USD, RATE, INT = "text", "datetime", "date", "syp", "usd", "rate", "int"
_FORMATS = {DATETIME: "yyyy-mm-dd hh:mm", DATE: "yyyy-mm-dd", SYP: "#,##0", USD: "#,##0.00", RATE: "0.00", INT: "0"}
_MIN_WIDTH = {DATETIME: 18, DATE: 12, SYP: 14, USD: 12, RATE: 10, INT: 8}

LABELS = {
    "status": {
        "pending": ("قيد المراجعة", "Pending"), "confirmed": ("مؤكد", "Confirmed"), "shipped": ("قيد التوصيل", "Shipped"),
        "delivered": ("تم التسليم", "Delivered"), "cancelled": ("ملغى", "Cancelled"),
    },
    "delivery": {"delivery": ("توصيل", "Delivery"), "pickup": ("استلام من المحل", "Pickup")},
    "kind": {"order": ("طلب مُسلَّم", "Delivered order"), "payment": ("دفعة", "Payment"), "adjustment": ("تصحيح", "Adjustment")},
}


def wants_file(request):
    return request.query_params.get("format") in ("csv", "xlsx")


def lang_of(request):
    return "en" if request.query_params.get("lang") == "en" else "ar"


def label(group, value, lang):
    pair = LABELS[group].get(value)
    return (pair[0] if lang == "ar" else pair[1]) if pair else value


def local(dt):
    """Aware datetime → local time without tzinfo (Excel has no time zones)."""
    if isinstance(dt, datetime):
        return timezone.localtime(dt).replace(tzinfo=None, microsecond=0) if timezone.is_aware(dt) else dt
    return dt


def table_response(request, filename, columns, rows, title=None, footer=None):
    """columns: [(heading_ar, heading_en, kind)], rows: lists of values (None = empty cell).
    `title` (a line above the table) and `footer` (a totals row) are optional."""
    lang = lang_of(request)
    headings = [ar if lang == "ar" else en for ar, en, _ in columns]
    kinds = [kind for _, _, kind in columns]
    if request.query_params.get("format") == "xlsx":
        return _xlsx(f"{filename}.xlsx", headings, kinds, rows, title, footer, lang)
    return _csv(f"{filename}.csv", headings, kinds, rows, title, footer)


def _plain(value, kind):
    if value is None:
        return ""
    if isinstance(value, datetime):
        return local(value).strftime("%Y-%m-%d %H:%M")
    if isinstance(value, date):
        return value.isoformat()
    return value


def _csv(filename, headings, kinds, rows, title, footer):
    response = HttpResponse(content_type="text/csv; charset=utf-8")
    response["Content-Disposition"] = f'attachment; filename="{filename}"'
    response.write("﻿")  # BOM so Excel shows Arabic correctly
    w = csv.writer(response)
    if title:
        w.writerow(title if isinstance(title, list) else [title])
    w.writerow(headings)
    for row in rows:
        w.writerow([_plain(v, k) for v, k in zip(row, kinds)])
    if footer:
        w.writerow([])
        w.writerow([_plain(v, k) for v, k in zip(footer, kinds)])
    return response


def _xlsx(filename, headings, kinds, rows, title, footer, lang):
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Font, PatternFill
    from openpyxl.utils import get_column_letter

    wb = Workbook()
    ws = wb.active
    ws.title = "Alas"
    ws.sheet_view.rightToLeft = lang == "ar"
    bold = Font(bold=True)
    head_fill = PatternFill("solid", fgColor="23573A")
    widths = [max(len(str(h)) + 2, _MIN_WIDTH.get(k, 10)) for h, k in zip(headings, kinds)]

    def put(row_idx, values, font=None):
        for col, (value, kind) in enumerate(zip(values, kinds), start=1):
            if isinstance(value, Decimal):
                value = float(value)
            if isinstance(value, datetime):
                value = local(value)
            cell = ws.cell(row=row_idx, column=col, value=value)
            if kind in _FORMATS and value not in (None, ""):
                cell.number_format = _FORMATS[kind]
            if font:
                cell.font = font
            if kind == TEXT and value:
                widths[col - 1] = min(60, max(widths[col - 1], len(str(value)) + 2))

    r = 1
    if title:
        for col, value in enumerate(title if isinstance(title, list) else [title], start=1):
            ws.cell(row=r, column=col, value=value).font = Font(bold=True, size=13)
        r += 2
    header_row = r
    for col, h in enumerate(headings, start=1):
        c = ws.cell(row=r, column=col, value=h)
        c.font = Font(bold=True, color="FFFFFF")
        c.fill = head_fill
        c.alignment = Alignment(vertical="center", wrap_text=True)
    for row in rows:
        r += 1
        put(r, row)
    if footer:
        r += 2
        put(r, footer, bold)
    for col, width in enumerate(widths, start=1):
        ws.column_dimensions[get_column_letter(col)].width = width
    ws.freeze_panes = ws.cell(row=header_row + 1, column=1)
    ws.auto_filter.ref = f"A{header_row}:{get_column_letter(len(headings))}{max(header_row, r if not footer else r - 2)}"

    buf = io.BytesIO()
    wb.save(buf)
    response = HttpResponse(buf.getvalue(), content_type=XLSX_TYPE)
    response["Content-Disposition"] = f'attachment; filename="{filename}"'
    return response
