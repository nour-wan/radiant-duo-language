from rest_framework import serializers

from apps.ledger import services as ledger

from .models import Order, OrderEvent, OrderItem


class OrderItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = OrderItem
        fields = [
            "id", "product_id", "variant_id", "product_name_ar", "product_name_en", "variant_label_ar",
            "variant_label_en", "image", "unit_price", "quantity", "line_total",
        ]


class OrderEventSerializer(serializers.ModelSerializer):
    class Meta:
        model = OrderEvent
        fields = ["status", "note", "created_at"]


class OrderListSerializer(serializers.ModelSerializer):
    item_count = serializers.IntegerField(source="items.count", read_only=True)

    class Meta:
        model = Order
        fields = ["id", "number", "status", "delivery_method", "total", "item_count", "created_at"]


class OrderDetailSerializer(serializers.ModelSerializer):
    items = OrderItemSerializer(many=True, read_only=True)
    events = OrderEventSerializer(many=True, read_only=True)
    can_cancel = serializers.SerializerMethodField()
    paid_amount = serializers.SerializerMethodField()
    remaining = serializers.SerializerMethodField()

    class Meta:
        model = Order
        fields = [
            "id", "number", "status", "customer_name", "customer_phone", "business_name", "city", "area", "street",
            "address_details", "notes", "payment_method", "delivery_method", "delivery_zone", "delivery_fee",
            "delivery_currency", "coupon_code", "subtotal", "discount", "app_discount_percent", "app_discount", "total",
            "items", "events", "can_cancel", "paid_amount", "remaining", "created_at", "updated_at",
        ]

    def get_can_cancel(self, obj):
        return obj.status == Order.PENDING

    def get_paid_amount(self, obj):
        return str(ledger.order_paid(obj))

    def get_remaining(self, obj):
        """Unpaid part of this order once delivered (payments recorded against the order)."""
        if obj.status != Order.DELIVERED:
            return None
        return str(max(ledger.ZERO, obj.total - ledger.order_paid(obj)))


class QuoteRequestSerializer(serializers.Serializer):
    items = serializers.ListField(child=serializers.DictField(), allow_empty=False)
    coupon_code = serializers.CharField(required=False, allow_blank=True, max_length=40)
    delivery_method = serializers.ChoiceField(choices=[Order.PICKUP, Order.DELIVERY], required=False)
    delivery_area_id = serializers.IntegerField(required=False, allow_null=True)


class PlaceOrderSerializer(QuoteRequestSerializer):
    client_ref = serializers.CharField(required=False, allow_blank=True, max_length=64)
    address_id = serializers.IntegerField(required=False)
    customer_name = serializers.CharField(max_length=150, required=False, allow_blank=True)
    customer_phone = serializers.CharField(max_length=32, required=False, allow_blank=True)
    business_name = serializers.CharField(max_length=150, required=False, allow_blank=True)
    city = serializers.CharField(max_length=80, required=False, allow_blank=True)
    area = serializers.CharField(max_length=120, required=False, allow_blank=True)
    street = serializers.CharField(max_length=200, required=False, allow_blank=True)
    address_details = serializers.CharField(max_length=300, required=False, allow_blank=True)
    notes = serializers.CharField(max_length=500, required=False, allow_blank=True)
