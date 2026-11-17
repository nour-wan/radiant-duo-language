from django.conf import settings
from django.db import models


class Order(models.Model):
    PENDING, CONFIRMED, SHIPPED, DELIVERED, CANCELLED = "pending", "confirmed", "shipped", "delivered", "cancelled"
    STATUSES = [
        (PENDING, "Pending"),
        (CONFIRMED, "Confirmed"),
        (SHIPPED, "Shipped"),
        (DELIVERED, "Delivered"),
        (CANCELLED, "Cancelled"),
    ]
    TRANSITIONS = {
        PENDING: {CONFIRMED, CANCELLED},
        CONFIRMED: {SHIPPED, CANCELLED},
        SHIPPED: {DELIVERED, CANCELLED},
        DELIVERED: set(),
        CANCELLED: set(),
    }

    number = models.CharField(max_length=20, unique=True, blank=True)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name="orders")
    client_ref = models.CharField(max_length=64, blank=True)
    status = models.CharField(max_length=12, choices=STATUSES, default=PENDING, db_index=True)

    # Snapshot of customer & delivery details (cleared if the customer deletes the account)
    customer_name = models.CharField(max_length=150)
    customer_phone = models.CharField(max_length=32)
    customer_email = models.EmailField(blank=True)
    business_name = models.CharField(max_length=150, blank=True)
    city = models.CharField(max_length=80)
    area = models.CharField(max_length=120, blank=True)
    street = models.CharField(max_length=200, blank=True)
    address_details = models.CharField(max_length=300, blank=True)
    notes = models.CharField(max_length=500, blank=True)
    customer_deleted = models.BooleanField(default=False)

    PICKUP, DELIVERY = "pickup", "delivery"
    DELIVERY_METHODS = [(PICKUP, "Pickup from store"), (DELIVERY, "Delivery")]

    payment_method = models.CharField(max_length=10, default="cod")
    delivery_method = models.CharField(max_length=10, choices=DELIVERY_METHODS, default=DELIVERY)
    # Customer's prepaid credit (money they had with us) used for this order, fixed at delivery
    credit_applied = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    delivery_zone = models.CharField(max_length=100, blank=True)
    delivery_fee = models.DecimalField(max_digits=10, decimal_places=2, default=0)  # in the delivery currency (SYP)
    delivery_currency = models.CharField(max_length=20, blank=True)
    coupon_code = models.CharField(max_length=40, blank=True)
    subtotal = models.DecimalField(max_digits=12, decimal_places=2)
    discount = models.DecimalField(max_digits=12, decimal_places=2, default=0)  # coupon discount
    app_discount_percent = models.DecimalField(max_digits=5, decimal_places=2, default=0)
    app_discount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    total = models.DecimalField(max_digits=12, decimal_places=2)  # SYP, products only (delivery fee separate)
    # Amounts above are in Syrian pounds. The USD → SYP rate the order was priced with, and the
    # same total in dollars (for the store's own reports; never shown to customers).
    currency = models.CharField(max_length=3, default="SYP")
    exchange_rate = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    total_usd = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    admin_note = models.CharField(max_length=500, blank=True)

    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["user", "client_ref"], condition=~models.Q(client_ref=""), name="unique_order_client_ref"
            )
        ]

    def __str__(self):
        return self.number

    def save(self, *args, **kwargs):
        super().save(*args, **kwargs)
        if not self.number:
            self.number = f"ALS-{self.created_at:%y}{self.pk:05d}"
            super().save(update_fields=["number"])

    def can_move_to(self, status):
        return status in self.TRANSITIONS.get(self.status, set())


class OrderItem(models.Model):
    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name="items")
    product = models.ForeignKey("catalog.Product", on_delete=models.SET_NULL, null=True, related_name="+")
    variant = models.ForeignKey("catalog.Variant", on_delete=models.SET_NULL, null=True, related_name="+")
    product_name_ar = models.CharField(max_length=160)
    product_name_en = models.CharField(max_length=160)
    variant_label_ar = models.CharField(max_length=80)
    variant_label_en = models.CharField(max_length=80)
    image = models.CharField(max_length=300, blank=True)
    unit_price = models.DecimalField(max_digits=12, decimal_places=2)  # SYP
    unit_price_usd = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    quantity = models.PositiveIntegerField()
    line_total = models.DecimalField(max_digits=12, decimal_places=2)


class OrderEvent(models.Model):
    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name="events")
    status = models.CharField(max_length=12, choices=Order.STATUSES)
    note = models.CharField(max_length=500, blank=True)
    by_admin = models.BooleanField(default=False)
    # The staff member who made the change (kept if the account is later disabled)
    by = models.ForeignKey("accounts.User", on_delete=models.SET_NULL, null=True, blank=True, related_name="+")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created_at", "id"]
