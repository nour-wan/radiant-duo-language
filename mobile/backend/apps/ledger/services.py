"""Customer account (receivables). All balances are computed here from ledger entries."""

from decimal import Decimal

from django.db.models import F, Sum, Window

from apps.core.errors import BusinessError
from apps.store.models import StoreSettings

from .models import LedgerEntry

ZERO = Decimal("0.00")
OPEN_STATUSES = ["pending", "confirmed", "shipped"]


def _money(value):
    return (value or ZERO).quantize(Decimal("0.01"))


def balance(user):
    """What the customer owes now (negative = the customer has credit with the store)."""
    return _money(LedgerEntry.objects.filter(user=user).aggregate(s=Sum("amount"))["s"])


def credit_limit_for(user):
    """The customer's own limit, else the store default. None = no limit (or credit not enabled)."""
    if not user.credit_enabled:
        return None
    if user.credit_limit is not None:
        return user.credit_limit
    return StoreSettings.load().default_credit_limit


def open_orders_total(user):
    return _money(user.orders.filter(status__in=OPEN_STATUSES).aggregate(s=Sum("total"))["s"])


def credit_info(user):
    owed = balance(user)
    limit = credit_limit_for(user)
    info = {
        "balance": owed, "credit_limit": limit, "open_orders": open_orders_total(user), "available": None,
        "credit_enabled": user.credit_enabled,
    }
    if limit is not None:
        info["available"] = _money(max(ZERO, limit - owed - info["open_orders"]))
    return info


def credit_problem(user, order_total):
    """'credit_limit_exceeded' when this order would take the customer over the limit."""
    if not user or not user.is_authenticated:
        return None
    info = credit_info(user)
    if info["credit_limit"] is not None and order_total > info["available"]:
        return "credit_limit_exceeded"
    return None


def record_order_delivered(order, by=None):
    """A delivered order is added to what the customer owes (once per order)."""
    if not order.user_id or order.total <= 0:
        return None
    entry, _ = LedgerEntry.objects.get_or_create(
        order=order, kind=LedgerEntry.ORDER,
        defaults={"user_id": order.user_id, "amount": order.total, "created_by": by},
    )
    return entry


def record_payment(user, amount, by, order=None, note=""):
    if amount is None or amount <= 0:
        raise BusinessError("invalid_amount")
    if order is not None and (order.user_id != user.pk or order.status == "cancelled"):
        raise BusinessError("invalid_order")
    return LedgerEntry.objects.create(user=user, kind=LedgerEntry.PAYMENT, amount=-amount, order=order, note=note, created_by=by)


def record_adjustment(user, amount, by, note):
    """Correction entry: positive adds to the debt, negative reduces it. A reason is required."""
    if amount is None or amount == 0:
        raise BusinessError("invalid_amount")
    if not note.strip():
        raise BusinessError("note_required")
    return LedgerEntry.objects.create(user=user, kind=LedgerEntry.ADJUSTMENT, amount=amount, note=note.strip(), created_by=by)


def order_paid(order):
    paid = order.ledger_entries.filter(kind=LedgerEntry.PAYMENT).aggregate(s=Sum("amount"))["s"]
    return -_money(paid)


def statement(user):
    """Entries newest first, each with the balance right after it."""
    return (
        LedgerEntry.objects.filter(user=user)
        .select_related("order")
        .annotate(balance_after=Window(Sum("amount"), order_by=[F("created_at").asc(), F("id").asc()]))
        .order_by("-created_at", "-id")
    )


def receivables():
    """[(user_id, balance)] for customers whose balance is not zero, largest debt first."""
    rows = LedgerEntry.objects.filter(user__isnull=False).values("user").annotate(b=Sum("amount")).exclude(b=0).order_by("-b")
    return [(r["user"], _money(r["b"])) for r in rows]
