from decimal import ROUND_HALF_UP, Decimal

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models
from django.utils import timezone


class Coupon(models.Model):
    PERCENT, FIXED = "percent", "fixed"
    KINDS = [(PERCENT, "Percentage"), (FIXED, "Fixed amount")]

    code = models.CharField(max_length=40, unique=True)
    kind = models.CharField(max_length=10, choices=KINDS, default=PERCENT)
    value = models.DecimalField(max_digits=10, decimal_places=2, validators=[MinValueValidator(Decimal("0.01"))])
    min_order_total = models.DecimalField(max_digits=10, decimal_places=2, default=Decimal("0"))
    max_discount = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    max_uses = models.PositiveIntegerField(null=True, blank=True)
    max_uses_per_user = models.PositiveIntegerField(null=True, blank=True, default=1)
    used_count = models.PositiveIntegerField(default=0)
    starts_at = models.DateTimeField(null=True, blank=True)
    expires_at = models.DateTimeField(null=True, blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def save(self, *args, **kwargs):
        self.code = self.code.strip().upper()
        super().save(*args, **kwargs)

    def problem_for(self, user, subtotal):
        """Return an error code if the coupon can't be used now, else None."""
        now = timezone.now()
        if not self.is_active:
            return "coupon_inactive"
        if self.starts_at and now < self.starts_at:
            return "coupon_not_started"
        if self.expires_at and now > self.expires_at:
            return "coupon_expired"
        if self.max_uses is not None and self.used_count >= self.max_uses:
            return "coupon_used_up"
        if user is not None and self.max_uses_per_user is not None:
            if self.redemptions.filter(user=user).count() >= self.max_uses_per_user:
                return "coupon_already_used"
        if subtotal < self.min_order_total:
            return "coupon_min_total"
        return None

    def discount_for(self, subtotal):
        if self.kind == self.PERCENT:
            amount = subtotal * min(self.value, Decimal("100")) / Decimal("100")
        else:
            amount = self.value
        if self.max_discount is not None:
            amount = min(amount, self.max_discount)
        return min(amount, subtotal).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


class CouponRedemption(models.Model):
    coupon = models.ForeignKey(Coupon, on_delete=models.CASCADE, related_name="redemptions")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name="+")
    order = models.OneToOneField("orders.Order", on_delete=models.CASCADE, related_name="coupon_redemption")
    created_at = models.DateTimeField(auto_now_add=True)


class Banner(models.Model):
    LINKS = [("none", "None"), ("product", "Product"), ("category", "Category"), ("url", "External URL")]

    image = models.ImageField(upload_to="banners/")
    title_ar = models.CharField(max_length=120, blank=True)
    title_en = models.CharField(max_length=120, blank=True)
    subtitle_ar = models.CharField(max_length=200, blank=True)
    subtitle_en = models.CharField(max_length=200, blank=True)
    link_type = models.CharField(max_length=10, choices=LINKS, default="none")
    link_value = models.CharField(max_length=300, blank=True)
    sort_order = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)
    starts_at = models.DateTimeField(null=True, blank=True)
    ends_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["sort_order", "id"]
