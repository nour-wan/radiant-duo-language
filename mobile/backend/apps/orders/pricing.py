"""Server-side pricing. Clients only send variant ids, quantities and a coupon
code; every price, discount and total is computed here from the database."""

from dataclasses import dataclass, field
from decimal import ROUND_HALF_UP, Decimal

from django.db import transaction
from django.db.models import F

from apps.catalog.models import Product, Variant
from apps.core.errors import BusinessError
from apps.core.images import absolute_media_url
from apps.ledger import services as ledger
from apps.promotions.models import Coupon, CouponRedemption
from apps.store.delivery import fee_for_area
from apps.store.models import StoreSettings

from .models import Order, OrderEvent, OrderItem

MAX_LINES = 100
MAX_QTY = 100_000


@dataclass
class Line:
    variant: Variant
    quantity: int
    problem: str | None = None

    @property
    def unit_price(self):
        return self.variant.effective_price

    @property
    def line_total(self):
        return self.unit_price * self.quantity


@dataclass
class Quote:
    lines: list = field(default_factory=list)
    subtotal: Decimal = Decimal("0")
    discount: Decimal = Decimal("0")
    app_discount_percent: Decimal = Decimal("0")
    app_discount: Decimal = Decimal("0")
    total: Decimal = Decimal("0")
    coupon: Coupon | None = None
    coupon_problem: str | None = None
    order_problem: str | None = None
    delivery_method: str = Order.DELIVERY
    delivery_zone: object = None
    delivery_area: object = None
    delivery_fee: Decimal = Decimal("0")
    credit: dict | None = None

    @property
    def ok(self):
        return not self.order_problem and not any(line.problem for line in self.lines) and not self.coupon_problem


def _parse_items(items):
    if not isinstance(items, list) or not items:
        raise BusinessError("cart_empty")
    if len(items) > MAX_LINES:
        raise BusinessError("cart_too_large")
    merged = {}
    for item in items:
        try:
            vid, qty = int(item["variant_id"]), int(item["quantity"])
        except (KeyError, TypeError, ValueError):
            raise BusinessError("cart_invalid")
        if qty < 1 or qty > MAX_QTY:
            raise BusinessError("cart_invalid")
        merged[vid] = merged.get(vid, 0) + qty
    return merged


def _money(value):
    return value.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def build_quote(items, coupon_code, user, lock=False, delivery_method=None, area_id=None):
    wanted = _parse_items(items)
    variants = Variant.objects.select_related("product", "product__category").filter(id__in=wanted).order_by("id")
    if lock:
        variants = variants.select_for_update(of=("self",))
    by_id = {v.id: v for v in variants}
    quote = Quote()
    for vid, qty in wanted.items():
        v = by_id.get(vid)
        if v is None:
            raise BusinessError("item_unavailable", variant_id=vid)
        line = Line(v, qty)
        if not (v.is_active and v.product.is_active and v.product.category.is_active):
            line.problem = "item_unavailable"
        elif qty < v.min_order_qty:
            line.problem = "below_min_qty"
        elif qty > v.stock:
            line.problem = "insufficient_stock"
        quote.lines.append(line)
        if not line.problem:
            quote.subtotal += line.line_total

    store = StoreSettings.load()
    if not store.orders_enabled:
        quote.order_problem = "orders_disabled"
    elif quote.subtotal < store.min_order_total:
        quote.order_problem = "below_min_order_total"

    code = (coupon_code or "").strip().upper()
    if code:
        coupons = Coupon.objects.filter(code=code)
        if lock:
            coupons = coupons.select_for_update()
        quote.coupon = coupons.first()
        if quote.coupon is None:
            quote.coupon_problem = "coupon_invalid"
        else:
            quote.coupon_problem = quote.coupon.problem_for(user if user and user.is_authenticated else None, quote.subtotal)
            if not quote.coupon_problem:
                quote.discount = quote.coupon.discount_for(quote.subtotal)

    # Discount for ordering through the app (phone orders don't get it)
    if store.app_discount_enabled and store.app_discount_percent > 0:
        quote.app_discount_percent = store.app_discount_percent
        quote.app_discount = _money((quote.subtotal - quote.discount) * store.app_discount_percent / Decimal("100"))
    quote.total = quote.subtotal - quote.discount - quote.app_discount

    # Unpaid balance limit (customer's own limit, else the store default; none = unlimited)
    if user and user.is_authenticated:
        quote.credit = ledger.credit_info(user)
        if not quote.order_problem:
            quote.order_problem = ledger.credit_problem(user, quote.total)

    # Delivery: pickup is free; delivery fee depends on the customer's area (separate currency)
    method = delivery_method or (Order.DELIVERY if store.delivery_enabled else Order.PICKUP)
    if method == Order.PICKUP and not store.pickup_enabled:
        method = Order.DELIVERY
    if method == Order.DELIVERY and not store.delivery_enabled:
        method = Order.PICKUP
    quote.delivery_method = method
    if method == Order.DELIVERY:
        quote.delivery_zone, quote.delivery_area, quote.delivery_fee = fee_for_area(area_id)
    return quote


def quote_payload(quote):
    store = StoreSettings.load()
    return {
        "lines": [
            {
                "variant_id": line.variant.id,
                "product_id": line.variant.product_id,
                "quantity": line.quantity,
                "unit_price": str(line.unit_price),
                "regular_price": str(line.variant.price),
                "line_total": str(line.line_total),
                "stock": line.variant.stock,
                "min_order_qty": line.variant.min_order_qty,
                "problem": line.problem,
            }
            for line in quote.lines
        ],
        "subtotal": str(quote.subtotal),
        "discount": str(quote.discount),
        "app_discount_percent": str(quote.app_discount_percent),
        "app_discount": str(quote.app_discount),
        "total": str(quote.total),
        "delivery_method": quote.delivery_method,
        "delivery_zone_ar": quote.delivery_zone.name_ar if quote.delivery_zone else None,
        "delivery_zone_en": quote.delivery_zone.name_en if quote.delivery_zone else None,
        "delivery_area_listed": quote.delivery_area is not None,
        "delivery_fee": str(quote.delivery_fee),
        "delivery_currency_ar": store.delivery_currency_ar,
        "delivery_currency_en": store.delivery_currency_en,
        "coupon_code": quote.coupon.code if quote.coupon and not quote.coupon_problem else None,
        "coupon_problem": quote.coupon_problem,
        "order_problem": quote.order_problem,
        "min_order_total": str(store.min_order_total),
        "currency": "USD",
        "credit_limit": str(quote.credit["credit_limit"]) if quote.credit and quote.credit["credit_limit"] is not None else None,
        "credit_available": str(quote.credit["available"]) if quote.credit and quote.credit["available"] is not None else None,
        "ok": quote.ok,
    }


@transaction.atomic
def place_order(user, items, coupon_code, contact, client_ref="", delivery_method=None, area_id=None):
    if client_ref:
        existing = Order.objects.filter(user=user, client_ref=client_ref).first()
        if existing:
            return existing, False
    # Lock the customer so two orders at once can't both pass the credit limit check
    type(user).objects.select_for_update().filter(pk=user.pk).first()
    quote = build_quote(items, coupon_code, user, lock=True, delivery_method=delivery_method, area_id=area_id)
    if quote.order_problem:
        raise BusinessError(quote.order_problem)
    for line in quote.lines:
        if line.problem:
            raise BusinessError(line.problem, variant_id=line.variant.id)
    if quote.coupon_problem:
        raise BusinessError(quote.coupon_problem)

    order = Order.objects.create(
        user=user,
        client_ref=client_ref,
        customer_email=user.email or "",
        subtotal=quote.subtotal,
        discount=quote.discount,
        app_discount_percent=quote.app_discount_percent,
        app_discount=quote.app_discount,
        total=quote.total,
        coupon_code=quote.coupon.code if quote.coupon else "",
        delivery_method=quote.delivery_method,
        delivery_zone=quote.delivery_zone.name_ar if quote.delivery_zone else "",
        delivery_fee=quote.delivery_fee,
        delivery_currency=StoreSettings.load().delivery_currency_ar if quote.delivery_method == Order.DELIVERY else "",
        **contact,
    )
    for line in quote.lines:
        v, product = line.variant, line.variant.product
        first_image = product.images.order_by("sort_order", "id").first()
        OrderItem.objects.create(
            order=order,
            product=product,
            variant=v,
            product_name_ar=product.name_ar,
            product_name_en=product.name_en,
            variant_label_ar=v.label_ar,
            variant_label_en=v.label_en,
            image=absolute_media_url(first_image.thumbnail or first_image.image) if first_image else "",
            unit_price=line.unit_price,
            quantity=line.quantity,
            line_total=line.line_total,
        )
        Variant.objects.filter(pk=v.pk).update(stock=F("stock") - line.quantity)
        Product.objects.filter(pk=product.pk).update(sold_count=F("sold_count") + line.quantity)
    if quote.coupon:
        Coupon.objects.filter(pk=quote.coupon.pk).update(used_count=F("used_count") + 1)
        CouponRedemption.objects.create(coupon=quote.coupon, user=user, order=order)
    OrderEvent.objects.create(order=order, status=Order.PENDING)
    return order, True


@transaction.atomic
def change_status(order, new_status, note="", by_admin=True, by=None):
    order = Order.objects.select_for_update().get(pk=order.pk)
    if not order.can_move_to(new_status):
        raise BusinessError("invalid_status_change")
    if new_status == Order.CANCELLED:
        for item in order.items.all():
            if item.variant_id:
                Variant.objects.filter(pk=item.variant_id).update(stock=F("stock") + item.quantity)
            if item.product_id:
                Product.objects.filter(pk=item.product_id, sold_count__gte=item.quantity).update(
                    sold_count=F("sold_count") - item.quantity
                )
        redemption = CouponRedemption.objects.filter(order=order).first()
        if redemption:
            Coupon.objects.filter(pk=redemption.coupon_id, used_count__gt=0).update(used_count=F("used_count") - 1)
            redemption.delete()
    order.status = new_status
    order.save(update_fields=["status", "updated_at"])
    OrderEvent.objects.create(order=order, status=new_status, note=note, by_admin=by_admin)
    if new_status == Order.DELIVERED:
        ledger.record_order_delivered(order, by)
    return order
