"""One-time switch of existing money from US dollars to Syrian pounds.

Converts, at one rate: orders priced in USD (amounts and lines), every ledger entry (debts, payments,
adjustments), customer credit limits, the store's default credit limit and minimum order, and coupon
amounts. Product prices stay in USD (they are converted live for customers).
Original dollar figures are kept: Order.total_usd, OrderItem.unit_price_usd, LedgerEntry.original_usd.

    python manage.py convert_to_syp --dry-run
    python manage.py convert_to_syp            # uses the current rate
    python manage.py convert_to_syp --rate 149.50
"""

from decimal import Decimal

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from apps.accounts.models import User
from apps.ledger.models import LedgerEntry
from apps.orders.models import Order, OrderItem
from apps.promotions.models import Coupon
from apps.store import fx
from apps.store.models import StoreSettings


class Command(BaseCommand):
    help = "Convert existing USD orders, balances, limits and coupons to Syrian pounds (once)."

    def add_arguments(self, parser):
        parser.add_argument("--rate", type=Decimal, help="USD → SYP rate (new pounds). Default: the current rate.")
        parser.add_argument("--dry-run", action="store_true")

    def handle(self, *args, rate=None, dry_run=False, **opts):
        store = StoreSettings.load()
        if store.syp_converted_rate is not None:
            raise CommandError(f"Already converted at {store.syp_converted_rate}.")
        if rate is None:
            try:
                rate = fx.current_rate()
            except fx.RateUnavailable:
                raise CommandError("No exchange rate yet: run update_exchange_rate or pass --rate.")
        if not (fx.MIN_RATE <= rate <= fx.MAX_RATE):
            raise CommandError(f"Rate {rate} looks wrong (new Syrian pounds per dollar expected).")

        def syp(v):
            return None if v is None else fx.whole(Decimal(v) * rate)

        with transaction.atomic():
            orders = list(Order.objects.select_for_update().exclude(currency="SYP"))
            for o in orders:
                o.total_usd = o.total
                o.subtotal, o.discount, o.app_discount = syp(o.subtotal), syp(o.discount), syp(o.app_discount)
                o.total, o.credit_applied = syp(o.total), syp(o.credit_applied)
                o.exchange_rate, o.currency = rate, "SYP"
                o.save(update_fields=["total_usd", "subtotal", "discount", "app_discount", "total", "credit_applied",
                                      "exchange_rate", "currency"])
            items = list(OrderItem.objects.filter(order__in=orders))
            for i in items:
                i.unit_price_usd = i.unit_price
                i.unit_price, i.line_total = syp(i.unit_price), syp(i.line_total)
                i.save(update_fields=["unit_price_usd", "unit_price", "line_total"])

            entries = list(LedgerEntry.objects.select_for_update().filter(original_usd__isnull=True))
            for e in entries:
                e.original_usd = e.amount
                e.amount = syp(e.amount)
                e.save(update_fields=["original_usd", "amount"])

            users = list(User.objects.filter(credit_limit__isnull=False))
            for u in users:
                u.credit_limit = syp(u.credit_limit)
                u.save(update_fields=["credit_limit"])

            coupons = list(Coupon.objects.all())
            for c in coupons:
                if c.kind == Coupon.FIXED:
                    c.value = syp(c.value)
                c.min_order_total, c.max_discount = syp(c.min_order_total), syp(c.max_discount)
                c.save(update_fields=["value", "min_order_total", "max_discount"])

            store.min_order_total = syp(store.min_order_total)
            store.default_credit_limit = syp(store.default_credit_limit)
            store.syp_converted_rate = rate
            store.save(update_fields=["min_order_total", "default_credit_limit", "syp_converted_rate"])

            self.stdout.write(
                f"rate {rate}: {len(orders)} orders, {len(items)} order lines, {len(entries)} ledger entries, "
                f"{len(users)} customer limits, {len(coupons)} coupons, store limits"
            )
            if dry_run:
                transaction.set_rollback(True)
                self.stdout.write("dry run: nothing saved")
