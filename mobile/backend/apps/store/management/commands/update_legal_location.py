"""Policy wording for the delivery map: the customer's optional map pin and the driver's live position.

Replaces only the affected sentences, so any other edits the owner made to the page are kept.
Safe to run more than once.
"""

from django.core.management.base import BaseCommand

from apps.store.models import LegalPage

AR_NO_LOCATION = "لا نجمع بيانات الموقع الجغرافي، ولا بيانات بطاقات الدفع، ولا جهات الاتصال، ولا الصور من جهازك."
AR_LOCATION = (
    "- موقع التسليم على الخريطة: إذا اخترت تحديد مكانك على الخريطة (اختياري)، نحفظ هذا الموقع مع العنوان ليصل إليك السائق. "
    "لا نتابع موقعك، ونطلب الوصول لموقع جهازك فقط عندما تضغط «موقعي الحالي».\n"
    "- أثناء توصيل طلبك نعرض لك موقع السائق على الخريطة والوقت التقريبي للوصول، ويتوقف ذلك عند تسليم الطلب.\n"
    "لا نجمع بيانات بطاقات الدفع، ولا جهات الاتصال، ولا الصور من جهازك."
)
EN_NO_LOCATION = "We do not collect location, payment card data, contacts or photos from your device."
EN_LOCATION = (
    "- Delivery location on the map: if you choose to pin your place on the map (optional), we save it with the address so the "
    "driver can find you. We do not track you; we only use your device's location when you tap \"My location\".\n"
    "- While your order is out for delivery, we show you the driver's position on a map and an estimated arrival time; "
    "this stops once the order is delivered.\n"
    "We do not collect payment card data, contacts or photos from your device."
)
AR_SHARING = "وخدمة WhatsApp Business من Meta فقط لإرسال رمز التحقق إلى رقمك."
AR_SHARING_MAPS = AR_SHARING + " وتُعرض الخرائط من OpenStreetMap، ولا نرسل إليها بياناتك."
EN_SHARING = "and Meta's WhatsApp Business service only to send the verification code to your number."
EN_SHARING_MAPS = EN_SHARING + " Maps are shown from OpenStreetMap; we do not send your data to it."

REPLACEMENTS = {
    "privacy": [
        ("body_ar", AR_NO_LOCATION, AR_LOCATION),
        ("body_en", EN_NO_LOCATION, EN_LOCATION),
        ("body_ar", AR_SHARING, AR_SHARING_MAPS),
        ("body_en", EN_SHARING, EN_SHARING_MAPS),
    ],
}


class Command(BaseCommand):
    help = "Update the privacy page for the delivery map and live driver location"

    def handle(self, *args, **options):
        for slug, changes in REPLACEMENTS.items():
            page = LegalPage.objects.filter(slug=slug).first()
            if page is None:
                continue
            changed = False
            for field, old, new in changes:
                text = getattr(page, field)
                if new not in text and old in text:
                    setattr(page, field, text.replace(old, new))
                    changed = True
            if changed:
                page.save()
            self.stdout.write(f"{slug}: {'updated' if changed else 'already up to date'}")
