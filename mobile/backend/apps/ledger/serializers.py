from decimal import Decimal

from rest_framework import serializers

from .models import LedgerEntry


class LedgerEntrySerializer(serializers.ModelSerializer):
    balance_after = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)
    order_number = serializers.CharField(source="order.number", read_only=True, default=None)

    class Meta:
        model = LedgerEntry
        fields = ["id", "kind", "amount", "balance_after", "note", "order_id", "order_number", "created_at"]


class AdminLedgerEntrySerializer(LedgerEntrySerializer):
    created_by = serializers.CharField(source="created_by.email", read_only=True, default=None)

    class Meta(LedgerEntrySerializer.Meta):
        fields = LedgerEntrySerializer.Meta.fields + ["created_by"]


class PaymentSerializer(serializers.Serializer):
    amount = serializers.DecimalField(max_digits=12, decimal_places=2, min_value=Decimal("0.01"))
    order_id = serializers.IntegerField(required=False, allow_null=True)
    note = serializers.CharField(max_length=300, required=False, allow_blank=True, default="")


class AdjustmentSerializer(serializers.Serializer):
    amount = serializers.DecimalField(max_digits=12, decimal_places=2)
    note = serializers.CharField(max_length=300)


def summary_payload(info):
    return {k: (v if v is None or isinstance(v, bool) else str(v)) for k, v in info.items()}
