from django.conf import settings
from django.db import models


class DeviceToken(models.Model):
    STORE, ADMIN = "store", "admin"

    token = models.CharField(max_length=512, unique=True)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, null=True, blank=True, related_name="device_tokens")
    app = models.CharField(max_length=10, choices=[(STORE, "Store"), (ADMIN, "Admin")], default=STORE)
    platform = models.CharField(max_length=10, default="android")
    language = models.CharField(max_length=2, default="ar")
    updated_at = models.DateTimeField(auto_now=True)


class Notification(models.Model):
    """In-app inbox entry. user=None means a broadcast to all customers."""

    KINDS = [("order", "Order"), ("account", "Account"), ("offer", "Offer"), ("general", "General")]

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, null=True, blank=True, related_name="notifications")
    kind = models.CharField(max_length=10, choices=KINDS, default="general")
    title_ar = models.CharField(max_length=150)
    title_en = models.CharField(max_length=150)
    body_ar = models.CharField(max_length=500, blank=True)
    body_en = models.CharField(max_length=500, blank=True)
    data = models.JSONField(default=dict, blank=True)
    # For admin campaigns (user=None): {} = all customers, else the targeting used.
    # Targeted campaigns also create one personal copy per matching customer.
    audience = models.JSONField(default=dict, blank=True)
    sent_count = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["-created_at"]


class AdminNotification(models.Model):
    """Team inbox for the admin app: every alert pushed to staff is kept here."""

    title_ar = models.CharField(max_length=150)
    title_en = models.CharField(max_length=150)
    body_ar = models.CharField(max_length=500, blank=True)
    body_en = models.CharField(max_length=500, blank=True)
    data = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["-created_at", "-id"]
