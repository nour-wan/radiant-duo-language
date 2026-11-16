"""Order invoice as a PDF (Arabic or English), shared by the store and admin apps.

Drawn with fpdf2 + HarfBuzz shaping: pure Python wheels, no system libraries.
The layout is written left-to-right and mirrored for Arabic by `_x()`.
"""

import logging
import re
from decimal import Decimal
from pathlib import Path

from django.conf import settings
from django.utils import timezone
from fpdf import FPDF

from apps.ledger import services as ledger
from apps.store.models import StoreSettings

from .models import Order

ASSETS = Path(settings.BASE_DIR) / "assets" / "invoice"
ARABIC = re.compile("[؀-ۿ]")

# fontTools logs every font subset at INFO level
logging.getLogger("fontTools").setLevel(logging.WARNING)

GREEN = (34, 90, 57)
GREEN_SOFT = (232, 241, 235)
CREAM = (243, 234, 219)
CREAM_SOFT = (251, 246, 238)
INK = (47, 29, 18)
MUTED = (120, 104, 90)
LINE = (224, 211, 192)
RED = (190, 45, 45)
WHITE = (255, 255, 255)

STATUS = {
    Order.PENDING: (("قيد المراجعة", "Pending"), (191, 120, 20)),
    Order.CONFIRMED: (("مؤكد", "Confirmed"), (40, 110, 170)),
    Order.SHIPPED: (("قيد التوصيل", "On the way"), (110, 80, 170)),
    Order.DELIVERED: (("تم التسليم", "Delivered"), GREEN),
    Order.CANCELLED: (("ملغي", "Cancelled"), RED),
}

PICKUP_STATUS = {Order.SHIPPED: ("جاهز للاستلام", "Ready for pickup"), Order.DELIVERED: ("تم الاستلام", "Picked up")}

TEXT = {
    "invoice": ("فاتورة", "INVOICE"),
    "tagline": ("مكونات غذائية بأسعار الجملة", "Wholesale food ingredients"),
    "number": ("رقم الفاتورة", "Invoice no."),
    "date": ("التاريخ", "Date"),
    "status": ("الحالة", "Status"),
    "from": ("من", "From"),
    "to": ("إلى", "Bill to"),
    "item": ("المنتج", "Item"),
    "qty": ("الكمية", "Qty"),
    "unit_price": ("سعر الوحدة", "Unit price"),
    "line_total": ("المجموع", "Amount"),
    "subtotal": ("المجموع الفرعي", "Subtotal"),
    "coupon": ("خصم الكوبون", "Coupon discount"),
    "app_discount": ("خصم التطبيق", "App discount"),
    "total": ("الإجمالي", "Total"),
    "paid": ("المدفوع", "Paid"),
    "credit_used": ("مخصوم من رصيد العميل", "Paid from account credit"),
    "remaining": ("المتبقي", "Balance due"),
    "payment": ("طريقة الدفع", "Payment"),
    "cod": ("الدفع نقدي عند الاستلام", "Cash on delivery"),
    "receiving": ("الاستلام", "Receiving"),
    "delivery": ("توصيل", "Delivery"),
    "pickup": ("استلام من المحل", "Store pickup"),
    "delivery_fee": ("أجرة التوصيل", "Delivery fee"),
    "fee_note": ("تدفع عند الاستلام ولا تدخل في الفاتورة", "Paid on receipt, not part of this invoice"),
    "notes": ("ملاحظات", "Notes"),
    "usd": ("جميع المبالغ بالدولار الأمريكي", "All amounts in US dollars"),
    "thanks": ("نشكركم على تعاملكم معنا", "Thank you for your business"),
    "page": ("صفحة", "Page"),
}


def _money(value):
    return f"${Decimal(value):,.2f}"


class InvoicePDF(FPDF):
    M = 14  # page margin (mm)

    def __init__(self, lang):
        super().__init__(format="A4", unit="mm")
        self.lang = lang
        self.rtl = lang == "ar"
        self.i = 0 if self.rtl else 1
        self.set_margins(self.M, self.M, self.M)
        self.set_auto_page_break(False)
        for style, weight in (("", "400"), ("B", "700")):
            self.add_font("kufi", style, ASSETS / f"NotoKufiArabic-{weight}.ttf")
            self.add_font("manrope", style, ASSETS / f"Manrope-{weight}.ttf")
        self.page_label = ""

    # -- helpers -------------------------------------------------------
    def t(self, key):
        return TEXT[key][self.i]

    def _x(self, x, w):
        """Logical x (from the reading start) → page x."""
        return self.w - x - w if self.rtl else x

    def _align(self, align):
        if align == "start":
            return "R" if self.rtl else "L"
        if align == "end":
            return "L" if self.rtl else "R"
        return "C"

    def text(self, x, y, w, h, value, size=9.5, bold=False, color=INK, align="start", font=None):
        # Font and direction follow the text itself: customer names, notes and
        # addresses can be Arabic on an English invoice and the other way round.
        arabic = bool(ARABIC.search(str(value)))
        self.set_text_shaping(use_shaping_engine=True, direction="rtl" if arabic else "ltr")
        self.set_font(font or ("kufi" if arabic else "manrope"), "B" if bold else "", size)
        self.set_text_color(*color)
        value = str(value)
        while value and self.get_string_width(value) > w - 1:
            value = value[:-2] + "…"
        self.set_xy(self._x(x, w), y)
        self.cell(w, h, value, align=self._align(align))

    def box(self, x, y, w, h, fill, radius=2.5, border=None):
        self.set_fill_color(*fill)
        if border:
            self.set_draw_color(*border)
            self.set_line_width(0.3)
        self.rect(self._x(x, w), y, w, h, style="DF" if border else "F", round_corners=True, corner_radius=radius)

    def footer(self):
        y = self.h - 16
        self.set_draw_color(*LINE)
        self.set_line_width(0.3)
        self.line(self.M, y, self.w - self.M, y)
        self.text(self.M, y + 2, 110, 6, self.page_label, size=8, color=MUTED)
        self.text(self.w - self.M - 40, y + 2, 40, 6, f"{self.t('page')} {self.page_no()}", size=8, color=MUTED, align="end")


def build_invoice(order, lang="ar"):
    """Return the invoice PDF for `order` as bytes."""
    s = StoreSettings.load()
    pdf = InvoicePDF(lang)
    ar = pdf.rtl
    M, W = pdf.M, pdf.w - 2 * pdf.M
    pick = (lambda a, e: (a or e) if ar else (e or a))
    pdf.page_label = " · ".join(p for p in [s.website.replace("https://", ""), s.email, s.whatsapp] if p)
    pdf.add_page()

    # Header band
    pdf.set_fill_color(*GREEN)
    pdf.rect(0, 0, pdf.w, 40, style="F")
    pdf.image(str(ASSETS / "logo.png"), x=pdf._x(M, 22), y=9, w=22, h=22)
    pdf.text(M + 27, 10, 100, 9, pick(s.name_ar, s.name_en), size=14, bold=True, color=WHITE)
    pdf.text(M + 27, 20, 100, 7, pdf.t("tagline"), size=9.5, color=CREAM)
    pdf.text(M + W - 60, 9, 60, 12, pdf.t("invoice"), size=22, bold=True, color=CREAM, align="end")
    pdf.text(M + W - 60, 22, 60, 7, order.number, size=11, bold=True, color=WHITE, align="end", font="manrope")

    # Number / date / status
    y = 48
    (status_ar, status_en), status_color = STATUS.get(order.status, ((order.status, order.status), MUTED))
    if order.delivery_method == Order.PICKUP and order.status in PICKUP_STATUS:
        status_ar, status_en = PICKUP_STATUS[order.status]
    cells = [
        (pdf.t("number"), order.number, INK),
        (pdf.t("date"), timezone.localtime(order.created_at).strftime("%Y-%m-%d  %H:%M"), INK),
        (pdf.t("status"), status_ar if ar else status_en, status_color),
    ]
    cw = (W - 8) / 3
    for n, (label, value, color) in enumerate(cells):
        x = M + n * (cw + 4)
        pdf.box(x, y, cw, 17, CREAM_SOFT, border=LINE)
        pdf.text(x + 4, y + 2, cw - 8, 6, label, size=8, color=MUTED)
        pdf.text(x + 4, y + 8.5, cw - 8, 7, value, size=10.5, bold=True, color=color)

    # From / bill to
    y = 72
    half = (W - 6) / 2
    store_lines = [
        pick(s.name_ar, s.name_en),
        " · ".join(p for p in [s.mobile, s.phone] if p),
        s.email,
        pick(s.address_ar, s.address_en) or pick(s.pickup_address_ar, s.pickup_address_en),
    ]
    if order.delivery_method == Order.DELIVERY:
        where = " - ".join(p for p in [order.city, order.area, order.street, order.address_details] if p)
    else:
        where = f"{pdf.t('pickup')}: {pick(s.pickup_address_ar, s.pickup_address_en)}"
    customer_lines = [order.business_name or order.customer_name, order.customer_name if order.business_name else "",
                      order.customer_phone, where]
    for n, (title, lines) in enumerate([(pdf.t("from"), store_lines), (pdf.t("to"), customer_lines)]):
        x = M + n * (half + 6)
        lines = [line for line in lines if line]
        pdf.box(x, y, half, 36, WHITE, border=LINE)
        pdf.box(x, y, 3, 36, GREEN, radius=1)
        pdf.text(x + 7, y + 3, half - 10, 6, title, size=8, bold=True, color=GREEN)
        for k, line in enumerate(lines[:4]):
            pdf.text(x + 7, y + 10 + k * 6, half - 10, 6, line, size=9.5 if k else 10.5, bold=k == 0)

    # Items table
    cols = [("#", 9, "center"), (pdf.t("item"), W - 9 - 20 - 30 - 32, "start"),
            (pdf.t("qty"), 20, "center"), (pdf.t("unit_price"), 30, "end"), (pdf.t("line_total"), 32, "end")]

    def table_header(y):
        pdf.box(M, y, W, 9, GREEN, radius=2)
        x = M
        for title, w, align in cols:
            pdf.text(x + 2, y + 1.2, w - 4, 7, title, size=8.5, bold=True, color=WHITE, align=align)
            x += w
        return y + 9

    y = table_header(116)
    for n, item in enumerate(order.items.all(), start=1):
        if y > pdf.h - 30:
            pdf.add_page()
            y = table_header(M)
        if n % 2 == 0:
            pdf.box(M, y, W, 13, CREAM_SOFT, radius=0)
        values = [
            (str(n), "center", INK),
            None,
            (str(item.quantity), "center", INK),
            (_money(item.unit_price), "end", INK),
            (_money(item.line_total), "end", INK),
        ]
        x = M
        for (title, w, align), value in zip(cols, values):
            if value is None:
                pdf.text(x + 2, y + 1, w - 4, 6, pick(item.product_name_ar, item.product_name_en), size=9.5, bold=True)
                pdf.text(x + 2, y + 6.5, w - 4, 5, pick(item.variant_label_ar, item.variant_label_en), size=8, color=MUTED)
            else:
                pdf.text(x + 2, y + 3.5, w - 4, 6, value[0], size=9.5, bold=align == "end" and title == pdf.t("line_total"),
                         color=value[2], align=value[1])
            x += w
        y += 13
    pdf.set_draw_color(*LINE)
    pdf.line(M, y, M + W, y)

    # Totals (end side) and payment details (start side)
    rows = [(pdf.t("subtotal"), _money(order.subtotal), INK)]
    if order.discount > 0:
        rows.append((f"{pdf.t('coupon')} ({order.coupon_code})", f"- {_money(order.discount)}", RED))
    if order.app_discount > 0:
        rows.append((f"{pdf.t('app_discount')} ({order.app_discount_percent.normalize():f}%)", f"- {_money(order.app_discount)}", GREEN))
    paid = remaining = None
    credit = ledger.credit_for_order(order) if order.status == Order.DELIVERED else ledger.ZERO
    if order.status == Order.DELIVERED:
        paid = ledger.order_paid(order)
        remaining = ledger.to_collect(order)
    needed = 12 + len(rows) * 7 + 12 + (16 if paid is not None else 0) + (7 if credit else 0)
    if y + needed > pdf.h - 24:
        pdf.add_page()
        y = M
    y += 5
    tw = 88
    tx = M + W - tw
    for label, value, color in rows:
        pdf.text(tx, y, tw - 34, 7, label, size=9.5, color=MUTED)
        pdf.text(tx + tw - 34, y, 34, 7, value, size=9.5, color=color, align="end")
        y += 7
    pdf.box(tx, y + 1, tw, 11, GREEN, radius=2.5)
    pdf.text(tx + 4, y + 2.5, tw - 40, 8, pdf.t("total"), size=11, bold=True, color=WHITE)
    pdf.text(tx + tw - 40, y + 2.5, 36, 8, _money(order.total), size=12, bold=True, color=WHITE, align="end")
    y += 14
    if credit:
        pdf.text(tx, y, tw - 34, 7, pdf.t("credit_used"), size=9.5, color=MUTED)
        pdf.text(tx + tw - 34, y, 34, 7, f"- {_money(credit)}", size=9.5, color=GREEN, align="end")
        y += 7
    if paid is not None:
        pdf.text(tx, y, tw - 34, 7, pdf.t("paid"), size=9.5, color=MUTED)
        pdf.text(tx + tw - 34, y, 34, 7, _money(paid), size=9.5, color=GREEN, align="end")
        y += 7
        pdf.text(tx, y, tw - 34, 7, pdf.t("remaining"), size=10, bold=True)
        pdf.text(tx + tw - 34, y, 34, 7, _money(remaining), size=10, bold=True, color=RED if remaining > 0 else GREEN, align="end")
        y += 7

    # Payment box beside the totals
    bx, bw = M, W - tw - 8
    info = [
        (pdf.t("payment"), pdf.t("cod")),
        (pdf.t("receiving"), pdf.t("delivery") if order.delivery_method == Order.DELIVERY else pdf.t("pickup")),
    ]
    if order.delivery_method == Order.DELIVERY and order.delivery_fee:
        currency = pick(s.delivery_currency_ar, s.delivery_currency_en)
        info.append((pdf.t("delivery_fee"), f"{order.delivery_fee:,.0f} {currency} — {pdf.t('fee_note')}"))
    if order.notes:
        info.append((pdf.t("notes"), order.notes))
    top = y - (14 + len(rows) * 7 + (14 if paid is not None else 0) + (7 if credit else 0))
    height = 6 + len(info) * 11
    pdf.box(bx, top, bw, height, CREAM_SOFT, border=LINE)
    for k, (label, value) in enumerate(info):
        pdf.text(bx + 4, top + 3 + k * 11, bw - 8, 5, label, size=8, color=MUTED)
        pdf.text(bx + 4, top + 7.5 + k * 11, bw - 8, 6, value, size=9)
    y = max(y, top + height) + 8

    pdf.text(M, y, W, 6, pdf.t("usd"), size=8, color=MUTED)
    pdf.text(M, y + 7, W, 8, pdf.t("thanks"), size=11, bold=True, color=GREEN, align="center")
    return bytes(pdf.output())


def invoice_response(order, request):
    """PDF download; language from ?lang=en|ar (Arabic by default)."""
    from django.http import HttpResponse

    lang = "en" if request.query_params.get("lang") == "en" else "ar"
    response = HttpResponse(build_invoice(order, lang), content_type="application/pdf")
    response["Content-Disposition"] = f'attachment; filename="invoice-{order.number}.pdf"'
    return response
