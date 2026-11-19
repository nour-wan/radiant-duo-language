from decimal import Decimal

from django.db import transaction
from rest_framework import serializers

from apps.accounts.models import BUSINESS_TYPES, User
from apps.catalog.models import Category, Product, Variant
from apps.catalog.serializers import ImageSerializer
from apps.core.images import absolute_media_url
from apps.notifications.models import AdminNotification, Notification
from apps.orders.models import Order
from apps.orders.serializers import OrderDetailSerializer, OrderItemSerializer
from apps.promotions.models import Banner, Coupon
from apps.store.delivery import DeliveryArea, DeliveryZone
from apps.store import fx
from apps.store.models import LegalPage, StoreSettings


class AdminCategorySerializer(serializers.ModelSerializer):
    image = serializers.SerializerMethodField()
    product_count = serializers.IntegerField(read_only=True, default=0)

    class Meta:
        model = Category
        fields = [
            "id", "slug", "name_ar", "name_en", "description_ar", "description_en", "image", "sort_order",
            "is_active", "product_count",
        ]
        read_only_fields = ["slug"]

    def get_image(self, obj):
        return absolute_media_url(obj.image)


class AdminVariantSerializer(serializers.ModelSerializer):
    """price / discount_price are in USD (entered by the admin); *_syp is what customers see now."""

    id = serializers.IntegerField(required=False)
    price_syp = serializers.SerializerMethodField()
    discount_price_syp = serializers.SerializerMethodField()

    class Meta:
        model = Variant
        fields = [
            "id", "label_ar", "label_en", "unit", "unit_quantity", "sku", "price", "discount_price", "stock",
            "min_order_qty", "is_active", "sort_order", "price_syp", "discount_price_syp",
        ]

    def _syp(self, usd):
        rate = fx.rate_or_none()
        return str(fx.to_syp(usd, rate)) if usd is not None and rate else None

    def get_price_syp(self, obj):
        return self._syp(obj.price)

    def get_discount_price_syp(self, obj):
        return self._syp(obj.discount_price)

    def validate(self, data):
        price, discount = data.get("price"), data.get("discount_price")
        if price is not None and discount is not None and discount >= price:
            raise serializers.ValidationError({"discount_price": "discount_must_be_lower"})
        return data


class AdminProductSerializer(serializers.ModelSerializer):
    variants = AdminVariantSerializer(many=True)
    images = ImageSerializer(many=True, read_only=True)
    category_name_ar = serializers.CharField(source="category.name_ar", read_only=True)
    category_name_en = serializers.CharField(source="category.name_en", read_only=True)
    total_stock = serializers.SerializerMethodField()

    class Meta:
        model = Product
        fields = [
            "id", "slug", "category", "category_name_ar", "category_name_en", "name_ar", "name_en",
            "short_description_ar", "short_description_en", "description_ar", "description_en", "specifications",
            "keywords", "is_featured", "is_active", "sold_count", "variants", "images", "total_stock",
            "created_at", "updated_at",
        ]
        read_only_fields = ["slug", "sold_count", "created_at", "updated_at"]

    def get_total_stock(self, obj):
        return sum(v.stock for v in obj.variants.all())

    def validate_variants(self, value):
        if not value:
            raise serializers.ValidationError("at_least_one_variant")
        return value

    @transaction.atomic
    def create(self, data):
        variants = data.pop("variants")
        product = Product.objects.create(**data)
        for i, v in enumerate(variants):
            v.pop("id", None)
            v.setdefault("sort_order", i)
            Variant.objects.create(product=product, **v)
        return product

    @transaction.atomic
    def update(self, product, data):
        variants = data.pop("variants", None)
        for key, value in data.items():
            setattr(product, key, value)
        product.save()
        if variants is not None:
            existing = {v.id: v for v in product.variants.all()}
            keep = set()
            for i, v in enumerate(variants):
                vid = v.pop("id", None)
                v.setdefault("sort_order", i)
                if vid in existing:
                    obj = existing[vid]
                    for key, value in v.items():
                        setattr(obj, key, value)
                    obj.save()
                    keep.add(vid)
                else:
                    keep.add(Variant.objects.create(product=product, **v).id)
            product.variants.exclude(id__in=keep).delete()
        return product


class AdminOrderListSerializer(serializers.ModelSerializer):
    item_count = serializers.IntegerField(read_only=True)

    class Meta:
        model = Order
        fields = [
            "id", "number", "status", "delivery_method", "customer_name", "business_name", "customer_phone", "city", "total",
            "total_usd", "exchange_rate", "item_count", "distributor_name", "created_at",
        ]

    distributor_name = serializers.SerializerMethodField()

    def get_distributor_name(self, obj):
        return obj.distributor.display_name if obj.distributor_id else None


class AdminOrderEventSerializer(serializers.Serializer):
    status = serializers.CharField()
    note = serializers.CharField()
    created_at = serializers.DateTimeField()
    by_name = serializers.SerializerMethodField()

    def get_by_name(self, obj):
        return obj.by.display_name if obj.by_id else None


class AdminOrderItemSerializer(OrderItemSerializer):
    class Meta(OrderItemSerializer.Meta):
        fields = OrderItemSerializer.Meta.fields + ["unit_price_usd"]


class AdminOrderDetailSerializer(OrderDetailSerializer):
    """Amounts in SYP like the customer sees them, plus the rate and the USD total for the store."""

    items = AdminOrderItemSerializer(many=True, read_only=True)
    user_id = serializers.IntegerField(read_only=True)
    allowed_statuses = serializers.SerializerMethodField()
    events = AdminOrderEventSerializer(many=True, read_only=True)
    payments = serializers.SerializerMethodField()
    driver_id = serializers.IntegerField(read_only=True)
    driver_name = serializers.SerializerMethodField()

    class Meta(OrderDetailSerializer.Meta):
        fields = OrderDetailSerializer.Meta.fields + [
            "customer_email", "user_id", "admin_note", "customer_deleted", "allowed_statuses", "payments",
            "exchange_rate", "total_usd", "driver_id", "driver_name", "distributor_name",
        ]

    distributor_name = serializers.SerializerMethodField()

    def get_distributor_name(self, obj):
        return obj.distributor.display_name if obj.distributor_id else None

    def get_driver_name(self, obj):
        return obj.driver.display_name if obj.driver_id else None

    def get_payments(self, obj):
        """Cash received for this order and who took it."""
        from apps.ledger.models import LedgerEntry

        return [
            {"amount": str(-e.amount), "by_name": e.created_by.display_name if e.created_by_id else None,
             "note": e.note, "created_at": e.created_at}
            for e in LedgerEntry.objects.filter(order=obj, kind=LedgerEntry.PAYMENT).select_related("created_by").order_by("created_at")
        ]

    def get_allowed_statuses(self, obj):
        return sorted(Order.TRANSITIONS.get(obj.status, set()))


class StatusChangeSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=[s for s, _ in Order.STATUSES])
    note = serializers.CharField(required=False, allow_blank=True, max_length=500)
    # Out for delivery: who delivers it (default: whoever sends it out)
    driver_id = serializers.IntegerField(required=False, allow_null=True)
    # Cash received on delivery (recorded as a payment on the customer's account)
    paid_amount = serializers.DecimalField(max_digits=12, decimal_places=2, required=False, allow_null=True, min_value=Decimal("0"))


class AdminCustomerSerializer(serializers.ModelSerializer):
    order_count = serializers.IntegerField(read_only=True, default=0)
    total_spent = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True, default=0)
    last_order_at = serializers.DateTimeField(read_only=True, default=None)
    balance = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True, default=0)
    interests = serializers.SerializerMethodField()
    # Owner only (checked in the view): move the customer to a distributor, or back to the store (null)
    distributor = serializers.PrimaryKeyRelatedField(
        queryset=User.objects.filter(is_distributor=True, is_staff=True), required=False, allow_null=True
    )
    distributor_name = serializers.SerializerMethodField()

    def get_distributor_name(self, obj):
        return obj.distributor.display_name if obj.distributor_id else None

    class Meta:
        model = User
        fields = [
            "id", "email", "full_name", "phone", "phone_verified", "business_name", "business_type", "area_name",
            "address", "interests", "language", "is_active", "date_joined", "last_login", "order_count", "total_spent",
            "last_order_at", "balance", "credit_enabled", "credit_limit", "distributor", "distributor_name",
        ]
        read_only_fields = [
            "email", "full_name", "phone", "phone_verified", "business_name", "business_type", "area_name", "address",
            "language", "date_joined", "last_login",
        ]

    def get_interests(self, obj):
        return [{"id": c.id, "name_ar": c.name_ar, "name_en": c.name_en} for c in obj.interests.all()]


class AdminCustomerCreateSerializer(serializers.Serializer):
    """An employee or distributor adds a customer. The customer signs in later with
    "Forgot password" (a WhatsApp code to their number) and sets their own password."""

    full_name = serializers.CharField(max_length=150)
    phone = serializers.CharField(max_length=32)
    business_name = serializers.CharField(max_length=150)
    business_type = serializers.ChoiceField(choices=[c for c, _ in BUSINESS_TYPES], required=False, allow_blank=True)
    delivery_area = serializers.PrimaryKeyRelatedField(queryset=DeliveryArea.objects.filter(is_active=True), required=False, allow_null=True)
    area_name = serializers.CharField(max_length=100, required=False, allow_blank=True)
    address = serializers.CharField(max_length=300, required=False, allow_blank=True)
    # Owner only: add straight to a distributor
    distributor = serializers.PrimaryKeyRelatedField(
        queryset=User.objects.filter(is_distributor=True, is_staff=True), required=False, allow_null=True
    )

    def validate_phone(self, value):
        from apps.accounts.phone import normalize_phone

        phone = normalize_phone(value)
        if not phone:
            raise serializers.ValidationError("invalid_phone")
        if User.objects.filter(phone=phone).exists():
            raise serializers.ValidationError("phone_taken")
        return phone

    def validate(self, data):
        area = data.get("delivery_area")
        if area is not None:
            data["area_name"] = area.name_ar
        if not data.get("area_name", "").strip():
            raise serializers.ValidationError({"area_name": "required"})
        return data

    @transaction.atomic
    def create(self, data):
        from apps.accounts.serializers import create_default_address
        from apps.core.permissions import is_distributor

        by = self.context["request"].user
        if is_distributor(by):
            data["distributor"] = by  # a distributor's customers are always their own
        elif not by.is_superuser:
            data.pop("distributor", None)  # employees add the store's own customers
        user = User.objects.create_user(**data)  # no password yet
        create_default_address(user)
        return user


class AdminAreaSerializer(serializers.ModelSerializer):
    id = serializers.IntegerField(required=False)

    class Meta:
        model = DeliveryArea
        fields = ["id", "name_ar", "name_en", "sort_order", "is_active"]


class AdminZoneSerializer(serializers.ModelSerializer):
    areas = AdminAreaSerializer(many=True, required=False)

    class Meta:
        model = DeliveryZone
        fields = ["id", "name_ar", "name_en", "fee", "is_default_for_unlisted", "sort_order", "is_active", "areas"]

    @transaction.atomic
    def save(self, **kwargs):
        areas = self.validated_data.pop("areas", None)
        zone = super().save(**kwargs)
        if zone.is_default_for_unlisted:
            DeliveryZone.objects.exclude(pk=zone.pk).update(is_default_for_unlisted=False)
        if areas is not None:
            keep = set()
            existing = {a.id: a for a in zone.areas.all()}
            for i, a in enumerate(areas):
                aid = a.pop("id", None)
                a.setdefault("sort_order", i)
                if aid in existing:
                    for k, v in a.items():
                        setattr(existing[aid], k, v)
                    existing[aid].save()
                    keep.add(aid)
                else:
                    keep.add(DeliveryArea.objects.create(zone=zone, **a).id)
            zone.areas.exclude(id__in=keep).delete()
        return zone


class AdminCouponSerializer(serializers.ModelSerializer):
    class Meta:
        model = Coupon
        fields = [
            "id", "code", "kind", "value", "min_order_total", "max_discount", "max_uses", "max_uses_per_user",
            "used_count", "starts_at", "expires_at", "is_active", "created_at",
        ]
        read_only_fields = ["used_count", "created_at"]

    def validate_code(self, value):
        value = value.strip().upper()
        if not value.replace("-", "").replace("_", "").isalnum():
            raise serializers.ValidationError("invalid_code")
        return value

    def validate(self, data):
        kind = data.get("kind", getattr(self.instance, "kind", Coupon.PERCENT))
        value = data.get("value", getattr(self.instance, "value", None))
        if kind == Coupon.PERCENT and value is not None and value > 100:
            raise serializers.ValidationError({"value": "percent_over_100"})
        return data


class AdminBannerSerializer(serializers.ModelSerializer):
    image = serializers.SerializerMethodField()

    class Meta:
        model = Banner
        fields = [
            "id", "image", "title_ar", "title_en", "subtitle_ar", "subtitle_en", "link_type", "link_value",
            "sort_order", "is_active", "starts_at", "ends_at",
        ]

    def get_image(self, obj):
        return absolute_media_url(obj.image)


class AdminSettingsSerializer(serializers.ModelSerializer):
    class Meta:
        model = StoreSettings
        exclude = ["id", "usd_rate_alerted_at"]
        read_only_fields = ["usd_rate_error", "syp_converted_rate"]

    def validate(self, data):
        mode = data.get("usd_rate_mode", getattr(self.instance, "usd_rate_mode", "auto"))
        manual = data.get("usd_rate_manual", getattr(self.instance, "usd_rate_manual", None))
        if mode == "manual" and not manual:
            raise serializers.ValidationError({"usd_rate_manual": "required"})
        if manual is not None and not (fx.MIN_RATE <= manual <= fx.MAX_RATE):
            raise serializers.ValidationError({"usd_rate_manual": "rate_out_of_range"})
        return data


class AdminLegalSerializer(serializers.ModelSerializer):
    class Meta:
        model = LegalPage
        fields = ["slug", "title_ar", "title_en", "body_ar", "body_en", "updated_at"]
        read_only_fields = ["slug", "updated_at"]


class BroadcastSerializer(serializers.Serializer):
    title_ar = serializers.CharField(max_length=150)
    title_en = serializers.CharField(max_length=150)
    body_ar = serializers.CharField(max_length=500, required=False, allow_blank=True)
    body_en = serializers.CharField(max_length=500, required=False, allow_blank=True)
    kind = serializers.ChoiceField(choices=["offer", "general"], default="offer")
    product_id = serializers.IntegerField(required=False)
    category_id = serializers.IntegerField(required=False)
    # Optional audience: empty = all customers
    target_interests = serializers.ListField(child=serializers.IntegerField(), required=False)
    target_business_types = serializers.ListField(child=serializers.CharField(), required=False)
    target_zones = serializers.ListField(child=serializers.IntegerField(), required=False)


class AdminNotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = ["id", "kind", "title_ar", "title_en", "body_ar", "body_en", "data", "sent_count", "audience", "created_at"]


class AdminInboxSerializer(serializers.ModelSerializer):
    class Meta:
        model = AdminNotification
        fields = ["id", "title_ar", "title_en", "body_ar", "body_en", "data", "created_at"]


class AdminWhatsAppSerializer(serializers.Serializer):
    """The token is write-only: the app only learns whether one is saved."""

    phone_number_id = serializers.RegexField(r"^\d*$", max_length=40, required=False, allow_blank=True)
    access_token = serializers.CharField(write_only=True, required=False, allow_blank=True, trim_whitespace=True)
    otp_template = serializers.RegexField(r"^[a-z0-9_]*$", max_length=100, required=False, allow_blank=True)
    template_lang = serializers.RegexField(r"^[a-zA-Z_]{2,10}$", required=False)
    token_saved = serializers.SerializerMethodField()
    configured = serializers.SerializerMethodField()

    def get_token_saved(self, obj):
        return bool(obj.access_token)

    def get_configured(self, obj):
        from apps.accounts import whatsapp

        return whatsapp.configured()

    def update(self, instance, data):
        # An empty token field means "keep the saved one"
        if not data.get("access_token"):
            data.pop("access_token", None)
        for k, v in data.items():
            setattr(instance, k, v)
        instance.save()
        return instance


class StaffSerializer(serializers.ModelSerializer):
    """Admin app accounts. The owner adds employees, renames them, resets passwords, disables them."""

    is_owner = serializers.BooleanField(source="is_superuser", read_only=True)
    phone = serializers.CharField(max_length=32, required=False, allow_blank=True)
    password = serializers.CharField(write_only=True, required=False)
    # A distributor is a partner: sees only their own customers (fixed when the account is created)
    is_distributor = serializers.BooleanField(required=False)
    distributor_code = serializers.CharField(max_length=12, required=False, allow_blank=True, allow_null=True)
    customer_count = serializers.SerializerMethodField()
    month_sales = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            "id", "full_name", "phone", "email", "is_owner", "is_active", "last_login", "date_joined", "password",
            "is_distributor", "distributor_code", "customer_count", "month_sales", "is_driver",
        ]
        read_only_fields = ["id", "email", "is_owner", "last_login", "date_joined", "is_driver"]

    def get_customer_count(self, obj):
        return obj.distributor_customers.count() if obj.is_distributor else None

    def get_month_sales(self, obj):
        if not obj.is_distributor:
            return None
        from django.db.models import Sum
        from django.utils import timezone

        start = timezone.localtime().replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        total = Order.objects.filter(
            distributor=obj, created_at__gte=start, status__in=[Order.PENDING, Order.CONFIRMED, Order.SHIPPED, Order.DELIVERED]
        ).aggregate(t=Sum("total"))["t"]
        return str(total or 0)

    def validate_distributor_code(self, value):
        import re

        code = (value or "").strip().upper()
        if not code:
            return None
        if not re.fullmatch(r"[A-Z0-9]{3,12}", code):
            raise serializers.ValidationError("invalid_distributor_code")
        others = User.objects.filter(distributor_code=code)
        if self.instance is not None:
            others = others.exclude(pk=self.instance.pk)
        if others.exists():
            raise serializers.ValidationError("distributor_code_taken")
        return code

    def validate_phone(self, value):
        from apps.accounts.phone import normalize_phone

        if not value:
            return value
        phone = normalize_phone(value)
        if not phone:
            raise serializers.ValidationError("invalid_phone")
        others = User.objects.filter(phone=phone)
        if self.instance is not None:
            others = others.exclude(pk=self.instance.pk)
        if others.exists():
            raise serializers.ValidationError("phone_taken")
        return phone

    def validate_password(self, value):
        from django.contrib.auth import password_validation

        password_validation.validate_password(value)
        return value

    def validate(self, data):
        if self.instance is None:
            if not data.get("full_name", "").strip():
                raise serializers.ValidationError({"full_name": "required"})
            if not data.get("phone"):
                raise serializers.ValidationError({"phone": "required"})
            if not data.get("password"):
                raise serializers.ValidationError({"password": "required"})
        elif self.instance.is_superuser and data.get("is_active") is False:
            raise serializers.ValidationError({"is_active": "owner_cannot_be_disabled"})
        if self.instance is not None:
            data.pop("is_distributor", None)  # an employee can't become a distributor or the other way round
            if not self.instance.is_distributor:
                data.pop("distributor_code", None)
        return data

    def create(self, data):
        distributor = bool(data.get("is_distributor"))
        user = User.objects.create_user(
            phone=data["phone"], password=data["password"], full_name=data["full_name"].strip(),
            is_staff=True, phone_verified=True, is_distributor=distributor,
        )
        if distributor:
            user.distributor_code = data.get("distributor_code") or _new_distributor_code()
            user.save(update_fields=["distributor_code"])
        return user

    def update(self, user, data):
        if user.is_distributor and "distributor_code" in data and not data["distributor_code"]:
            data.pop("distributor_code")  # a distributor always keeps a code
        password = data.pop("password", None)
        for k, v in data.items():
            setattr(user, k, v)
        if password:
            user.set_password(password)
        user.save()
        return user


def _new_distributor_code():
    """A short code customers type to buy through this distributor, e.g. D4K7Q."""
    import secrets

    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O or 1/I to avoid typos
    while True:
        code = "D" + "".join(secrets.choice(alphabet) for _ in range(4))
        if not User.objects.filter(distributor_code=code).exists():
            return code


class DriverSerializer(serializers.ModelSerializer):
    """A delivery account: sees only the orders handed to it, shares its location while delivering."""

    password = serializers.CharField(write_only=True, required=False)
    phone = serializers.CharField(max_length=32, required=False)
    works_for_name = serializers.SerializerMethodField()
    active_deliveries = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ["id", "full_name", "phone", "is_active", "last_login", "password", "works_for", "works_for_name", "active_deliveries"]
        read_only_fields = ["id", "last_login", "works_for_name", "active_deliveries"]
        extra_kwargs = {"works_for": {"required": False, "allow_null": True}}

    def get_works_for_name(self, obj):
        return obj.works_for.display_name if obj.works_for_id else None

    def get_active_deliveries(self, obj):
        return Order.objects.filter(driver=obj, status=Order.SHIPPED).count()

    validate_phone = StaffSerializer.validate_phone
    validate_password = StaffSerializer.validate_password

    def validate_works_for(self, value):
        if value is not None and not value.is_distributor:
            raise serializers.ValidationError("invalid")
        return value

    def validate(self, data):
        if self.instance is None:
            for f in ("full_name", "phone", "password"):
                if not str(data.get(f, "")).strip():
                    raise serializers.ValidationError({f: "required"})
        by = self.context["request"].user
        if not by.is_superuser:
            data.pop("works_for", None)  # a distributor's drivers always work for them
        return data

    def create(self, data):
        by = self.context["request"].user
        works_for = data.get("works_for") if by.is_superuser else by
        return User.objects.create_user(
            phone=data["phone"], password=data["password"], full_name=data["full_name"].strip(),
            is_staff=True, phone_verified=True, is_driver=True, works_for=works_for,
        )

    def update(self, user, data):
        password = data.pop("password", None)
        for k, v in data.items():
            setattr(user, k, v)
        if password:
            user.set_password(password)
        user.save()
        return user
