import logging
import secrets
from datetime import timedelta

from django.conf import settings
from django.contrib.auth.hashers import check_password, make_password
from django.core.mail import send_mail
from django.db import transaction
from django.utils import timezone
from rest_framework_simplejwt.tokens import RefreshToken

from apps.core.errors import BusinessError

from .models import PasswordResetCode, PhoneCode, User
from . import whatsapp

log = logging.getLogger(__name__)


def issue_tokens(user):
    User.objects.filter(pk=user.pk).update(last_login=timezone.now())
    refresh = RefreshToken.for_user(user)
    return {"access": str(refresh.access_token), "refresh": str(refresh)}


def verify_google_token(raw_token):
    """Verify a Google ID token server-side and return its claims."""
    if not settings.GOOGLE_CLIENT_IDS:
        raise BusinessError("google_not_configured")
    from google.auth.transport import requests as google_requests
    from google.oauth2 import id_token

    try:
        claims = id_token.verify_oauth2_token(raw_token, google_requests.Request())
    except ValueError:
        raise BusinessError("google_token_invalid")
    if claims.get("aud") not in settings.GOOGLE_CLIENT_IDS and claims.get("azp") not in settings.GOOGLE_CLIENT_IDS:
        raise BusinessError("google_token_invalid")
    if not claims.get("email") or not claims.get("email_verified"):
        raise BusinessError("google_email_unverified")
    return claims


def google_user(claims, language):
    email = claims["email"].lower()
    user = User.objects.filter(google_sub=claims["sub"]).first() or User.objects.filter(email=email).first()
    if user is None:
        user = User.objects.create_user(email=email, full_name=claims.get("name", ""), language=language)
    if not user.google_sub:
        user.google_sub = claims["sub"]
        user.save(update_fields=["google_sub"])
    return user


def send_reset_code(email):
    """Always behaves the same whether the email exists or not (no account enumeration)."""
    user = User.objects.filter(email=email.lower(), is_active=True).first()
    if not user:
        return
    code = f"{secrets.randbelow(1_000_000):06d}"
    PasswordResetCode.objects.filter(user=user, used=False).update(used=True)
    PasswordResetCode.objects.create(
        user=user, code_hash=make_password(code), expires_at=timezone.now() + timedelta(minutes=15)
    )
    if user.language == "ar":
        subject = "رمز استعادة كلمة المرور - آلاس"
        body = f"رمز استعادة كلمة المرور الخاص بك هو: {code}\nصالح لمدة 15 دقيقة. إذا لم تطلب ذلك فتجاهل هذه الرسالة."
    else:
        subject = "Your Alas Foodstuff password reset code"
        body = f"Your password reset code is: {code}\nIt is valid for 15 minutes. If you did not request it, ignore this email."
    try:
        send_mail(subject, body, settings.DEFAULT_FROM_EMAIL, [user.email])
    except Exception:
        log.exception("Could not send password reset email")


CODE_TTL = timedelta(minutes=30)  # long enough for an admin to forward it by hand
CODE_GAP = timedelta(seconds=60)
CODES_PER_HOUR = 5


def customers_with_phone(phone):
    return User.objects.filter(phone=phone, is_active=True).order_by("-phone_verified", "-last_login", "-id")


def login_with_phone(phone, password, staff_only=False):
    """Old accounts may share a number; the one whose password matches signs in."""
    users = customers_with_phone(phone)
    if staff_only:
        users = users.filter(is_staff=True)
    for user in users:
        if user.check_password(password):
            return user
    return None


def request_phone_code(phone, purpose, language="ar", user=None):
    """Creates a code and sends it on WhatsApp. Returns the channel ('whatsapp' or 'manual'), or None
    for a password reset of an unknown number (the response looks the same: no account enumeration)."""
    if purpose == PhoneCode.REGISTER and User.objects.filter(phone=phone).exists():
        raise BusinessError("phone_taken")
    if purpose == PhoneCode.CHANGE:
        if user is None or not user.is_authenticated:
            raise BusinessError("not_authenticated")
        if User.objects.filter(phone=phone).exclude(pk=user.pk).exists():
            raise BusinessError("phone_taken")
    if purpose == PhoneCode.RESET:
        user = customers_with_phone(phone).first()
        if user is None:
            return None

    now = timezone.now()
    recent = PhoneCode.objects.filter(phone=phone, created_at__gte=now - timedelta(hours=1))
    last = recent.first()
    if last and last.created_at > now - CODE_GAP:
        wait = int((last.created_at + CODE_GAP - now).total_seconds()) + 1
        raise BusinessError("code_too_soon", seconds=wait)
    if recent.count() >= CODES_PER_HOUR:
        raise BusinessError("too_many_codes")

    code = f"{secrets.randbelow(1_000_000):06d}"
    PhoneCode.objects.filter(phone=phone, purpose=purpose, used=False).update(used=True)
    entry = PhoneCode.objects.create(
        phone=phone, purpose=purpose, user=user if user and user.is_authenticated else None,
        code_hash=make_password(code), expires_at=now + CODE_TTL,
    )
    entry.channel = whatsapp.send_code(phone, code, language, purpose)
    entry.save(update_fields=["channel"])
    return entry.channel


def use_phone_code(phone, purpose, code, user=None):
    """Checks the latest code for this number and uses it up; wrong guesses are counted."""
    qs = PhoneCode.objects.filter(phone=phone, purpose=purpose, used=False)
    if user is not None:
        qs = qs.filter(user=user)
    entry = qs.first()
    if not entry or not entry.is_valid:
        raise BusinessError("code_invalid")
    if not check_password(code, entry.code_hash):
        PhoneCode.objects.filter(pk=entry.pk).update(attempts=entry.attempts + 1)
        raise BusinessError("code_invalid")
    entry.used = True
    entry.save(update_fields=["used"])
    return entry


def reset_password_with_phone(phone, code, new_password):
    user = customers_with_phone(phone).first()
    if user is None:
        raise BusinessError("code_invalid")
    use_phone_code(phone, PhoneCode.RESET, code)
    user.set_password(new_password)
    user.phone_verified = True  # the code proved the number
    user.save(update_fields=["password", "phone_verified"])
    return user


def change_phone(user, phone, code):
    use_phone_code(phone, PhoneCode.CHANGE, code, user=user)
    if User.objects.filter(phone=phone).exclude(pk=user.pk).exists():
        raise BusinessError("phone_taken")
    user.phone = phone
    user.phone_verified = True
    user.save(update_fields=["phone", "phone_verified"])
    return user


def reset_password(email, code, new_password):
    user = User.objects.filter(email=email.lower(), is_active=True).first()
    entry = user and user.reset_codes.filter(used=False).order_by("-created_at").first()
    if not entry or not entry.is_valid:
        raise BusinessError("reset_code_invalid")
    if not check_password(code, entry.code_hash):
        entry.attempts += 1
        entry.save(update_fields=["attempts"])
        raise BusinessError("reset_code_invalid")
    entry.used = True
    entry.save(update_fields=["used"])
    user.set_password(new_password)
    user.save(update_fields=["password"])


@transaction.atomic
def delete_account(user):
    """Remove all personal data. Orders stay for accounting, without personal details."""
    from apps.orders.models import Order

    Order.objects.filter(user=user).update(
        user=None,
        customer_name="",
        customer_phone="",
        customer_email="",
        business_name="",
        city="",
        area="",
        street="",
        address_details="",
        notes="",
        customer_deleted=True,
    )
    user.delete()  # cascades: addresses, favorites, device tokens, personal notifications, reset codes
