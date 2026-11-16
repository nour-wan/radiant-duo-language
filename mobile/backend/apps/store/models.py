from django.core.validators import MinValueValidator
from decimal import Decimal

from django.db import models

from .delivery import DeliveryArea, DeliveryZone  # noqa: F401  (registers the models)


class StoreSettings(models.Model):
    """Single row of store-wide settings, editable from the admin app."""

    name_ar = models.CharField(max_length=120, default="آلاس لتجارة المواد الغذائية")
    name_en = models.CharField(max_length=120, default="Alas for Foodstuff Trading")
    about_ar = models.TextField(blank=True)
    about_en = models.TextField(blank=True)
    phone = models.CharField(max_length=32, default="0113333275", blank=True)
    mobile = models.CharField(max_length=32, default="0965747889", blank=True)
    whatsapp = models.CharField(max_length=32, default="+963965747889", blank=True)
    email = models.EmailField(default="info@alasfoodstuff.com", blank=True)
    website = models.URLField(default="https://alasfoodstuff.com", blank=True)
    address_ar = models.CharField(max_length=300, blank=True)
    address_en = models.CharField(max_length=300, blank=True)
    working_hours_ar = models.CharField(max_length=200, blank=True)
    working_hours_en = models.CharField(max_length=200, blank=True)
    facebook = models.URLField(blank=True)
    instagram = models.URLField(blank=True)
    telegram = models.URLField(blank=True)
    orders_enabled = models.BooleanField(default=True)
    min_order_total = models.DecimalField(max_digits=10, decimal_places=2, default=Decimal("0"))
    low_stock_threshold = models.PositiveIntegerField(default=10)
    # Discount given only to orders placed through the app (not phone orders)
    app_discount_enabled = models.BooleanField(default=True)
    app_discount_percent = models.DecimalField(max_digits=5, decimal_places=2, default=Decimal("2"))
    # Delivery: customer pickup and/or delivery with a fixed fee per zone
    pickup_enabled = models.BooleanField(default=True)
    pickup_address_ar = models.CharField(max_length=300, default="دمشق - الشعلان", blank=True)
    pickup_address_en = models.CharField(max_length=300, default="Damascus - Al-Shaalan", blank=True)
    delivery_enabled = models.BooleanField(default=True)
    delivery_currency_ar = models.CharField(max_length=20, default="ل.س")
    delivery_currency_en = models.CharField(max_length=20, default="SYP")
    # Max unpaid amount (USD) per customer; empty = no limit
    default_credit_limit = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True, validators=[MinValueValidator(Decimal("0"))])
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name_plural = "store settings"

    def save(self, *args, **kwargs):
        self.pk = 1
        super().save(*args, **kwargs)

    @classmethod
    def load(cls):
        obj, _ = cls.objects.get_or_create(pk=1)
        return obj


class LegalPage(models.Model):
    SLUGS = [
        ("privacy", "Privacy policy"),
        ("terms", "Terms & conditions"),
        ("returns", "Return & refund policy"),
        ("account-deletion", "Account deletion"),
    ]
    slug = models.SlugField(max_length=40, unique=True, choices=SLUGS)
    title_ar = models.CharField(max_length=150)
    title_en = models.CharField(max_length=150)
    body_ar = models.TextField()
    body_en = models.TextField()
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["id"]
