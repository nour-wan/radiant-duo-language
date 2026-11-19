from django.contrib.auth import authenticate
from rest_framework import generics, permissions, status, viewsets
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenRefreshView

from apps.core.errors import BusinessError

from . import services
from .models import Address
from .serializers import (
    AddressSerializer,
    ChangePasswordSerializer,
    ChangePhoneSerializer,
    PhoneCodeRequestSerializer,
    DeleteAccountSerializer,
    GoogleLoginSerializer,
    LoginSerializer,
    PasswordResetConfirmSerializer,
    PasswordResetRequestSerializer,
    RegisterSerializer,
    UserSerializer,
    create_default_address,
)


def auth_response(user, code=status.HTTP_200_OK):
    return Response({"user": UserSerializer(user).data, "tokens": services.issue_tokens(user)}, status=code)


class RegisterView(APIView):
    permission_classes = [permissions.AllowAny]
    throttle_scope = "auth"

    def post(self, request):
        s = RegisterSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        return auth_response(s.save(), status.HTTP_201_CREATED)


class LoginView(APIView):
    permission_classes = [permissions.AllowAny]
    throttle_scope = "auth"
    require_staff = False

    def post(self, request):
        s = LoginSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        if d.get("phone"):
            user = services.login_with_phone(d["phone"], d["password"], staff_only=self.require_staff)
        elif d.get("email"):
            user = authenticate(request, email=d["email"].lower(), password=d["password"])
        else:
            user = None
        if not user or (self.require_staff and not user.is_staff):
            if self.require_staff:
                from apps.adminapi.audit import record

                record(request, None, ("محاولة دخول فاشلة", "Failed sign-in"), d.get("phone") or d.get("email") or "")
            # Same message as wrong password: do not reveal that the customer account exists.
            raise BusinessError("invalid_credentials")
        if self.require_staff:
            from apps.adminapi.audit import record

            record(request, user, ("تسجيل دخول", "Signed in"))
        return auth_response(user)


class AdminLoginView(LoginView):
    require_staff = True


class GoogleLoginView(APIView):
    permission_classes = [permissions.AllowAny]
    throttle_scope = "auth"

    def post(self, request):
        s = GoogleLoginSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        claims = services.verify_google_token(s.validated_data["id_token"])
        user = services.google_user(claims, s.validated_data["language"])
        if not user.is_active:
            raise BusinessError("invalid_credentials")
        return auth_response(user)


class LogoutView(APIView):
    def post(self, request):
        try:
            RefreshToken(request.data.get("refresh", "")).blacklist()
        except TokenError:
            pass
        token = request.data.get("device_token")
        if token:
            from apps.notifications.models import DeviceToken

            DeviceToken.objects.filter(token=token).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class PasswordResetRequestView(APIView):
    permission_classes = [permissions.AllowAny]
    throttle_scope = "password_reset"

    def post(self, request):
        s = PasswordResetRequestSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        services.send_reset_code(s.validated_data["email"])
        return Response({"detail": "sent"})


class PasswordResetConfirmView(APIView):
    permission_classes = [permissions.AllowAny]
    throttle_scope = "auth"

    def post(self, request):
        s = PasswordResetConfirmSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        if d.get("phone"):
            services.reset_password_with_phone(d["phone"], d["code"], d["new_password"])
        else:
            services.reset_password(d["email"], d["code"], d["new_password"])
        return Response({"detail": "password_changed"})


class PhoneCodeView(APIView):
    """Sends a 6-digit code on WhatsApp (sign-up, password reset, or changing the number)."""

    permission_classes = [permissions.AllowAny]
    throttle_scope = "phone_code"

    def post(self, request):
        s = PhoneCodeRequestSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        channel = services.request_phone_code(d["phone"], d["purpose"], d["language"], user=request.user)
        # A reset for an unknown number answers like a sent code (no account enumeration)
        return Response({"phone": d["phone"], "channel": channel or "whatsapp"})


class ChangePhoneView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    throttle_scope = "auth"

    def post(self, request):
        s = ChangePhoneSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        user = services.change_phone(request.user, s.validated_data["phone"], s.validated_data["code"])
        return Response(UserSerializer(user).data)


class MeView(generics.RetrieveUpdateAPIView):
    serializer_class = UserSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_object(self):
        return self.request.user

    def perform_update(self, serializer):
        create_default_address(serializer.save())


class ChangePasswordView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    throttle_scope = "auth"

    def post(self, request):
        s = ChangePasswordSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        user = request.user
        if user.has_usable_password() and not user.check_password(s.validated_data.get("current_password", "")):
            raise BusinessError("wrong_password")
        user.set_password(s.validated_data["new_password"])
        user.save(update_fields=["password"])
        return auth_response(user)


class DeleteAccountView(APIView):
    """Google Play / App Store requirement: users can delete their account in-app."""

    permission_classes = [permissions.IsAuthenticated]
    throttle_scope = "auth"

    def post(self, request):
        s = DeleteAccountSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        user = request.user
        if not s.validated_data["confirm"]:
            raise BusinessError("confirmation_required")
        if user.has_usable_password() and not user.check_password(s.validated_data.get("password", "")):
            raise BusinessError("wrong_password")
        if user.is_staff:
            raise BusinessError("admin_cannot_self_delete")
        # An open account (debt or credit) must be settled with the store first; the entries are kept for accounting.
        from apps.ledger.services import balance

        if balance(user) != 0:
            raise BusinessError("account_has_balance")
        services.delete_account(user)
        return Response(status=status.HTTP_204_NO_CONTENT)


class AddressViewSet(viewsets.ModelViewSet):
    serializer_class = AddressSerializer
    permission_classes = [permissions.IsAuthenticated]
    pagination_class = None

    def get_queryset(self):
        return Address.objects.filter(user=self.request.user)

    def _sync_default(self, address):
        qs = self.get_queryset()
        if address.is_default:
            qs.exclude(pk=address.pk).update(is_default=False)
        elif not qs.filter(is_default=True).exists():
            address.is_default = True
            address.save(update_fields=["is_default"])

    def perform_create(self, serializer):
        address = serializer.save(user=self.request.user)
        self._sync_default(address)
        pin_open_orders(address)

    def perform_update(self, serializer):
        address = serializer.save()
        self._sync_default(address)
        pin_open_orders(address)


def pin_open_orders(address):
    """Orders still on their way to this address (placed before it was pinned) get its map pin too,
    so the driver and the delivery estimate work for them."""
    if address.latitude is None or address.longitude is None:
        return
    from apps.orders.models import Order

    Order.objects.filter(
        user=address.user, delivery_method=Order.DELIVERY, latitude__isnull=True,
        status__in=[Order.PENDING, Order.CONFIRMED, Order.SHIPPED],
        area=address.area, address_details=address.details,
    ).update(latitude=address.latitude, longitude=address.longitude)


class RefreshView(TokenRefreshView):
    """Token refresh that also marks the account as active now (shown to the owner as last activity)."""

    def post(self, request, *args, **kwargs):
        response = super().post(request, *args, **kwargs)
        if response.status_code == 200 and response.data.get("refresh"):
            from django.utils import timezone

            from .models import User

            try:
                user_id = RefreshToken(response.data["refresh"]).get("user_id")
                User.objects.filter(pk=user_id).update(last_login=timezone.now())
            except TokenError:
                pass
        return response
