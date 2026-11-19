"""Policy wording after the switch to phone sign-in with WhatsApp codes (Google sign-in removed).

Replaces only the affected sentences, so any other edits the owner made to the pages are kept.
Safe to run more than once.
"""

from django.core.management.base import BaseCommand

from apps.store.models import LegalPage

REPLACEMENTS = {
    "privacy": [
        ("body_ar", "- بيانات الحساب: الاسم، البريد الإلكتروني، رقم الهاتف، اسم المنشأة",
         "- بيانات الحساب: الاسم، رقم الهاتف (نتحقق منه برمز يصلك على واتساب)، اسم المنشأة"),
        ("body_ar", "- عند الدخول عبر Google: الاسم والبريد الإلكتروني فقط كما تزودنا بهما Google.\n", ""),
        ("body_ar", "، وخدمة Google Sign-In فقط إذا اخترت الدخول بحساب Google.",
         "، وخدمة WhatsApp Business من Meta فقط لإرسال رمز التحقق إلى رقمك."),
        ("body_en", "- Account data: name, email address, phone number, business name",
         "- Account data: name, phone number (verified with a code sent to you on WhatsApp), business name"),
        ("body_en", "- If you sign in with Google: only the name and email address Google shares with us.\n", ""),
        ("body_en", ", and Google Sign-In only if you choose to sign in with Google.",
         ", and Meta's WhatsApp Business service only to send the verification code to your number."),
    ],
    "account-deletion": [
        ("body_ar", "أرسل طلب حذف من بريدك المسجّل إلى info@alasfoodstuff.com بعنوان «حذف الحساب»",
         "أرسل طلب حذف من رقمك المسجّل على واتساب +963980387705، أو إلى info@alasfoodstuff.com، بعنوان «حذف الحساب»"),
        ("body_en", 'Email info@alasfoodstuff.com from your registered address with the subject "Delete account"',
         'Send "Delete account" on WhatsApp from your registered number to +963980387705, or email info@alasfoodstuff.com'),
    ],
}


class Command(BaseCommand):
    help = "Update the privacy and account-deletion pages for phone sign-in"

    def handle(self, *args, **options):
        for slug, changes in REPLACEMENTS.items():
            page = LegalPage.objects.filter(slug=slug).first()
            if page is None:
                continue
            changed = False
            for field, old, new in changes:
                text = getattr(page, field)
                if old in text:
                    setattr(page, field, text.replace(old, new))
                    changed = True
            if changed:
                page.save()
            self.stdout.write(f"{slug}: {'updated' if changed else 'already up to date'}")
