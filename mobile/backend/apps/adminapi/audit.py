"""Activity log of the admin app: who changed what, and when (owner-only screen).

AuditMiddleware records every successful change request to /api/v1/admin/; sign-ins are
recorded by the login view. Passwords, tokens and codes are never stored.
"""

import json
import logging

from .models import AuditLog

log = logging.getLogger(__name__)

PREFIX = "/api/v1/admin/"
WRITE = {"POST", "PUT", "PATCH", "DELETE"}
SECRET = {"password", "new_password", "current_password", "access_token", "code", "id_token", "refresh", "token"}
SKIP = {"admin-inbox-seen", "admin-notification-audience"}  # reading, not changing

# url name -> {method: (Arabic, English)}; "*" = any change method
ACTIONS = {
    "admin-order-status": {"*": ("تغيير حالة طلب", "Order status changed")},
    "admin-order-payment": {"*": ("تسجيل دفعة على طلب", "Payment recorded on order")},
    "admin-order-note": {"*": ("تعديل ملاحظة طلب", "Order note edited")},
    "admin-customer-payments": {"*": ("تسجيل دفعة لزبون", "Customer payment recorded")},
    "admin-customer-adjustments": {"*": ("تصحيح كشف حساب", "Account correction")},
    "admin-customer-detail": {"*": ("تعديل بيانات زبون", "Customer updated")},
    "admin-product-list": {"POST": ("إضافة منتج", "Product added")},
    "admin-product-detail": {"DELETE": ("حذف منتج", "Product deleted"), "*": ("تعديل منتج", "Product edited")},
    "admin-product-upload-images": {"*": ("رفع صورة منتج", "Product image uploaded")},
    "admin-category-image": {"*": ("تغيير صورة فئة", "Category image changed")},
    "admin-banner-image": {"*": ("تغيير صورة بانر", "Banner image changed")},
    "admin-product-delete-image": {"*": ("حذف صورة منتج", "Product image deleted")},
    "admin-product-reorder-images": {"*": ("ترتيب صور منتج", "Product images reordered")},
    "admin-category-list": {"POST": ("إضافة فئة", "Category added")},
    "admin-category-detail": {"DELETE": ("حذف فئة", "Category deleted"), "*": ("تعديل فئة", "Category edited")},
    "admin-coupon-list": {"POST": ("إضافة كوبون", "Coupon added")},
    "admin-coupon-detail": {"DELETE": ("حذف كوبون", "Coupon deleted"), "*": ("تعديل كوبون", "Coupon edited")},
    "admin-banner-list": {"POST": ("إضافة بانر", "Banner added")},
    "admin-banner-detail": {"DELETE": ("حذف بانر", "Banner deleted"), "*": ("تعديل بانر", "Banner edited")},
    "admin-zone-list": {"POST": ("إضافة منطقة توصيل", "Delivery zone added")},
    "admin-zone-detail": {"DELETE": ("حذف منطقة توصيل", "Delivery zone deleted"), "*": ("تعديل منطقة توصيل", "Delivery zone edited")},
    "admin-legal-detail": {"*": ("تعديل صفحة سياسات", "Policy page edited")},
    "admin-notification-list": {"POST": ("إرسال إشعار للزبائن", "Notification sent to customers")},
    "admin-staff-list": {"POST": ("إضافة موظف", "Employee added")},
    "admin-staff-detail": {"*": ("تعديل حساب موظف", "Employee account changed")},
}
PATH_ACTIONS = {
    "settings/": ("تعديل إعدادات المتجر", "Store settings changed"),
    "whatsapp/": ("تعديل إعدادات واتساب", "WhatsApp settings changed"),
    "whatsapp/link/": ("ربط/فصل رقم واتساب", "WhatsApp number linked/unlinked"),
}


def _ip(request):
    return (request.META.get("HTTP_X_FORWARDED_FOR", "").split(",")[0].strip() or request.META.get("REMOTE_ADDR")) or None


def _clean(data):
    if isinstance(data, dict):
        return {k: ("***" if k in SECRET else _clean(v)) for k, v in data.items()}
    if isinstance(data, list):
        return [_clean(v) for v in data[:30]]
    if isinstance(data, str) and len(data) > 300:
        return data[:300] + "…"
    return data


def _target(url_name, pk):
    """A readable name for the thing that was changed (order number, product, customer…)."""
    if not pk:
        return ""
    try:
        if url_name.startswith("admin-order"):
            from apps.orders.models import Order

            return Order.objects.filter(pk=pk).values_list("number", flat=True).first() or f"#{pk}"
        if url_name.startswith(("admin-customer", "admin-staff")):
            from apps.accounts.models import User

            u = User.objects.filter(pk=pk).first()
            return (u.business_name or u.display_name) if u else f"#{pk}"
        if url_name.startswith("admin-product"):
            from apps.catalog.models import Product

            return Product.objects.filter(pk=pk).values_list("name_ar", flat=True).first() or f"#{pk}"
        if url_name.startswith("admin-category"):
            from apps.catalog.models import Category

            return Category.objects.filter(pk=pk).values_list("name_ar", flat=True).first() or f"#{pk}"
    except Exception:  # never break the request because of the log
        log.exception("audit target")
    return f"#{pk}"


def record(request, actor, action, target="", details=None):
    AuditLog.objects.create(
        actor=actor if actor and actor.is_authenticated else None,
        actor_name=actor.display_name if actor and actor.is_authenticated else "",
        action_ar=action[0], action_en=action[1], target=target[:200], details=details or {},
        method=request.method, path=request.path[:200], ip=_ip(request),
    )


class AuditMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        body = None
        if request.method in WRITE and request.path.startswith(PREFIX):
            # Read the JSON body now (cached for the view); uploads are not stored
            if request.content_type == "application/json" and int(request.META.get("CONTENT_LENGTH") or 0) < 50_000:
                try:
                    body = json.loads(request.body or b"{}")
                except ValueError:
                    body = None
        response = self.get_response(request)
        try:
            self._log(request, response, body)
        except Exception:
            log.exception("audit log failed")
        return response

    def _log(self, request, response, body):
        if request.method not in WRITE or not request.path.startswith(PREFIX) or response.status_code >= 400:
            return
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated and user.is_staff):
            return  # sign-ins are logged by the login view
        match = getattr(request, "resolver_match", None)
        name = match.url_name if match else ""
        if name in SKIP:
            return
        rel = request.path[len(PREFIX):]
        action = None
        if name in ACTIONS:
            options = ACTIONS[name]
            action = options.get(request.method) or options.get("*")
        if action is None:
            action = PATH_ACTIONS.get(rel) or (f"{request.method} {rel}", f"{request.method} {rel}")
        pk = match.kwargs.get("pk") if match else None
        record(request, user, action, _target(name, pk), _clean(body) if isinstance(body, (dict, list)) else {})
