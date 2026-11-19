"""Change the store's contact mobile/WhatsApp number everywhere the apps read it: store settings
(contact screen, WhatsApp buttons) and the legal pages. Only the old number is replaced, so other
edits are kept. Safe to run more than once.

    python manage.py update_contact_phone --old 0965747889 --new 0980387705
"""

from django.core.management.base import BaseCommand, CommandError

from apps.accounts.phone import normalize_phone
from apps.store.models import LegalPage, StoreSettings


class Command(BaseCommand):
    help = "Replace the store's contact mobile/WhatsApp number"

    def add_arguments(self, parser):
        parser.add_argument("--old", required=True)
        parser.add_argument("--new", required=True)

    def handle(self, *args, old, new, **opts):
        old_intl, new_intl = normalize_phone(old), normalize_phone(new)
        if not old_intl or not new_intl:
            raise CommandError("Both numbers must be valid Syrian mobile numbers")
        old_local, new_local = "0" + old_intl[4:], "0" + new_intl[4:]
        forms = [(old_intl, new_intl), (old_intl[1:], new_intl[1:]), (old_local, new_local)]

        def swap(text):
            for a, b in forms:
                text = text.replace(a, b)
            return text

        s = StoreSettings.load()
        changed = [f for f in ("phone", "mobile", "whatsapp") if swap(getattr(s, f) or "") != (getattr(s, f) or "")]
        for f in changed:
            setattr(s, f, swap(getattr(s, f)))
        if changed:
            s.save()
        self.stdout.write(f"store settings: {', '.join(changed) or 'already up to date'}")
        for page in LegalPage.objects.all():
            fields = [f for f in ("body_ar", "body_en") if swap(getattr(page, f)) != getattr(page, f)]
            for f in fields:
                setattr(page, f, swap(getattr(page, f)))
            if fields:
                page.save()
            self.stdout.write(f"{page.slug}: {'updated' if fields else 'no change'}")
