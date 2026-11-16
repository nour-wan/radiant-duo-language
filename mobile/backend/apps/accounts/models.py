from decimal import Decimal
from django.core.validators import MinValueValidator
from django.contrib.auth.base_user import BaseUserManager
from django.contrib.auth.models import AbstractUser
from django.db import models
from django.utils import timezone


class UserManager(BaseUserManager):
    use_in_migrations = True

    def _create_user(self, email, password, **extra):
        if not email and not extra.get("phone"):
            raise ValueError("Email or phone is required")
        user = self.model(email=self.normalize_email(email).lower() if email else None, **extra)
        if password:
            user.set_password(password)
        else:
            user.set_unusable_password()
        user.save(using=self._db)
        return user

    def create_user(self, email=None, password=None, **extra):
        extra.setdefault("is_staff", False)
        extra.setdefault("is_superuser", False)
        return self._create_user(email, password, **extra)

    def create_superuser(self, email, password=None, **extra):
        extra["is_staff"] = True
        extra["is_superuser"] = True
        return self._create_user(email, password, **extra)


BUSINESS_TYPES = [
    ("cafe", "Café"),
    ("restaurant", "Restaurant"),
    ("cafeteria", "Cafeteria"),
    ("bakery", "Bakery"),
    ("sweets", "Sweets shop"),
    ("factory", "Factory / workshop"),
    ("ice_cream", "Ice cream shop"),
    ("hotel", "Hotel"),
    ("market", "Supermarket / grocery"),
    ("other", "Other"),
]


class User(AbstractUser):
    """Customer or store admin. Admins are users with is_staff=True."""

    username = None
    first_name = None
    last_name = None
    # Staff sign in with email; customers sign in with their phone number (email is optional)
    email = models.EmailField(unique=True, null=True, blank=True)
    full_name = models.CharField(max_length=150, blank=True)
    phone = models.CharField(max_length=32, blank=True, db_index=True)  # +9639XXXXXXXX
    phone_verified = models.BooleanField(default=False)
    business_name = models.CharField(max_length=150, blank=True)
    business_type = models.CharField(max_length=20, choices=BUSINESS_TYPES, blank=True)
    delivery_area = models.ForeignKey("store.DeliveryArea", on_delete=models.SET_NULL, null=True, blank=True, related_name="+")
    area_name = models.CharField(max_length=100, blank=True)  # always filled (listed area name or free text)
    address = models.CharField(max_length=300, blank=True)
    interests = models.ManyToManyField("catalog.Category", blank=True, related_name="interested_customers")
    language = models.CharField(max_length=2, choices=[("ar", "Arabic"), ("en", "English")], default="ar")
    google_sub = models.CharField(max_length=64, unique=True, null=True, blank=True)
    notifications_seen_at = models.DateTimeField(null=True, blank=True)
    admin_inbox_seen_at = models.DateTimeField(null=True, blank=True)
    # Max unpaid amount (USD) for this customer; empty = use the store default
    credit_limit = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True, validators=[MinValueValidator(Decimal("0"))])
    # Buying on credit is off until an admin turns it on for this customer; until then the
    # customer sees nothing about debt or limits.
    credit_enabled = models.BooleanField(default=False)

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = []
    objects = UserManager()

    def __str__(self):
        return self.email or self.phone or f"#{self.pk}"


class Address(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="addresses")
    label = models.CharField(max_length=60, blank=True)
    recipient_name = models.CharField(max_length=150)
    phone = models.CharField(max_length=32)
    city = models.CharField(max_length=80, default="دمشق")
    delivery_area = models.ForeignKey("store.DeliveryArea", on_delete=models.SET_NULL, null=True, blank=True, related_name="+")
    area = models.CharField(max_length=120, blank=True)
    street = models.CharField(max_length=200, blank=True)
    details = models.CharField(max_length=300, blank=True)
    is_default = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-is_default", "-created_at"]


class PasswordResetCode(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="reset_codes")
    code_hash = models.CharField(max_length=128)
    expires_at = models.DateTimeField()
    attempts = models.PositiveSmallIntegerField(default=0)
    used = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    MAX_ATTEMPTS = 5

    @property
    def is_valid(self):
        return not self.used and self.attempts < self.MAX_ATTEMPTS and self.expires_at > timezone.now()


class PhoneCode(models.Model):
    """A one-time code sent on WhatsApp to prove the customer owns a phone number."""

    REGISTER, RESET, CHANGE = "register", "reset", "change"
    PURPOSES = [(REGISTER, "Sign up"), (RESET, "Password reset"), (CHANGE, "Change phone")]
    MAX_ATTEMPTS = 5

    phone = models.CharField(max_length=32, db_index=True)
    purpose = models.CharField(max_length=10, choices=PURPOSES)
    user = models.ForeignKey(User, on_delete=models.CASCADE, null=True, blank=True, related_name="phone_codes")
    code_hash = models.CharField(max_length=128)
    channel = models.CharField(max_length=12, default="whatsapp")
    expires_at = models.DateTimeField()
    attempts = models.PositiveSmallIntegerField(default=0)
    used = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at", "-id"]

    @property
    def is_valid(self):
        return not self.used and self.attempts < self.MAX_ATTEMPTS and self.expires_at > timezone.now()


class WhatsAppConfig(models.Model):
    """WhatsApp Cloud API account that sends verification codes, editable from the admin app.

    Kept apart from StoreSettings on purpose: store settings are public, this holds a secret token.
    """

    phone_number_id = models.CharField(max_length=40, blank=True)
    access_token = models.TextField(blank=True)
    otp_template = models.CharField(max_length=100, blank=True)
    template_lang = models.CharField(max_length=10, default="ar")
    updated_at = models.DateTimeField(auto_now=True)

    def save(self, *args, **kwargs):
        self.pk = 1
        super().save(*args, **kwargs)

    @classmethod
    def load(cls):
        obj, _ = cls.objects.get_or_create(pk=1)
        return obj
