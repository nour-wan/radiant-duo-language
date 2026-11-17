"""US dollar → Syrian pound exchange rate.

Product prices are entered by the admin in US dollars. Customers only ever see Syrian pounds
(new pound, after the two zeros were removed): each price is the dollar price × today's rate,
rounded to the store's rounding step. Orders, the customer ledger, coupons, the minimum order and
credit limits are all kept in Syrian pounds; an order keeps the rate it was placed with.

The rate is read from the public "الليرة اليوم" (sp-today.com) page every 15 minutes by the
`update_exchange_rate` command (cron). The owner can switch to a manual rate in the admin app.
"""

import logging
import re
import urllib.request
from datetime import timedelta
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation

from django.utils import timezone

log = logging.getLogger(__name__)

SOURCE_URL = "https://sp-today.com/"
USER_AGENT = "Mozilla/5.0 (compatible; AlasFoodstuff/1.0)"
# A plausible USD rate in NEW Syrian pounds. The page quotes old pounds (×100).
MIN_RATE, MAX_RATE = Decimal("20"), Decimal("2000")
# A change bigger than this between two readings is held back until the owner checks it
MAX_JUMP = Decimal("0.20")
STALE_AFTER = timedelta(hours=6)

_cache = {"at": None, "value": None}
_CACHE_SECONDS = 15


class RateUnavailable(Exception):
    pass


def _to_new_pounds(value):
    value = Decimal(str(value))
    if value > Decimal("1000"):  # old pounds
        value = value / Decimal("100")
    return value.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def parse_sp_today(html):
    """{'buy': Decimal, 'sell': Decimal, 'updated_at': str} for USD in Damascus, from the page HTML."""
    text = html.replace('\\"', '"')
    m = re.search(r'"code":"USD".{0,400}?"damascus":\{"buy":([0-9.]+),"sell":([0-9.]+)', text, re.S)
    if not m:
        raise RateUnavailable("usd_not_found")
    updated = re.search(r'"code":"USD".{0,1500}?"updated_at":"([^"]+)"', text, re.S)
    try:
        buy, sell = _to_new_pounds(m.group(1)), _to_new_pounds(m.group(2))
    except InvalidOperation:
        raise RateUnavailable("bad_number")
    if not (MIN_RATE <= buy <= MAX_RATE and MIN_RATE <= sell <= MAX_RATE):
        raise RateUnavailable("out_of_range")
    return {"buy": buy, "sell": sell, "updated_at": updated.group(1) if updated else ""}


def fetch_sp_today(timeout=20):
    req = urllib.request.Request(SOURCE_URL, headers={"User-Agent": USER_AGENT, "Accept": "text/html"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310 (fixed https URL)
        html = resp.read(3_000_000).decode("utf-8", "replace")
    return parse_sp_today(html)


def _settings():
    from .models import StoreSettings

    return StoreSettings.load()


def latest_auto():
    from .models import ExchangeRate

    return ExchangeRate.objects.filter(accepted=True).order_by("-fetched_at", "-id").first()


def rate_from(store, auto=None):
    """The rate used for prices with these settings, or None if there is none yet."""
    if store.usd_rate_mode == "manual":
        return store.usd_rate_manual
    auto = auto if auto is not None else latest_auto()
    if auto is None:
        return store.usd_rate_manual  # nothing fetched yet: fall back to the manual value if set
    return auto.sell if store.usd_rate_side == "sell" else auto.buy


def current_rate():
    """Rate in use now (cached for a few seconds per process). Raises RateUnavailable."""
    now = timezone.now()
    if _cache["at"] and (now - _cache["at"]).total_seconds() < _CACHE_SECONDS and _cache["value"]:
        return _cache["value"]
    rate = rate_from(_settings())
    if not rate or rate <= 0:
        raise RateUnavailable("no_rate")
    _cache.update(at=now, value=rate)
    return rate


def clear_cache():
    _cache.update(at=None, value=None)


def rate_or_none():
    try:
        return current_rate()
    except RateUnavailable:
        return None


def round_syp(value, step=None):
    """Round to the store's step (e.g. nearest 10 pounds). Whole pounds at least."""
    step = Decimal(step if step is not None else _settings().syp_rounding or 1)
    if step < 1:
        step = Decimal(1)
    return ((Decimal(value) / step).quantize(Decimal("1"), rounding=ROUND_HALF_UP) * step).quantize(Decimal("0.01"))


def to_syp(usd, rate=None, step=None):
    """Customer price in Syrian pounds for a dollar price."""
    if usd is None:
        return None
    rate = rate if rate is not None else current_rate()
    return round_syp(Decimal(usd) * rate, step)


def whole(value):
    """Amounts in Syrian pounds are whole numbers."""
    return Decimal(value).quantize(Decimal("1"), rounding=ROUND_HALF_UP).quantize(Decimal("0.01"))


def fmt(amount, lang="ar"):
    """'1,870 ل.س' / '1,870 SYP' for messages and notifications."""
    amount = Decimal(amount or 0)
    text = f"{amount:,.0f}" if amount == amount.to_integral_value() else f"{amount:,.2f}"
    return f"{text} ل.س" if lang == "ar" else f"{text} SYP"


def update_from_source(fetch=fetch_sp_today):
    """Fetch and store a new reading. Returns (ExchangeRate | None, problem | None)."""
    from apps.notifications import events

    from .models import ExchangeRate

    store = _settings()
    previous = latest_auto()
    try:
        reading = fetch()
    except Exception as exc:  # network, parsing, range
        problem = str(exc) or exc.__class__.__name__
        log.warning("Exchange rate fetch failed: %s", problem)
        store.usd_rate_error = problem[:200]
        store.save(update_fields=["usd_rate_error"])
        last_ok = previous.fetched_at if previous else None
        if (last_ok is None or timezone.now() - last_ok > STALE_AFTER) and _alert_due(store):
            events.exchange_rate_problem("stale", last_ok)
        return None, problem

    accepted = True
    if previous is not None:
        old = previous.sell if store.usd_rate_side == "sell" else previous.buy
        new = reading["sell"] if store.usd_rate_side == "sell" else reading["buy"]
        if old and abs(new - old) / old > MAX_JUMP:
            accepted = False
    entry = ExchangeRate.objects.create(
        buy=reading["buy"], sell=reading["sell"], source_updated_at=reading.get("updated_at", "")[:40], accepted=accepted,
    )
    store.usd_rate_error = "" if accepted else "jump_held"
    store.save(update_fields=["usd_rate_error"])
    clear_cache()
    if not accepted and _alert_due(store):
        events.exchange_rate_problem("jump", previous.fetched_at, entry)
    # Keep the history small: a reading every 15 minutes for 90 days is plenty
    cutoff = timezone.now() - timedelta(days=90)
    ExchangeRate.objects.filter(fetched_at__lt=cutoff).delete()
    return entry, None if accepted else "jump_held"


def _alert_due(store):
    """At most one alert to the admins every 6 hours."""
    now = timezone.now()
    if store.usd_rate_alerted_at and now - store.usd_rate_alerted_at < STALE_AFTER:
        return False
    store.usd_rate_alerted_at = now
    store.save(update_fields=["usd_rate_alerted_at"])
    return True


def accept(entry):
    """Owner confirmed a held-back reading (a big real move)."""
    entry.accepted = True
    entry.save(update_fields=["accepted"])
    store = _settings()
    store.usd_rate_error = ""
    store.save(update_fields=["usd_rate_error"])
    clear_cache()


def status():
    """Everything the admin app shows about the rate."""
    store = _settings()
    auto = latest_auto()
    from .models import ExchangeRate

    held = None

    newest = ExchangeRate.objects.order_by("-fetched_at", "-id").first()
    if newest is not None and not newest.accepted:
        held = {"id": newest.id, "buy": str(newest.buy), "sell": str(newest.sell), "fetched_at": newest.fetched_at}
    rate = rate_from(store, auto)
    return {
        "rate": str(rate) if rate else None,
        "mode": store.usd_rate_mode,
        "side": store.usd_rate_side,
        "manual": str(store.usd_rate_manual) if store.usd_rate_manual is not None else None,
        "rounding": store.syp_rounding,
        "auto_buy": str(auto.buy) if auto else None,
        "auto_sell": str(auto.sell) if auto else None,
        "fetched_at": auto.fetched_at if auto else None,
        "source_updated_at": auto.source_updated_at if auto else None,
        "stale": bool(store.usd_rate_mode == "auto" and (auto is None or timezone.now() - auto.fetched_at > STALE_AFTER)),
        "error": store.usd_rate_error,
        "held": held,
        "source": "sp-today.com",
    }
