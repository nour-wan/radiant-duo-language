"""Business events → inbox entries, push notifications and admin emails."""

import logging

from django.conf import settings
from django.core.mail import send_mail

from . import fcm
from .models import AdminNotification, DeviceToken, Notification

log = logging.getLogger(__name__)

STATUS_TEXT = {
    "pending": ("تم استلام طلبك", "Order received"),
    "confirmed": ("تم تأكيد طلبك", "Order confirmed"),
    "shipped": ("طلبك في الطريق", "Order on the way"),
    "delivered": ("تم تسليم طلبك", "Order delivered"),
    "cancelled": ("تم إلغاء طلبك", "Order cancelled"),
}
PICKUP_STATUS_TEXT = {
    "shipped": ("طلبك جاهز للاستلام من المحل", "Your order is ready for pickup"),
    "delivered": ("تم استلام طلبك", "Order picked up"),
}


def _push(tokens, n):
    fcm.send_localized_async(
        tokens,
        {"ar": (n.title_ar, n.body_ar), "en": (n.title_en, n.body_en)},
        {**n.data, "notification_id": n.id, "kind": n.kind},
        notification_id=n.id,
    )


def notify_user(user, kind, title_ar, title_en, body_ar="", body_en="", data=None):
    n = Notification.objects.create(
        user=user, kind=kind, title_ar=title_ar, title_en=title_en, body_ar=body_ar, body_en=body_en, data=data or {}
    )
    _push(list(DeviceToken.objects.filter(user=user, app=DeviceToken.STORE)), n)
    return n


def target_customers(audience):
    from django.contrib.auth import get_user_model

    qs = get_user_model().objects.filter(is_staff=False, is_active=True)
    if audience.get("interests"):
        qs = qs.filter(interests__id__in=audience["interests"])
    if audience.get("business_types"):
        qs = qs.filter(business_type__in=audience["business_types"])
    if audience.get("zones"):
        qs = qs.filter(delivery_area__zone_id__in=audience["zones"])
    return qs.distinct()


def broadcast(title_ar, title_en, body_ar="", body_en="", kind="offer", data=None, audience=None):
    """Send to all customers (audience empty) or only to matching customers."""
    audience = {k: v for k, v in (audience or {}).items() if v}
    texts = dict(kind=kind, title_ar=title_ar, title_en=title_en, body_ar=body_ar, body_en=body_en, data=data or {})
    campaign = Notification.objects.create(user=None, audience=audience, **texts)
    if not audience:
        _push(list(DeviceToken.objects.filter(app=DeviceToken.STORE)), campaign)
        return campaign
    users = list(target_customers(audience))
    Notification.objects.bulk_create([Notification(user=u, **texts) for u in users])
    tokens = list(DeviceToken.objects.filter(app=DeviceToken.STORE, user__in=users))
    fcm.send_localized_async(
        tokens,
        {"ar": (title_ar, body_ar), "en": (title_en, body_en)},
        {**(data or {}), "notification_id": campaign.id, "kind": kind},
        notification_id=campaign.id,
    )
    campaign.audience = {**audience, "customer_count": len(users)}
    campaign.save(update_fields=["audience"])
    return campaign


def _notify_admins(title_ar, title_en, body_ar, body_en, data):
    # Kept in the admin inbox too, so a dismissed push can still be found in the app.
    data = {"kind": "admin_order", **data}
    n = AdminNotification.objects.create(title_ar=title_ar, title_en=title_en, body_ar=body_ar, body_en=body_en, data=data)
    tokens = list(DeviceToken.objects.filter(app=DeviceToken.ADMIN, user__is_staff=True, user__is_active=True))
    fcm.send_localized_async(
        tokens, {"ar": (title_ar, body_ar), "en": (title_en, body_en)}, {**data, "admin_notification_id": n.id}
    )


def order_placed(order):
    t_ar, t_en = STATUS_TEXT["pending"]
    data = {"order_id": order.id, "number": order.number}
    notify_user(
        order.user, "order", t_ar, t_en,
        f"طلبك رقم {order.number} قيد المراجعة، وسنتواصل معك قريباً.",
        f"Your order {order.number} is being reviewed. We will contact you soon.",
        data,
    )
    who = order.business_name or order.customer_name
    _notify_admins(
        "طلب جديد 🛒", "New order 🛒",
        f"{order.number} — {who} — ${order.total}",
        f"{order.number} — {who} — ${order.total}",
        data,
    )
    try:
        lines = "\n".join(f"- {i.product_name_ar} / {i.variant_label_ar} × {i.quantity} = ${i.line_total}" for i in order.items.all())
        send_mail(
            f"طلب جديد {order.number} — ${order.total}",
            f"العميل: {order.customer_name}\nالمنشأة: {order.business_name or '-'}\nالهاتف: {order.customer_phone}\n"
            f"الاستلام: {'توصيل' if order.delivery_method == 'delivery' else 'استلام من المحل'}"
            f" — {order.area} {order.street} {order.address_details}\nملاحظات: {order.notes or '-'}\n\n{lines}\n\n"
            f"المجموع: ${order.subtotal}\nخصم الكوبون: ${order.discount}\nخصم التطبيق: ${order.app_discount}\n"
            f"الإجمالي: ${order.total}\nالتوصيل: {order.delivery_fee} {order.delivery_currency}",
            settings.DEFAULT_FROM_EMAIL,
            [settings.ADMIN_NOTIFY_EMAIL],
            fail_silently=True,
        )
    except Exception:
        log.exception("Could not email new order")


def order_status_changed(order, note=""):
    if not order.user_id:
        return
    t_ar, t_en = (PICKUP_STATUS_TEXT if order.delivery_method == "pickup" else {}).get(order.status) or STATUS_TEXT.get(
        order.status, ("تحديث على طلبك", "Order update")
    )
    # The admin's optional message to the customer is shown in the notification and the order timeline.
    body_ar, body_en = f"طلب رقم {order.number}", f"Order {order.number}"
    if note:
        body_ar, body_en = f"{body_ar}: {note}", f"{body_en}: {note}"
    notify_user(
        order.user, "order", t_ar, t_en,
        body_ar, body_en,
        {"order_id": order.id, "number": order.number, "status": order.status},
    )


def order_cancelled_by_customer(order):
    _notify_admins(
        "ألغى عميل طلبه", "Customer cancelled an order",
        order.number, order.number, {"order_id": order.id, "number": order.number},
    )


def payment_recorded(entry, balance):
    """Tell the customer a payment was received and what is left on the account."""
    if not entry.user_id:
        return
    paid = -entry.amount
    if balance > 0:
        rest_ar, rest_en = f"المتبقي عليك: ${balance}", f"Remaining balance: ${balance}"
    elif balance < 0:
        rest_ar, rest_en = f"رصيدك لدينا: ${-balance}", f"Your credit with us: ${-balance}"
    else:
        rest_ar, rest_en = "حسابك مسدد بالكامل، شكراً لك", "Your account is fully paid. Thank you"
    notify_user(
        entry.user, "account", "تم استلام دفعة", "Payment received",
        f"استلمنا منك ${paid}. {rest_ar}", f"We received ${paid}. {rest_en}",
        {"screen": "statement"},
    )


def account_adjusted(entry, balance):
    if not entry.user_id:
        return
    notify_user(
        entry.user, "account", "تحديث على كشف حسابك", "Account statement updated",
        f"{entry.note} — الرصيد الحالي: ${balance}", f"{entry.note} — Current balance: ${balance}",
        {"screen": "statement"},
    )


PHONE_CODE_PURPOSE = {
    "register": ("حساب جديد", "New account"),
    "reset": ("استعادة كلمة السر", "Password reset"),
    "change": ("تغيير رقم الهاتف", "Phone change"),
}


def phone_code_for_admin(phone, code, purpose, whatsapp_link):
    """No automatic WhatsApp sender yet: an admin forwards the code (tap opens WhatsApp ready to send)."""
    p_ar, p_en = PHONE_CODE_PURPOSE.get(purpose, ("تحقق", "Verification"))
    _notify_admins(
        f"أرسل رمز التحقق للزبون 🔑 ({p_ar})", f"Send the verification code 🔑 ({p_en})",
        f"{phone} — الرمز: {code} — اضغط لإرساله على واتساب",
        f"{phone} — code: {code} — tap to send it on WhatsApp",
        {"kind": "phone_code", "phone": phone, "whatsapp_link": whatsapp_link},
    )
