from decimal import Decimal

from django.db import transaction
from rest_framework import serializers

from apps.accounts.models import User
from apps.catalog.models import Category, Product, Variant
from apps.catalog.serializers import ImageSerializer
from apps.core.images import absolute_media_url
from apps.notifications.models import AdminNotification, Notification
from apps.orders.models import Order
from apps.orders.serializers import OrderDetailSerializer
from apps.promotions.models import Banner, Coupon
from apps.store.delivery import DeliveryArea, DeliveryZone
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
    id = serializers.IntegerField(required=False)

    class Meta:
        model = Variant
        fields = [
            "id", "label_ar", "label_en", "unit", "unit_quantity", "sku", "price", "discount_price", "stock",
            "min_order_qty", "is_active", "sort_order",
        ]

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
            "item_count", "created_at",
        ]


class AdminOrderEventSerializer(serializers.Serializer):
    status = serializers.CharField()
    note = serializers.CharField()
    created_at = serializers.DateTimeField()
    by_name = serializers.SerializerMethodField()

    def get_by_name(self, obj):
        return obj.by.display_name if obj.by_id else None


class AdminOrderDetailSerializer(OrderDetailSerializer):
    user_id = serializers.IntegerField(read_only=True)
    allowed_statuses = serializers.SerializerMethodField()
    events = AdminOrderEventSerializer(many=True, read_only=True)
    payments = serializers.SerializerMethodField()

    class Meta(OrderDetailSerializer.Meta):
        fields = OrderDetailSerializer.Meta.fields + [
            "customer_email", "user_id", "admin_note", "customer_deleted", "allowed_statuses", "payments",
        ]

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
    # Cash received on delivery (recorded as a payment on the customer's account)
    paid_amount = serializers.DecimalField(max_digits=12, decimal_places=2, required=False, allow_null=True, min_value=Decimal("0"))


class AdminCustomerSerializer(serializers.ModelSerializer):
    order_count = serializers.IntegerField(read_only=True, default=0)
    total_spent = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True, default=0)
    last_order_at = serializers.DateTimeField(read_only=True, default=None)
    balance = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True, default=0)
    interests = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            "id", "email", "full_name", "phone", "phone_verified", "business_name", "business_type", "area_name",
            "address", "interests", "language", "is_active", "date_joined", "last_login", "order_count", "total_spent",
            "last_order_at", "balance", "credit_enabled", "credit_limit",
        ]
        read_only_fields = [
            "email", "full_name", "phone", "phone_verified", "business_name", "business_type", "area_name", "address",
            "language", "date_joined", "last_login",
        ]

    def get_interests(self, obj):
        return [{"id": c.id, "name_ar": c.name_ar, "name_en": c.name_en} for c in obj.interests.all()]


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
        exclude = ["id"]


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

    class Meta:
        model = User
        fields = ["id", "full_name", "phone", "email", "is_owner", "is_active", "last_login", "date_joined", "password"]
        read_only_fields = ["id", "email", "is_owner", "last_login", "date_joined"]

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
        return data

    def create(self, data):
        return User.objects.create_user(
            phone=data["phone"], password=data["password"], full_name=data["full_name"].strip(),
            is_staff=True, phone_verified=True,
        )

    def update(self, user, data):
        password = data.pop("password", None)
        for k, v in data.items():
            setattr(user, k, v)
        if password:
            user.set_password(password)
        user.save()
        return user
