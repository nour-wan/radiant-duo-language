from django.contrib.auth import password_validation
from django.db import transaction
from rest_framework import serializers

from apps.catalog.models import Category
from apps.store.delivery import DeliveryArea

from .models import BUSINESS_TYPES, Address, PhoneCode, User
from .phone import normalize_phone


class PhoneField(serializers.CharField):
    """Accepts any common way of writing a number and stores it as +963..."""

    def __init__(self, **kwargs):
        kwargs.setdefault("max_length", 32)
        super().__init__(**kwargs)

    def to_internal_value(self, data):
        phone = normalize_phone(super().to_internal_value(data))
        if not phone:
            raise serializers.ValidationError("invalid_phone")
        return phone


CODE = r"^\d{6}$"

PROFILE_FIELDS = ["full_name", "phone", "business_name", "business_type", "area_name", "address"]


class ProfileFieldsMixin(serializers.Serializer):
    """Business profile asked at sign-up (and completed later for Google accounts)."""

    delivery_area = serializers.PrimaryKeyRelatedField(
        queryset=DeliveryArea.objects.filter(is_active=True), required=False, allow_null=True
    )
    interests = serializers.PrimaryKeyRelatedField(queryset=Category.objects.filter(is_active=True), many=True, required=False)

    def validate(self, data):
        data = super().validate(data)
        area = data.get("delivery_area")
        if area is not None:
            data["area_name"] = area.name_ar
        return data


class UserSerializer(ProfileFieldsMixin, serializers.ModelSerializer):
    has_password = serializers.SerializerMethodField()
    profile_complete = serializers.SerializerMethodField()
    show_statement = serializers.SerializerMethodField()
    is_owner = serializers.BooleanField(source="is_superuser", read_only=True)

    class Meta:
        model = User
        fields = [
            "id", "email", "full_name", "phone", "phone_verified", "business_name", "business_type", "delivery_area",
            "area_name", "address", "interests", "language", "is_staff", "has_password", "profile_complete",
            "credit_enabled", "show_statement", "is_owner", "date_joined",
        ]
        # The phone changes only through a WhatsApp code (me/phone/)
        read_only_fields = [
            "id", "email", "phone", "phone_verified", "is_staff", "has_password", "profile_complete", "credit_enabled",
            "date_joined",
        ]

    def get_show_statement(self, obj):
        """The account statement is shown once credit is enabled, or while there is something on the account."""
        if obj.credit_enabled:
            return True
        from apps.ledger.services import balance

        return balance(obj) != 0

    def get_has_password(self, obj):
        return obj.has_usable_password()

    def get_profile_complete(self, obj):
        return all(getattr(obj, f) for f in PROFILE_FIELDS)


class RegisterSerializer(ProfileFieldsMixin, serializers.Serializer):
    phone = PhoneField()
    code = serializers.RegexField(CODE)
    password = serializers.CharField(write_only=True)
    full_name = serializers.CharField(max_length=150)
    business_name = serializers.CharField(max_length=150)
    business_type = serializers.ChoiceField(choices=[c for c, _ in BUSINESS_TYPES])
    area_name = serializers.CharField(max_length=100, required=False, allow_blank=True)
    address = serializers.CharField(max_length=300)
    language = serializers.ChoiceField(choices=["ar", "en"], default="ar")

    def validate_phone(self, value):
        if User.objects.filter(phone=value).exists():
            raise serializers.ValidationError("phone_taken")
        return value

    def validate_password(self, value):
        password_validation.validate_password(value)
        return value

    def validate(self, data):
        data = super().validate(data)
        if not data.get("area_name", "").strip():
            raise serializers.ValidationError({"area_name": "required"})
        from .services import use_phone_code

        # Outside create()'s transaction so a wrong guess is still counted
        use_phone_code(data["phone"], PhoneCode.REGISTER, data.pop("code"))
        return data

    @transaction.atomic
    def create(self, data):
        interests = data.pop("interests", [])
        user = User.objects.create_user(phone_verified=True, **data)
        user.interests.set(interests)
        create_default_address(user)
        return user


def create_default_address(user):
    """The sign-up address becomes the customer's first (default) delivery address."""
    if user.address and not user.addresses.exists():
        Address.objects.create(
            user=user,
            label=user.business_name,
            recipient_name=user.full_name,
            phone=user.phone,
            delivery_area=user.delivery_area,
            area=user.area_name,
            details=user.address,
            is_default=True,
        )


class LoginSerializer(serializers.Serializer):
    """Customers sign in with their phone; email still works (admins, older app versions)."""

    phone = PhoneField(required=False)
    email = serializers.EmailField(required=False)
    password = serializers.CharField()

    def validate(self, data):
        if not data.get("phone") and not data.get("email"):
            raise serializers.ValidationError({"phone": "required"})
        return data


class PhoneCodeRequestSerializer(serializers.Serializer):
    phone = PhoneField()
    purpose = serializers.ChoiceField(choices=[PhoneCode.REGISTER, PhoneCode.RESET, PhoneCode.CHANGE])
    language = serializers.ChoiceField(choices=["ar", "en"], default="ar")


class ChangePhoneSerializer(serializers.Serializer):
    phone = PhoneField()
    code = serializers.RegexField(CODE)


class GoogleLoginSerializer(serializers.Serializer):
    id_token = serializers.CharField()
    language = serializers.ChoiceField(choices=["ar", "en"], default="ar")


class PasswordResetRequestSerializer(serializers.Serializer):
    email = serializers.EmailField()


class PasswordResetConfirmSerializer(serializers.Serializer):
    phone = PhoneField(required=False)
    email = serializers.EmailField(required=False)
    code = serializers.RegexField(CODE)
    new_password = serializers.CharField()

    def validate(self, data):
        if not data.get("phone") and not data.get("email"):
            raise serializers.ValidationError({"phone": "required"})
        return data

    def validate_new_password(self, value):
        password_validation.validate_password(value)
        return value


class ChangePasswordSerializer(serializers.Serializer):
    current_password = serializers.CharField(required=False, allow_blank=True)
    new_password = serializers.CharField()

    def validate_new_password(self, value):
        password_validation.validate_password(value)
        return value


class DeleteAccountSerializer(serializers.Serializer):
    password = serializers.CharField(required=False, allow_blank=True)
    confirm = serializers.BooleanField()


class AddressSerializer(serializers.ModelSerializer):
    delivery_area = serializers.PrimaryKeyRelatedField(
        queryset=DeliveryArea.objects.filter(is_active=True), required=False, allow_null=True
    )

    class Meta:
        model = Address
        fields = ["id", "label", "recipient_name", "phone", "city", "delivery_area", "area", "street", "details", "is_default"]

    def validate(self, data):
        area = data.get("delivery_area")
        if area is not None:
            data["area"] = area.name_ar
        return data
