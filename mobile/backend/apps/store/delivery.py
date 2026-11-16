"""Delivery zones (fixed fee per zone) and the areas that belong to each zone."""

from decimal import Decimal

from django.db import models


class DeliveryZone(models.Model):
    name_ar = models.CharField(max_length=100)
    name_en = models.CharField(max_length=100)
    fee = models.DecimalField(max_digits=10, decimal_places=2, default=Decimal("0"))
    is_default_for_unlisted = models.BooleanField(
        default=False, help_text="Fee used when the customer's area is not in any list"
    )
    sort_order = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)

    class Meta:
        app_label = "store"
        ordering = ["sort_order", "id"]

    def __str__(self):
        return self.name_en


class DeliveryArea(models.Model):
    zone = models.ForeignKey(DeliveryZone, on_delete=models.CASCADE, related_name="areas")
    name_ar = models.CharField(max_length=100)
    name_en = models.CharField(max_length=100, blank=True)
    sort_order = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)

    class Meta:
        app_label = "store"
        ordering = ["zone__sort_order", "sort_order", "name_ar"]

    def __str__(self):
        return self.name_ar


def fee_for_area(area_id):
    """Return (zone, area, fee). Unknown/unlisted area → the 'unlisted' zone."""
    area = DeliveryArea.objects.select_related("zone").filter(pk=area_id, is_active=True, zone__is_active=True).first() if area_id else None
    if area:
        return area.zone, area, area.zone.fee
    zone = DeliveryZone.objects.filter(is_active=True, is_default_for_unlisted=True).first() or DeliveryZone.objects.filter(is_active=True).order_by("-fee").first()
    return zone, None, (zone.fee if zone else Decimal("0"))
