from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import Address
from apps.core.errors import BusinessError
from apps.notifications import events
from apps.store.delivery import DeliveryArea

from . import pricing, tracking
from .invoice import invoice_response
from .models import Order
from .serializers import OrderDetailSerializer, OrderListSerializer, PlaceOrderSerializer, QuoteRequestSerializer


class QuoteView(APIView):
    """Price a cart. Works for guests too (per-customer coupon limits are checked at checkout)."""

    permission_classes = [permissions.AllowAny]

    def post(self, request):
        s = QuoteRequestSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        quote = pricing.build_quote(
            d["items"], d.get("coupon_code"), request.user,
            delivery_method=d.get("delivery_method"), area_id=d.get("delivery_area_id"),
        )
        return Response(pricing.quote_payload(quote))


class OrderListCreateView(generics.ListAPIView):
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = OrderListSerializer
    throttle_scope = "orders"

    def get_throttles(self):
        return super().get_throttles() if self.request.method == "POST" else []

    def get_queryset(self):
        qs = Order.objects.filter(user=self.request.user).prefetch_related("items").order_by("-created_at", "-id")
        if self.request.query_params.get("status"):
            qs = qs.filter(status=self.request.query_params["status"])
        return qs

    def post(self, request):
        s = PlaceOrderSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        data = s.validated_data
        user = request.user
        contact = {
            "customer_name": data.get("customer_name") or user.full_name,
            "customer_phone": data.get("customer_phone") or user.phone,
            "business_name": data.get("business_name", user.business_name),
            "city": data.get("city", ""),
            "area": data.get("area", ""),
            "street": data.get("street", ""),
            "address_details": data.get("address_details", ""),
            "notes": data.get("notes", ""),
            "distributor": user.distributor if user.distributor_id else None,
            "latitude": data.get("latitude") if data.get("longitude") is not None else None,
            "longitude": data.get("longitude") if data.get("latitude") is not None else None,
        }
        method = data.get("delivery_method", Order.DELIVERY)
        area_id = data.get("delivery_area_id")
        if method == Order.DELIVERY:
            if data.get("address_id"):
                address = get_object_or_404(Address, pk=data["address_id"], user=user)
                contact.update(
                    customer_name=data.get("customer_name") or address.recipient_name,
                    customer_phone=data.get("customer_phone") or address.phone,
                    city=address.city,
                    area=address.area,
                    street=address.street,
                    address_details=address.details,
                    latitude=address.latitude,
                    longitude=address.longitude,
                )
                area_id = address.delivery_area_id
            if not contact["city"]:
                contact["city"] = "دمشق"
            if area_id and not contact["area"]:
                listed = DeliveryArea.objects.filter(pk=area_id).first()
                contact["area"] = listed.name_ar if listed else ""
            pinned = contact.get("latitude") is not None and contact.get("longitude") is not None
            if not contact["area"] or (not contact["address_details"] and not contact["street"] and not pinned):
                raise BusinessError("address_required")
        else:
            contact.update(city="", area="", street="", address_details="", latitude=None, longitude=None)
        if not contact["customer_name"] or not contact["customer_phone"]:
            raise BusinessError("contact_required")
        order, created = pricing.place_order(
            user, data["items"], data.get("coupon_code"), contact, data.get("client_ref", ""),
            delivery_method=method, area_id=area_id, expected_total=data.get("expected_total"),
        )
        if created:
            transaction.on_commit(lambda: events.order_placed(order))
            if contact["business_name"] and not user.business_name:
                user.business_name = contact["business_name"]
                user.save(update_fields=["business_name"])
        return Response(OrderDetailSerializer(order).data, status=status.HTTP_201_CREATED)


class OrderTrackingView(APIView):
    """Light endpoint the store app polls while the order is out for delivery."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, pk):
        order = get_object_or_404(Order, pk=pk, user=request.user)
        return Response({"status": order.status, "tracking": tracking.tracking(order)})


class OrderDetailView(generics.RetrieveAPIView):
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = OrderDetailSerializer

    def get_queryset(self):
        return Order.objects.filter(user=self.request.user).prefetch_related("items", "events")


class OrderInvoiceView(APIView):
    """The customer's own order as a PDF invoice."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, pk):
        return invoice_response(get_object_or_404(Order, pk=pk, user=request.user), request)


class OrderCancelView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        order = get_object_or_404(Order, pk=pk, user=request.user)
        if order.status != Order.PENDING:
            raise BusinessError("cannot_cancel")
        order = pricing.change_status(order, Order.CANCELLED, note="Cancelled by customer", by_admin=False)
        transaction.on_commit(lambda: events.order_cancelled_by_customer(order))
        return Response(OrderDetailSerializer(order).data)
