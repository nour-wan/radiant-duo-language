"""Delivery locations: the customer's map pin and the driver's live position while an order is out for delivery."""

import math
from datetime import timedelta
from decimal import Decimal

from django.db import models
from django.utils import timezone

from apps.core.errors import BusinessError

from .models import DeliveryPoint, Order

# A position older than this is not shown to the customer (the driver's phone stopped reporting)
FRESH_FOR = timedelta(minutes=15)
# Rough city driving: roads are ~35% longer than the straight line, at ~22 km/h average
ROAD_FACTOR = 1.35
CITY_KMH = 22


def coordinate(value, limit):
    """A latitude/longitude as a 6-decimal Decimal, or BusinessError if it is out of range."""
    try:
        v = Decimal(str(value)).quantize(Decimal("0.000001"))
    except Exception:
        raise BusinessError("invalid_location")
    if not v.is_finite() or abs(v) > limit:
        raise BusinessError("invalid_location")
    return v


def distance_km(lat1, lng1, lat2, lng2):
    lat1, lng1, lat2, lng2 = map(lambda v: math.radians(float(v)), (lat1, lng1, lat2, lng2))
    a = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lng2 - lng1) / 2) ** 2
    return 6371 * 2 * math.asin(math.sqrt(a))


def eta_minutes(km):
    return max(1, round(km * ROAD_FACTOR / CITY_KMH * 60 + 1))


def is_trackable(order):
    return order.status == Order.SHIPPED and order.delivery_method == Order.DELIVERY


def tracking(order):
    """What the customer sees while the order is on its way, or None."""
    if not is_trackable(order) or order.driver_location_at is None or order.driver_latitude is None:
        return None
    if timezone.now() - order.driver_location_at > FRESH_FOR:
        return None
    data = {
        "latitude": float(order.driver_latitude),
        "longitude": float(order.driver_longitude),
        "updated_at": order.driver_location_at,
        "distance_km": None,
        "eta_minutes": None,
    }
    if order.latitude is not None:
        km = distance_km(order.driver_latitude, order.driver_longitude, order.latitude, order.longitude)
        data["distance_km"] = round(km * ROAD_FACTOR, 1)
        data["eta_minutes"] = eta_minutes(km)
    return data


def assign_driver(order, user):
    """[user] delivers [order] from now on (a new driver starts with no position)."""
    if order.driver_id != user.pk:
        order.driver = user
        order.driver_latitude = order.driver_longitude = order.driver_location_at = None
        order.save(update_fields=["driver", "driver_latitude", "driver_longitude", "driver_location_at", "updated_at"])
    return order


# Points a phone kept while offline are accepted if recorded within this window
MAX_BACKLOG = timedelta(hours=12)
MAX_POINTS_PER_REPORT = 500


def _parse(value):
    from django.utils.dateparse import parse_datetime

    try:
        at = parse_datetime(str(value)) if value else None
    except ValueError:
        return None
    if at is not None and timezone.is_naive(at):
        at = timezone.make_aware(at)
    return at


def _when(value, now, skew):
    """The time the phone recorded a point, moved by the phone's clock error and kept within
    [now - MAX_BACKLOG, now]."""
    at = _parse(value)
    if at is None:
        return now
    return min(max(at + skew, now - MAX_BACKLOG), now)


def report_location(order, user, points, sent_at=None):
    """The driver's phone reports where it is: one point now, or several it kept while offline
    ([{latitude, longitude, at}]). Every point is kept for the route. Returns False when tracking
    should stop (delivered, cancelled or handed to someone else)."""
    if not is_trackable(order):
        return False
    if order.driver_id is None:
        assign_driver(order, user)
    elif order.driver_id != user.pk:
        return False
    now = timezone.now()
    # The phone's clock may be off: [sent_at] is its own time when it sent this report
    phone_now = _parse(sent_at)
    skew = (now - phone_now) if phone_now is not None and abs(now - phone_now) < MAX_BACKLOG else timedelta(0)
    rows = []
    for p in points[:MAX_POINTS_PER_REPORT]:
        if not isinstance(p, dict):
            raise BusinessError("invalid_location")
        rows.append(DeliveryPoint(
            order=order, driver=user, latitude=coordinate(p.get("latitude"), 90),
            longitude=coordinate(p.get("longitude"), 180), recorded_at=_when(p.get("at"), now, skew),
        ))
    if not rows:
        raise BusinessError("invalid_location")
    DeliveryPoint.objects.bulk_create(rows)
    latest = max(rows, key=lambda r: r.recorded_at)
    if order.driver_location_at is None or latest.recorded_at >= order.driver_location_at:
        Order.objects.filter(pk=order.pk).update(
            driver_latitude=latest.latitude, driver_longitude=latest.longitude, driver_location_at=latest.recorded_at
        )
    return True


def route(order, limit=600):
    """The driver's route for this order as [[lat, lng], ...], thinned to at most [limit] points."""
    pts = list(order.delivery_points.values_list("latitude", "longitude"))
    if len(pts) > limit:
        step = len(pts) / limit
        pts = [pts[int(i * step)] for i in range(limit - 1)] + [pts[-1]]
    return [[float(a), float(b)] for a, b in pts]


def eligible_drivers(order):
    """Who may deliver [order]: a distributor's order goes to that distributor or their drivers; the
    store's own orders to the store's drivers or employees."""
    from apps.accounts.models import User

    active = User.objects.filter(is_active=True, is_staff=True)
    if order.distributor_id:
        return active.filter(models.Q(pk=order.distributor_id) | models.Q(is_driver=True, works_for_id=order.distributor_id))
    return active.filter(is_distributor=False, is_superuser=False).filter(
        models.Q(is_driver=True, works_for__isnull=True) | models.Q(is_driver=False)
    ) | active.filter(is_superuser=True)


def hand_to(order, user, driver):
    """[user] hands [order] to [driver] for delivery. Raises BusinessError if that driver can't take it."""
    if driver.pk != user.pk and not eligible_drivers(order).filter(pk=driver.pk).exists():
        raise BusinessError("driver_not_allowed")
    changed = order.driver_id != driver.pk
    assign_driver(order, driver)
    return changed
