import json
from datetime import date, datetime, time, timedelta
from decimal import Decimal

from django.db import transaction
from django.db.models import Count, DecimalField, Max, OuterRef, Q, Subquery, Sum, Value
from django.db.models.functions import Coalesce
from django.db.models.functions import TruncDay, TruncMonth, TruncWeek
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import User
from apps.catalog.models import Category, Product, ProductImage, Variant
from apps.catalog.serializers import ImageSerializer
from apps.core.errors import BusinessError
from apps.core.images import process_upload
from apps.core.pagination import Pagination
from apps.core.permissions import (
    DISTRIBUTOR_READ, DISTRIBUTOR_SCOPED, IsOwner, IsStoreAdmin, is_distributor, is_driver, scope_customers, scope_orders,
)
from apps.ledger import services as ledger
from apps.ledger.models import LedgerEntry
from apps.ledger.serializers import AdjustmentSerializer, AdminLedgerEntrySerializer, PaymentSerializer
from apps.ledger.views import statement_response
from apps.notifications import events
from apps.notifications.models import AdminNotification, Notification
from apps.orders import pricing, tracking
from apps.orders.invoice import invoice_response
from apps.orders.models import Order, OrderItem
from apps.promotions.models import Banner, Coupon
from apps.store import fx
from apps.store.delivery import DeliveryZone
from apps.store.models import LegalPage, StoreSettings

from . import export as x
from . import serializers as s

SALE_STATUSES = [Order.PENDING, Order.CONFIRMED, Order.SHIPPED, Order.DELIVERED]


class AdminMixin:
    permission_classes = [IsStoreAdmin]


class OwnerMixin:
    """Only the store owner: employees, store settings, WhatsApp, credit, corrections, cash report."""

    permission_classes = [IsOwner]


def _end_sessions(user):
    """Signs the account out everywhere and stops its push notifications."""
    from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken, OutstandingToken

    from apps.notifications.models import DeviceToken

    for token in OutstandingToken.objects.filter(user=user):
        BlacklistedToken.objects.get_or_create(token=token)
    DeviceToken.objects.filter(user=user).delete()


def _scoped_receivables(user):
    """(customer id, balance) rows for the customers this account may see."""
    rows = ledger.receivables()
    if user.is_superuser:
        return rows
    allowed = set(scope_customers(User.objects.filter(is_staff=False), user).values_list("id", flat=True))
    return [(uid, b) for uid, b in rows if uid in allowed]


def _local_day_start(day):
    return timezone.make_aware(datetime.combine(day, time.min))


class DashboardView(AdminMixin, APIView):
    distributor_access = DISTRIBUTOR_SCOPED

    def get(self, request):
        now = timezone.localtime()
        today = _local_day_start(now.date())
        month = _local_day_start(now.date().replace(day=1))
        user = request.user
        orders = scope_orders(Order.objects.all(), user)
        sales = orders.filter(status__in=SALE_STATUSES)
        customers = scope_customers(User.objects.filter(is_staff=False), user)

        def summary(since):
            agg = sales.filter(created_at__gte=since).aggregate(total=Sum("total"), usd=Sum("total_usd"), count=Count("id"))
            return {"sales": str(agg["total"] or 0), "sales_usd": str(agg["usd"] or 0), "orders": agg["count"]}

        start = today - timedelta(days=13)
        daily = {
            row["day"].date(): row
            for row in sales.filter(created_at__gte=start)
            .annotate(day=TruncDay("created_at"))
            .values("day")
            .annotate(total=Sum("total"), count=Count("id"))
        }
        chart = []
        for i in range(14):
            d = (start + timedelta(days=i)).date()
            row = daily.get(d)
            chart.append({"date": d.isoformat(), "sales": str(row["total"] if row else 0), "orders": row["count"] if row else 0})

        best = (
            OrderItem.objects.filter(order__in=sales, order__created_at__gte=today - timedelta(days=30))
            .values("product_id", "product_name_ar", "product_name_en")
            .annotate(quantity=Sum("quantity"), revenue=Sum("line_total"))
            .order_by("-quantity")[:5]
        )
        threshold = StoreSettings.load().low_stock_threshold
        low = Variant.objects.filter(is_active=True, product__is_active=True, stock__lte=threshold).select_related("product").order_by("stock")[:20]
        return Response(
            {
                "today": summary(today),
                "month": summary(month),
                "pending_orders": orders.filter(status=Order.PENDING).count(),
                "customers": customers.count(),
                "products": Product.objects.filter(is_active=True).count(),
                "chart": chart,
                "best_sellers": [{**b, "revenue": str(b["revenue"])} for b in best],
                "low_stock": [
                    {
                        "product_id": v.product_id, "variant_id": v.id, "product_name_ar": v.product.name_ar,
                        "product_name_en": v.product.name_en, "label_ar": v.label_ar, "label_en": v.label_en, "stock": v.stock,
                    }
                    for v in low
                ],
                "low_stock_threshold": threshold,
                "unread_inbox": _unread_inbox(request.user).count(),
                "receivables_total": str(sum((b for _, b in _scoped_receivables(user) if b > 0), ledger.ZERO)),
                "exchange_rate": fx.status(),
            }
        )


class ImageUploadMixin:
    """POST multipart 'image' to <obj>/image/ to set the object's single image."""

    @action(detail=True, methods=["post", "delete"], parser_classes=[MultiPartParser, FormParser])
    def image(self, request, pk=None):
        obj = self.get_object()
        if obj.image:
            obj.image.delete(save=False)
        if request.method == "POST":
            main, _thumb = process_upload(request.FILES.get("image") or self._missing())
            obj.image.save(main.name, main, save=True)
        else:
            obj.save()
        return Response(self.get_serializer(obj).data)

    def _missing(self):
        raise BusinessError("image_required")


class CategoryViewSet(AdminMixin, ImageUploadMixin, viewsets.ModelViewSet):
    distributor_access = DISTRIBUTOR_READ  # distributors see products and stock, never change them

    serializer_class = s.AdminCategorySerializer
    pagination_class = None

    def get_queryset(self):
        return Category.objects.annotate(product_count=Count("products"))

    def perform_destroy(self, instance):
        if instance.products.exists():
            raise BusinessError("category_has_products")
        instance.delete()


class ProductViewSet(AdminMixin, viewsets.ModelViewSet):
    distributor_access = DISTRIBUTOR_READ  # distributors see products and stock, never change them

    serializer_class = s.AdminProductSerializer
    parser_classes = [JSONParser, MultiPartParser, FormParser]

    def get_queryset(self):
        qs = Product.objects.select_related("category").prefetch_related("variants", "images")
        p = self.request.query_params
        if p.get("q"):
            qs = qs.filter(Q(name_ar__icontains=p["q"]) | Q(name_en__icontains=p["q"]) | Q(variants__sku__icontains=p["q"])).distinct()
        if p.get("category"):
            qs = qs.filter(category_id=p["category"])
        if p.get("active") in ("0", "1"):
            qs = qs.filter(is_active=p["active"] == "1")
        if p.get("low_stock") == "1":
            qs = qs.filter(variants__stock__lte=StoreSettings.load().low_stock_threshold).distinct()
        return qs.order_by("-updated_at", "-id")

    def perform_destroy(self, instance):
        for img in instance.images.all():
            img.delete()
        instance.delete()

    @action(detail=True, methods=["post"], url_path="images", parser_classes=[MultiPartParser, FormParser])
    def upload_images(self, request, pk=None):
        product = self.get_object()
        files = request.FILES.getlist("images") or request.FILES.getlist("image")
        if not files:
            raise BusinessError("image_required")
        if product.images.count() + len(files) > 10:
            raise BusinessError("too_many_images")
        start = product.images.count()
        processed = [process_upload(f) for f in files]  # validate all before saving any
        for i, (main, thumb) in enumerate(processed):
            img = ProductImage(product=product, sort_order=start + i)
            img.image.save(main.name, main, save=False)
            img.thumbnail.save(thumb.name, thumb, save=False)
            img.save()
        return Response(ImageSerializer(product.images.all(), many=True).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["delete"], url_path=r"images/(?P<image_id>\d+)")
    def delete_image(self, request, pk=None, image_id=None):
        get_object_or_404(ProductImage, pk=image_id, product_id=pk).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=["post"], url_path="images/reorder")
    def reorder_images(self, request, pk=None):
        product = self.get_object()
        order = [int(i) for i in request.data.get("ids", []) if str(i).isdigit()]
        with transaction.atomic():
            for index, image_id in enumerate(order):
                ProductImage.objects.filter(pk=image_id, product=product).update(sort_order=index)
        return Response(ImageSerializer(product.images.all(), many=True).data)


class OrderViewSet(AdminMixin, mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    distributor_access = DISTRIBUTOR_SCOPED
    driver_access = True
    # A driver sees only the orders handed to them and can only deliver them (status, cash, location)
    DRIVER_ACTIONS = {"list", "retrieve", "status", "payment", "location", "invoice"}

    def initial(self, request, *args, **kwargs):
        super().initial(request, *args, **kwargs)
        if is_driver(request.user) and self.action not in self.DRIVER_ACTIONS:
            raise PermissionDenied("not_allowed")
    def get_serializer_class(self):
        return s.AdminOrderListSerializer if self.action == "list" else s.AdminOrderDetailSerializer

    @action(detail=True, methods=["get"])
    def invoice(self, request, pk=None):
        return invoice_response(self.get_object(), request)

    def get_queryset(self):
        qs = scope_orders(Order.objects.all(), self.request.user).annotate(item_count=Count("items")).select_related("driver").prefetch_related("items", "events__by").order_by("-created_at", "-id")
        p = self.request.query_params
        if p.get("status"):
            qs = qs.filter(status__in=p["status"].split(","))
        if p.get("customer"):
            qs = qs.filter(user_id=p["customer"])
        if p.get("q"):
            q = p["q"]
            qs = qs.filter(Q(number__icontains=q) | Q(customer_name__icontains=q) | Q(customer_phone__icontains=q) | Q(business_name__icontains=q))
        if p.get("from"):
            qs = qs.filter(created_at__date__gte=p["from"])
        if p.get("to"):
            qs = qs.filter(created_at__date__lte=p["to"])
        return qs

    @action(detail=True, methods=["post"])
    def status(self, request, pk=None):
        data = s.StatusChangeSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        d = data.validated_data
        note = d.get("note", "").strip()
        paid = d.get("paid_amount")
        if paid and (d["status"] != Order.DELIVERED or not self.get_object().user_id):
            raise BusinessError("payment_requires_delivered")
        if is_driver(request.user) and d["status"] != Order.DELIVERED:
            raise PermissionDenied("not_allowed")  # a driver only marks their deliveries as delivered
        driver = None
        if d.get("driver_id"):
            driver = get_object_or_404(User, pk=d["driver_id"], is_staff=True, is_active=True)
        handed = False
        with transaction.atomic():
            order = pricing.change_status(self.get_object(), d["status"], note, by=request.user)
            if order.status == Order.SHIPPED and order.delivery_method == Order.DELIVERY:
                # Out for delivery: with the chosen driver, or whoever sent it out
                handed = tracking.hand_to(order, request.user, driver or request.user) and (driver or request.user) != request.user
            entry = ledger.record_payment(order.user, paid, request.user, order=order) if paid else None
        if handed:
            transaction.on_commit(lambda: events.delivery_assigned(order))
        transaction.on_commit(lambda: events.order_status_changed(order, note))
        if entry:
            _notify_payment(entry)
        return Response(s.AdminOrderDetailSerializer(self.get_queryset().get(pk=order.pk)).data)

    @action(detail=True, methods=["post"])
    def payment(self, request, pk=None):
        """Record cash received for this order on the customer's account."""
        order = self.get_object()
        if not order.user_id:
            raise BusinessError("customer_deleted")
        data = PaymentSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        entry = ledger.record_payment(order.user, data.validated_data["amount"], request.user, order=order, note=data.validated_data["note"])
        _notify_payment(entry)
        return Response(s.AdminOrderDetailSerializer(self.get_queryset().get(pk=order.pk)).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"], url_path="take-delivery")
    def take_delivery(self, request, pk=None):
        """This staff member delivers the order from now on (another driver couldn't go)."""
        order = self.get_object()
        if not tracking.is_trackable(order):
            raise BusinessError("not_out_for_delivery")
        tracking.assign_driver(order, request.user)
        return Response(s.AdminOrderDetailSerializer(self.get_queryset().get(pk=order.pk)).data)

    @action(detail=True, methods=["get"])
    def drivers(self, request, pk=None):
        """Who this order can be handed to for delivery."""
        order = self.get_object()
        people = tracking.eligible_drivers(order).order_by("-is_driver", "full_name")
        return Response([
            {"id": u.id, "name": u.display_name, "is_driver": u.is_driver, "is_me": u.pk == request.user.pk} for u in people
        ])

    @action(detail=True, methods=["post"], url_path="assign-driver")
    def assign_driver(self, request, pk=None):
        """Hand an order that is out for delivery to another driver (the customer then follows them)."""
        order = self.get_object()
        if not tracking.is_trackable(order):
            raise BusinessError("not_out_for_delivery")
        driver = get_object_or_404(User, pk=request.data.get("driver_id"), is_staff=True, is_active=True)
        if tracking.hand_to(order, request.user, driver) and driver.pk != request.user.pk:
            events.delivery_assigned(order)
        return Response(s.AdminOrderDetailSerializer(self.get_queryset().get(pk=order.pk)).data)

    @action(detail=True, methods=["post"])
    def location(self, request, pk=None):
        """The driver's phone reports its position; {"tracking": false} tells it to stop."""
        order = get_object_or_404(scope_orders(Order.objects.all(), request.user), pk=pk)
        ok = tracking.report_location(order, request.user, request.data.get("latitude"), request.data.get("longitude"))
        return Response({"tracking": ok})

    @action(detail=True, methods=["patch"])
    def note(self, request, pk=None):
        order = self.get_object()
        order.admin_note = str(request.data.get("admin_note", ""))[:500]
        order.save(update_fields=["admin_note", "updated_at"])
        return Response(s.AdminOrderDetailSerializer(order).data)

    @action(detail=False, methods=["get"])
    def export(self, request):
        lang = x.lang_of(request)
        columns = [
            ("رقم الطلب", "Order", x.TEXT), ("التاريخ", "Date", x.DATETIME), ("الحالة", "Status", x.TEXT),
            ("الزبون", "Customer", x.TEXT), ("المنشأة", "Business", x.TEXT), ("الهاتف", "Phone", x.TEXT),
            ("المنطقة", "Area", x.TEXT), ("الاستلام", "Receiving", x.TEXT), ("أجرة التوصيل (ل.س)", "Delivery fee (SYP)", x.SYP),
            ("المجموع (ل.س)", "Subtotal (SYP)", x.SYP), ("خصم الكوبون (ل.س)", "Coupon discount (SYP)", x.SYP),
            ("خصم التطبيق (ل.س)", "App discount (SYP)", x.SYP), ("الإجمالي (ل.س)", "Total (SYP)", x.SYP),
            ("الإجمالي ($)", "Total (USD)", x.USD), ("سعر الصرف", "Exchange rate", x.RATE), ("الكوبون", "Coupon", x.TEXT),
        ]
        rows = [
            [o.number, o.created_at, x.label("status", o.status, lang), o.customer_name, o.business_name, o.customer_phone,
             o.area, x.label("delivery", o.delivery_method, lang), o.delivery_fee, o.subtotal, o.discount, o.app_discount,
             o.total, o.total_usd, o.exchange_rate, o.coupon_code]
            for o in self.get_queryset().order_by("-created_at")[:20000]
        ]
        return x.table_response(request, f"alas-orders-{timezone.localdate()}", columns, rows)


def _notify_payment(entry):
    balance = ledger.balance(entry.user)
    transaction.on_commit(lambda: events.payment_recorded(entry, balance))


def _balance_subquery():
    # A subquery, so it isn't multiplied by the orders join used for the other totals
    sums = LedgerEntry.objects.filter(user=OuterRef("pk")).values("user").annotate(s=Sum("amount")).values("s")
    return Coalesce(Subquery(sums), Value(ledger.ZERO), output_field=DecimalField(max_digits=12, decimal_places=2))


class CustomerViewSet(
    AdminMixin, mixins.ListModelMixin, mixins.RetrieveModelMixin, mixins.CreateModelMixin, mixins.UpdateModelMixin,
    viewsets.GenericViewSet,
):
    """Customers; there is no delete. Distributors see and add only their own customers."""

    serializer_class = s.AdminCustomerSerializer
    http_method_names = ["get", "patch", "post"]
    distributor_access = DISTRIBUTOR_SCOPED

    def get_serializer_class(self):
        return s.AdminCustomerCreateSerializer if self.action == "create" else s.AdminCustomerSerializer

    def create(self, request, *args, **kwargs):
        data = s.AdminCustomerCreateSerializer(data=request.data, context={"request": request})
        data.is_valid(raise_exception=True)
        customer = data.save()
        return Response(s.AdminCustomerSerializer(self.get_queryset().get(pk=customer.pk)).data, status=status.HTTP_201_CREATED)

    def get_queryset(self):
        sale = Q(orders__status__in=SALE_STATUSES)
        qs = scope_customers(User.objects.filter(is_staff=False), self.request.user).select_related("distributor").annotate(
            order_count=Count("orders", filter=sale),
            total_spent=Sum("orders__total", filter=sale),
            last_order_at=Max("orders__created_at"),
            balance=_balance_subquery(),
        )
        p = self.request.query_params
        if q := p.get("q"):
            # Phones are stored as +9639...: "0944123", "944123" and "+963944123" all find the same customer
            digits = "".join(ch for ch in q if ch.isdigit())
            phone_q = Q(phone__icontains=q)
            if len(digits) >= 3:
                phone_q |= Q(phone__contains=digits.lstrip("0"))
            qs = qs.filter(
                Q(email__icontains=q) | Q(full_name__icontains=q) | phone_q
                | Q(business_name__icontains=q) | Q(area_name__icontains=q)
            )
        if p.get("business_type"):
            qs = qs.filter(business_type=p["business_type"])
        if p.get("interest"):
            qs = qs.filter(interests__id=p["interest"])
        if p.get("owing") == "1":
            qs = qs.filter(balance__gt=0)
        return qs.prefetch_related("interests").order_by("-date_joined")

    def perform_update(self, serializer):
        # Buying on credit and its limit are the owner's decision
        owner_fields = {"credit_enabled", "credit_limit", "distributor"}
        if is_distributor(self.request.user):
            owner_fields.add("is_active")  # a distributor can't switch a customer off (only the owner can)
        if owner_fields & set(self.request.data) and not self.request.user.is_superuser:
            raise PermissionDenied("owner_only")
        serializer.save()

    @action(detail=True, methods=["get"])
    def statement(self, request, pk=None):
        customer = self.get_object()
        if x.wants_file(request):
            return _statement_file(request, customer)
        return statement_response(request, self, customer, AdminLedgerEntrySerializer)

    @action(detail=True, methods=["post"])
    def payments(self, request, pk=None):
        """A payment not tied to one order (e.g. one payment covering several orders)."""
        customer = self.get_object()
        data = PaymentSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        d = data.validated_data
        order = get_object_or_404(Order, pk=d["order_id"], user=customer) if d.get("order_id") else None
        entry = ledger.record_payment(customer, d["amount"], request.user, order=order, note=d["note"])
        _notify_payment(entry)
        return Response(AdminLedgerEntrySerializer(entry).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"], permission_classes=[IsOwner])
    def adjustments(self, request, pk=None):
        """Correction entry with a reason (entries are never edited or deleted). Owner only: a
        correction could otherwise hide a payment an employee received."""
        customer = self.get_object()
        data = AdjustmentSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        entry = ledger.record_adjustment(customer, data.validated_data["amount"], request.user, data.validated_data["note"])
        balance = ledger.balance(customer)
        transaction.on_commit(lambda: events.account_adjusted(entry, balance))
        return Response(AdminLedgerEntrySerializer(entry).data, status=status.HTTP_201_CREATED)


def _statement_file(request, customer):
    lang = x.lang_of(request)
    columns = [
        ("التاريخ", "Date", x.DATETIME), ("الحركة", "Entry", x.TEXT), ("الطلب", "Order", x.TEXT),
        ("المبلغ (ل.س)", "Amount (SYP)", x.SYP), ("الرصيد بعدها (ل.س)", "Balance after (SYP)", x.SYP),
        ("ملاحظة", "Note", x.TEXT), ("بواسطة", "By", x.TEXT),
    ]
    rows = [
        [e.created_at, x.label("kind", e.kind, lang), e.order.number if e.order else "", e.amount, e.balance_after, e.note,
         e.created_by.display_name if e.created_by else ""]
        for e in reversed(list(ledger.statement(customer).select_related("created_by", "order")))
    ]
    title = [customer.business_name or customer.full_name, customer.full_name if customer.business_name else "", customer.phone]
    footer = ["المتبقي" if lang == "ar" else "Balance", "", "", None, ledger.balance(customer), "", ""]
    return x.table_response(request, f"statement-{customer.pk}-{timezone.localdate()}", columns, rows, title=title, footer=footer)


class ReceivablesView(AdminMixin, APIView):
    """Customers with an open balance, largest first. ?format=xlsx (or csv) to export."""

    distributor_access = DISTRIBUTOR_SCOPED

    def get(self, request):
        rows = _scoped_receivables(request.user)
        users = User.objects.in_bulk([uid for uid, _ in rows])
        items = [
            {
                "id": uid, "full_name": users[uid].full_name, "business_name": users[uid].business_name,
                "phone": users[uid].phone, "area_name": users[uid].area_name, "balance": str(b),
                "credit_limit": None if users[uid].credit_limit is None else str(users[uid].credit_limit),
            }
            for uid, b in rows if uid in users
        ]
        total = sum((b for _, b in rows if b > 0), ledger.ZERO)
        if x.wants_file(request):
            lang = x.lang_of(request)
            columns = [
                ("الزبون", "Customer", x.TEXT), ("المنشأة", "Business", x.TEXT), ("الهاتف", "Phone", x.TEXT),
                ("المنطقة", "Area", x.TEXT), ("الرصيد (ل.س)", "Balance (SYP)", x.SYP), ("سقف الدين (ل.س)", "Credit limit (SYP)", x.SYP),
            ]
            rows = [[i["full_name"], i["business_name"], i["phone"], i["area_name"], Decimal(i["balance"]),
                     Decimal(i["credit_limit"]) if i["credit_limit"] else None] for i in items]
            footer = ["الإجمالي" if lang == "ar" else "Total", "", "", "", total, None]
            return x.table_response(request, f"receivables-{timezone.localdate()}", columns, rows, footer=footer)
        return Response({"total": str(total), "count": len(items), "results": items})


class CouponViewSet(AdminMixin, viewsets.ModelViewSet):
    serializer_class = s.AdminCouponSerializer
    queryset = Coupon.objects.all()


class BannerViewSet(AdminMixin, ImageUploadMixin, viewsets.ModelViewSet):
    serializer_class = s.AdminBannerSerializer
    queryset = Banner.objects.all()
    pagination_class = None
    parser_classes = [JSONParser, MultiPartParser, FormParser]

    def perform_create(self, serializer):
        """A banner is created together with its image (multipart field 'image')."""
        upload = self.request.FILES.get("image")
        if not upload:
            raise BusinessError("image_required")
        main, _thumb = process_upload(upload)
        banner = serializer.save(image=main)
        return banner

    def perform_destroy(self, instance):
        instance.image.delete(save=False)
        instance.delete()


class SettingsView(OwnerMixin, APIView):
    def get(self, request):
        return Response(s.AdminSettingsSerializer(StoreSettings.load()).data)

    def patch(self, request):
        ser = s.AdminSettingsSerializer(StoreSettings.load(), data=request.data, partial=True)
        ser.is_valid(raise_exception=True)
        ser.save()
        fx.clear_cache()
        return Response(ser.data)


class ExchangeRateView(AdminMixin, APIView):
    distributor_access = DISTRIBUTOR_READ  # distributors see products and stock, never change them

    """GET: the dollar rate in use and where it came from (all staff).
    POST {"action": "refresh"} reads sp-today.com now; {"action": "accept", "id": n} applies a reading
    that was held back because it moved a lot (owner only)."""

    def get(self, request):
        return Response(fx.status())

    def post(self, request):
        if not request.user.is_superuser:
            raise PermissionDenied()
        action_name = request.data.get("action")
        if action_name == "refresh":
            entry, problem = fx.update_from_source()
            if entry is None:
                raise BusinessError("rate_fetch_failed")
        elif action_name == "accept":
            from apps.store.models import ExchangeRate

            entry = get_object_or_404(ExchangeRate, pk=request.data.get("id"), accepted=False)
            fx.accept(entry)
        else:
            raise BusinessError("invalid_action")
        return Response(fx.status())


class LegalViewSet(AdminMixin, mixins.ListModelMixin, mixins.RetrieveModelMixin, mixins.UpdateModelMixin, viewsets.GenericViewSet):
    serializer_class = s.AdminLegalSerializer
    queryset = LegalPage.objects.all()
    lookup_field = "slug"
    pagination_class = None
    http_method_names = ["get", "patch"]


class NotificationViewSet(AdminMixin, mixins.ListModelMixin, mixins.CreateModelMixin, viewsets.GenericViewSet):
    serializer_class = s.AdminNotificationSerializer

    def get_queryset(self):
        return Notification.objects.filter(user__isnull=True)

    def create(self, request, *args, **kwargs):
        data = s.BroadcastSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        d = data.validated_data
        extra = {}
        if d.get("product_id"):
            extra["product_id"] = d["product_id"]
        if d.get("category_id"):
            extra["category_id"] = d["category_id"]
        audience = {
            "interests": d.get("target_interests", []),
            "business_types": d.get("target_business_types", []),
            "zones": d.get("target_zones", []),
        }
        n = events.broadcast(d["title_ar"], d["title_en"], d.get("body_ar", ""), d.get("body_en", ""), d["kind"], extra, audience)
        return Response(s.AdminNotificationSerializer(n).data, status=status.HTTP_201_CREATED)

    @action(detail=False, methods=["post"])
    def audience(self, request):
        """Preview how many customers a targeted notification would reach."""
        d = request.data
        count = events.target_customers({
            "interests": d.get("target_interests") or [],
            "business_types": d.get("target_business_types") or [],
            "zones": d.get("target_zones") or [],
        }).count()
        return Response({"count": count})


class ZoneViewSet(AdminMixin, viewsets.ModelViewSet):
    distributor_access = DISTRIBUTOR_READ  # areas, for the add-customer form

    serializer_class = s.AdminZoneSerializer
    pagination_class = None

    def get_queryset(self):
        return DeliveryZone.objects.prefetch_related("areas")


class ReportView(AdminMixin, APIView):
    """GET ?period=day|week|month&from=YYYY-MM-DD&to=YYYY-MM-DD[&format=xlsx|csv]"""

    TRUNC = {"day": TruncDay, "week": TruncWeek, "month": TruncMonth}
    distributor_access = DISTRIBUTOR_SCOPED

    def get(self, request):
        p = request.query_params
        period = p.get("period", "day") if p.get("period") in self.TRUNC else "day"
        today = timezone.localdate()
        try:
            date_to = datetime.strptime(p["to"], "%Y-%m-%d").date() if p.get("to") else today
            default_days = {"day": 30, "week": 7 * 12, "month": 365}[period]
            date_from = datetime.strptime(p["from"], "%Y-%m-%d").date() if p.get("from") else date_to - timedelta(days=default_days)
        except ValueError:
            raise BusinessError("invalid_date")
        orders = scope_orders(Order.objects.all(), request.user).filter(
            status__in=SALE_STATUSES, created_at__gte=_local_day_start(date_from), created_at__lt=_local_day_start(date_to + timedelta(days=1))
        )
        rows = (
            orders.annotate(bucket=self.TRUNC[period]("created_at"))
            .values("bucket")
            .annotate(sales=Sum("total"), sales_usd=Sum("total_usd"), discount=Sum("discount"), orders=Count("id"))
            .order_by("bucket")
        )
        series = [
            {"period": r["bucket"].date().isoformat(), "sales": str(r["sales"]), "sales_usd": str(r["sales_usd"] or 0),
             "discount": str(r["discount"]), "orders": r["orders"]}
            for r in rows
        ]
        totals = orders.aggregate(sales=Sum("total"), sales_usd=Sum("total_usd"), orders=Count("id"), discount=Sum("discount"))
        top = (
            OrderItem.objects.filter(order__in=orders)
            .values("product_name_ar", "product_name_en")
            .annotate(quantity=Sum("quantity"), revenue=Sum("line_total"))
            .order_by("-revenue")[:10]
        )
        if x.wants_file(request):
            lang = x.lang_of(request)
            columns = [
                ("الفترة", "Period", x.DATE), ("الطلبات", "Orders", x.INT), ("المبيعات (ل.س)", "Sales (SYP)", x.SYP),
                ("المبيعات ($)", "Sales (USD)", x.USD), ("الخصومات (ل.س)", "Discounts (SYP)", x.SYP),
            ]
            rows = [[r["bucket"].date(), r["orders"], r["sales"], r["sales_usd"] or 0, r["discount"]] for r in rows]
            footer = ["الإجمالي" if lang == "ar" else "Total", totals["orders"], totals["sales"] or 0, totals["sales_usd"] or 0,
                      totals["discount"] or 0]
            return x.table_response(request, f"alas-sales-{period}-{date_from}_{date_to}", columns, rows, footer=footer)
        return Response(
            {
                "period": period,
                "from": date_from.isoformat(),
                "to": date_to.isoformat(),
                "series": series,
                "totals": {
                    "sales": str(totals["sales"] or 0),
                    "sales_usd": str(totals["sales_usd"] or 0),
                    "orders": totals["orders"],
                    "discount": str(totals["discount"] or 0),
                    "average_order": str(round((totals["sales"] or 0) / totals["orders"], 2)) if totals["orders"] else "0",
                },
                "top_products": [{**t, "revenue": str(t["revenue"])} for t in top],
            }
        )


def _inbox(user):
    """Owner: every alert. Distributor: alerts about their customers. Employees: the store's own alerts."""
    return scope_orders(AdminNotification.objects.all(), user)


def _unread_inbox(user):
    qs = _inbox(user)
    return qs.filter(created_at__gt=user.admin_inbox_seen_at) if user.admin_inbox_seen_at else qs


class AdminInboxView(AdminMixin, mixins.ListModelMixin, viewsets.GenericViewSet):
    """Alerts sent to the admin app (new orders, cancellations), newest first."""

    serializer_class = s.AdminInboxSerializer
    distributor_access = DISTRIBUTOR_SCOPED

    def get_queryset(self):
        return _inbox(self.request.user)

    def list(self, request, *args, **kwargs):
        response = super().list(request, *args, **kwargs)
        response.data["unread"] = _unread_inbox(request.user).count()
        return response

    @action(detail=False, methods=["post"])
    def seen(self, request):
        request.user.admin_inbox_seen_at = timezone.now()
        request.user.save(update_fields=["admin_inbox_seen_at"])
        return Response(status=status.HTTP_204_NO_CONTENT)


class WhatsAppConfigView(OwnerMixin, APIView):
    """WhatsApp account for verification codes. POST sends a test code to a number."""

    def get(self, request):
        from apps.accounts.models import WhatsAppConfig

        return Response(s.AdminWhatsAppSerializer(WhatsAppConfig.load()).data)

    def patch(self, request):
        from apps.accounts.models import WhatsAppConfig

        ser = s.AdminWhatsAppSerializer(WhatsAppConfig.load(), data=request.data, partial=True)
        ser.is_valid(raise_exception=True)
        return Response(s.AdminWhatsAppSerializer(ser.save()).data)

    def post(self, request):
        from apps.accounts import whatsapp
        from apps.accounts.phone import normalize_phone

        phone = normalize_phone(request.data.get("phone"))
        if not phone:
            raise BusinessError("invalid_phone")
        try:
            if whatsapp.configured():
                number, name = whatsapp.sender_number()
                whatsapp._send_template(phone, "123456", "ar")
            else:
                status = whatsapp.gateway_status()
                if status.get("status") != "open":
                    return Response({"ok": False, "error": "not_configured"})
                number, name = status.get("me") or "", ""
                whatsapp.send_via_gateway(phone, whatsapp.message_text("123456", "ar"))
        except whatsapp.WhatsAppError as e:
            return Response({"ok": False, "error": str(e)})
        return Response({"ok": True, "from": number, "name": name, "to": phone})


class WhatsAppLinkView(OwnerMixin, APIView):
    """The store number linked to the gateway: GET shows the state or the QR to scan, POST unlinks."""

    def get(self, request):
        from apps.accounts import whatsapp

        return Response(whatsapp.gateway_status())

    def post(self, request):
        """{"action": "pair", "phone": "09..."} returns a code to type on the phone; otherwise unlinks."""
        from apps.accounts import whatsapp
        from apps.accounts.phone import normalize_phone

        try:
            if request.data.get("action") == "pair":
                phone = normalize_phone(request.data.get("phone"))
                if not phone:
                    raise BusinessError("invalid_phone")
                return Response(whatsapp.gateway("POST", "/pair", {"phone": phone}))
            whatsapp.gateway("POST", "/logout", {})
        except whatsapp.WhatsAppError as e:
            raise BusinessError(str(e))
        return Response({"ok": True})


class StaffViewSet(OwnerMixin, mixins.ListModelMixin, mixins.CreateModelMixin, mixins.UpdateModelMixin, viewsets.GenericViewSet):
    serializer_class = s.StaffSerializer
    pagination_class = None
    http_method_names = ["get", "post", "patch"]

    def get_queryset(self):
        return User.objects.filter(is_staff=True).order_by("-is_superuser", "-is_active", "full_name", "id")

    def perform_update(self, serializer):
        user = serializer.instance
        was_active = user.is_active
        password_changed = bool(serializer.validated_data.get("password"))
        user = serializer.save()
        if (was_active and not user.is_active) or (password_changed and user.pk != self.request.user.pk):
            _end_sessions(user)


class DriverViewSet(AdminMixin, mixins.ListModelMixin, mixins.CreateModelMixin, mixins.UpdateModelMixin, viewsets.GenericViewSet):
    """Delivery accounts. The owner sees every driver (the store's and the distributors'); a
    distributor sees and adds only their own. Employees can't manage drivers."""

    serializer_class = s.DriverSerializer
    pagination_class = None
    http_method_names = ["get", "post", "patch"]
    distributor_access = DISTRIBUTOR_SCOPED

    def initial(self, request, *args, **kwargs):
        super().initial(request, *args, **kwargs)
        if not (request.user.is_superuser or is_distributor(request.user)):
            raise PermissionDenied("owner_only")

    def get_queryset(self):
        qs = User.objects.filter(is_driver=True).select_related("works_for").order_by("-is_active", "full_name", "id")
        return qs if self.request.user.is_superuser else qs.filter(works_for=self.request.user)

    def perform_update(self, serializer):
        user = serializer.instance
        was_active = user.is_active
        password_changed = bool(serializer.validated_data.get("password"))
        user = serializer.save()
        if (was_active and not user.is_active) or password_changed:
            _end_sessions(user)


class CollectionsView(OwnerMixin, APIView):
    """Cash each staff member recorded as received, for a period (owner only).

    ?from=YYYY-MM-DD&to=YYYY-MM-DD (default: today); &staff=<id> adds that person's payments.
    """

    def get(self, request):
        from apps.ledger.models import LedgerEntry

        p = request.query_params
        today = timezone.localdate()
        try:
            date_from = date.fromisoformat(p["from"]) if p.get("from") else today
            date_to = date.fromisoformat(p["to"]) if p.get("to") else today
        except ValueError:
            raise BusinessError("invalid_date")
        qs = LedgerEntry.objects.filter(
            kind=LedgerEntry.PAYMENT,
            created_at__gte=_local_day_start(date_from),
            created_at__lt=_local_day_start(date_to + timedelta(days=1)),
        ).select_related("created_by", "user", "order")
        rows = {}
        for e in qs:
            key = e.created_by_id or 0
            row = rows.setdefault(key, {
                "id": e.created_by_id, "name": e.created_by.display_name if e.created_by_id else None,
                "total": Decimal("0"), "count": 0,
            })
            row["total"] += -e.amount
            row["count"] += 1
        staff = sorted(rows.values(), key=lambda r: -r["total"])
        data = {
            "from": date_from, "to": date_to,
            "total": str(sum((r["total"] for r in staff), Decimal("0"))),
            "staff": [{**r, "total": str(r["total"])} for r in staff],
        }
        if p.get("staff") is not None:
            sid = int(p["staff"]) if str(p["staff"]).isdigit() and p["staff"] != "0" else None
            data["entries"] = [
                {
                    "amount": str(-e.amount), "created_at": e.created_at, "note": e.note,
                    "customer": (e.user.business_name or e.user.full_name) if e.user_id else None,
                    "customer_id": e.user_id, "order_id": e.order_id, "order_number": e.order.number if e.order_id else None,
                }
                for e in qs.filter(created_by_id=sid).order_by("-created_at")
            ]
        return Response(data)


class AuditLogView(OwnerMixin, APIView):
    """Everything done in the admin app. ?staff=<id>&from=&to= ; &format=xlsx (or csv) downloads it."""

    def get(self, request):
        from .models import AuditLog

        p = request.query_params
        qs = AuditLog.objects.all()
        if p.get("staff"):
            qs = qs.filter(actor_id=p["staff"])
        try:
            if p.get("from"):
                qs = qs.filter(created_at__gte=_local_day_start(date.fromisoformat(p["from"])))
            if p.get("to"):
                qs = qs.filter(created_at__lt=_local_day_start(date.fromisoformat(p["to"]) + timedelta(days=1)))
        except ValueError:
            raise BusinessError("invalid_date")
        if x.wants_file(request):
            lang = x.lang_of(request)
            columns = [
                ("التاريخ", "Date", x.DATETIME), ("الموظف", "Employee", x.TEXT), ("العملية", "Action", x.TEXT),
                ("على", "Target", x.TEXT), ("التفاصيل", "Details", x.TEXT), ("IP", "IP", x.TEXT),
            ]
            rows = [
                [e.created_at, e.actor_name, e.action_ar if lang == "ar" else e.action_en, e.target,
                 json.dumps(e.details, ensure_ascii=False) if e.details else "", e.ip or ""]
                for e in qs[:20000]
            ]
            return x.table_response(request, f"alas-activity-log-{timezone.localdate()}", columns, rows)
        paginator = Pagination()
        page = paginator.paginate_queryset(qs, request, view=self)
        return paginator.get_paginated_response([
            {"id": e.id, "actor_id": e.actor_id, "actor_name": e.actor_name, "action_ar": e.action_ar, "action_en": e.action_en,
             "target": e.target, "details": e.details, "created_at": e.created_at}
            for e in page
        ])
