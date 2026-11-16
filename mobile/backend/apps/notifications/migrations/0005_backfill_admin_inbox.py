from datetime import timedelta

from django.db import migrations
from django.utils import timezone


def backfill(apps, schema_editor):
    """Fill the new admin inbox with the last 30 days of orders, so earlier alerts can still be found."""
    Order = apps.get_model("orders", "Order")
    AdminNotification = apps.get_model("notifications", "AdminNotification")
    if AdminNotification.objects.exists():
        return
    since = timezone.now() - timedelta(days=30)
    for order in Order.objects.filter(created_at__gte=since).order_by("created_at"):
        who = order.business_name or order.customer_name
        text = f"{order.number} — {who} — ${order.total}"
        n = AdminNotification.objects.create(
            title_ar="طلب جديد 🛒", title_en="New order 🛒", body_ar=text, body_en=text,
            data={"order_id": order.id, "number": order.number, "kind": "admin_order"},
        )
        AdminNotification.objects.filter(pk=n.pk).update(created_at=order.created_at)


class Migration(migrations.Migration):
    dependencies = [
        ("notifications", "0004_adminnotification"),
        ("orders", "0002_order_app_discount_order_app_discount_percent_and_more"),
    ]

    operations = [migrations.RunPython(backfill, migrations.RunPython.noop)]
