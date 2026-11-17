"""Load the initial catalog (copied from the website), prices, policies, banners
and sample coupons. Safe to run more than once: existing rows are left as they are."""

import json
import sys
from datetime import timedelta
from decimal import Decimal
from pathlib import Path

from django.conf import settings
from django.core.files import File
from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from apps.catalog.models import Category, Product, ProductImage, Variant
from apps.core.images import process_upload
from apps.promotions.models import Banner, Coupon
from apps.store import legal_defaults
from apps.store.delivery import DeliveryArea, DeliveryZone
from apps.store.models import LegalPage, StoreSettings

SEED = Path(settings.BASE_DIR) / "seed"
sys.path.insert(0, str(SEED))
import pricing  # noqa: E402


class Command(BaseCommand):
    help = "Seed catalog, prices, policies, banners and sample coupons"

    def add_arguments(self, parser):
        parser.add_argument("--no-images", action="store_true", help="Skip image processing (faster, for tests)")
        parser.add_argument("--refresh-legal", action="store_true", help="Overwrite policy pages with the default drafts")

    @transaction.atomic
    def handle(self, *args, no_images=False, refresh_legal=False, **options):
        data = json.loads((SEED / "catalog.json").read_text(encoding="utf-8"))
        self._settings()
        self._legal(refresh_legal)
        # The sample catalog is only for a fresh install: once the owner's categories are in place
        # (restructure_catalog), deleted sample categories and products must never come back.
        from .restructure_catalog import CATEGORIES

        if Category.objects.filter(slug__in=[c[0] for c in CATEGORIES]).exists():
            categories, created = {}, 0
        else:
            categories = self._categories(data["categories"], no_images)
            created = self._products(data["products"], categories, no_images)
            self._banners(no_images)
        self._coupons()
        self._delivery()
        self.stdout.write(self.style.SUCCESS(f"Seed complete: {len(categories)} categories, {created} new products"))

    def _settings(self):
        s = StoreSettings.load()
        if not s.about_ar:
            s.about_ar, s.about_en = legal_defaults.ABOUT_AR, legal_defaults.ABOUT_EN
            s.save()

    def _legal(self, refresh):
        for slug, page in legal_defaults.PAGES.items():
            if refresh:
                LegalPage.objects.update_or_create(slug=slug, defaults=page)
            else:
                LegalPage.objects.get_or_create(slug=slug, defaults=page)

    def _image(self, path):
        with open(path, "rb") as fh:
            return process_upload(File(fh, name=path.name))

    def _categories(self, rows, no_images):
        result = {}
        for index, c in enumerate(rows):
            obj, created = Category.objects.get_or_create(
                slug=c["slug"],
                defaults={
                    "name_ar": c["name"]["ar"], "name_en": c["name"]["en"],
                    "description_ar": c["description"]["ar"], "description_en": c["description"]["en"],
                    "sort_order": index,
                },
            )
            if created and not no_images:
                main, _ = self._image(SEED / "images" / "categories" / c["image"])
                obj.image.save(main.name, main, save=True)
            result[c["id"]] = obj
        return result

    def _products(self, rows, categories, no_images):
        created_count = 0
        now = timezone.now()
        for index, p in enumerate(rows):
            if Product.objects.filter(slug=p["slug"]).exists():
                continue
            specs = [
                {"label_ar": s["label"]["ar"], "label_en": s["label"]["en"], "value_ar": s["value"]["ar"], "value_en": s["value"]["en"]}
                for s in p.get("specifications", [])
            ]
            apps_ar = "، ".join(a["ar"] for a in p.get("applications", []))
            apps_en = ", ".join(a["en"] for a in p.get("applications", []))
            product = Product.objects.create(
                slug=p["slug"],
                category=categories[p["categoryId"]],
                name_ar=p["name"]["ar"],
                name_en=p["name"]["en"],
                short_description_ar=p["shortDescription"]["ar"][:300],
                short_description_en=p["shortDescription"]["en"][:300],
                description_ar=p["description"]["ar"] + (f"\n\nالاستخدامات: {apps_ar}." if apps_ar else ""),
                description_en=p["description"]["en"] + (f"\n\nApplications: {apps_en}." if apps_en else ""),
                specifications=specs,
                keywords=" ".join(p.get("keywords", []))[:500],
                is_featured=p.get("featured", False) or p["id"] in pricing.FEATURED_EXTRA,
            )
            # Spread creation dates so "newest" sorting looks natural
            Product.objects.filter(pk=product.pk).update(created_at=now - timedelta(hours=len(rows) - index))
            for v in pricing.packages(p["id"]):
                Variant.objects.create(
                    product=product,
                    **{**v, "price": Decimal(str(v["price"])),
                       "discount_price": Decimal(str(v["discount_price"])) if v["discount_price"] else None,
                       "unit_quantity": Decimal(str(v["unit_quantity"]))},
                )
            if not no_images:
                main, thumb = self._image(SEED / "images" / "products" / p["image"])
                img = ProductImage(product=product, sort_order=0)
                img.image.save(main.name, main, save=False)
                img.thumbnail.save(thumb.name, thumb, save=False)
                img.save()
            created_count += 1
        return created_count

    def _banners(self, no_images):
        if Banner.objects.exists() or no_images:
            return
        nuts = Category.objects.filter(slug="nuts-seeds").first()
        banners = [
            ("hero.jpg", "مكونات غذائية بأسعار الجملة", "Wholesale food ingredients",
             "كاكاو، شوكولا، مكسرات ومستلزمات المخابز", "Cocoa, chocolate, nuts and bakery supplies", "none", ""),
            ("products.jpg", "عروض المكسرات والفواكه المجففة", "Nuts & dried fruit offers",
             "خصومات على عبوات الجملة", "Discounts on wholesale packs", "category", str(nuts.id) if nuts else ""),
        ]
        for i, (file, t_ar, t_en, s_ar, s_en, link_type, link_value) in enumerate(banners):
            main, _ = self._image(SEED / "images" / "banners" / file)
            b = Banner(title_ar=t_ar, title_en=t_en, subtitle_ar=s_ar, subtitle_en=s_en, link_type=link_type, link_value=link_value, sort_order=i)
            b.image.save(main.name, main, save=False)
            b.save()

    def _delivery(self):
        """Damascus delivery zones (fees in SYP). The owner edits areas/fees from the admin app."""
        if DeliveryZone.objects.exists():
            return
        zones = [
            ("المناطق القريبة من الشعلان", "Near Al-Shaalan", Decimal("250"), False, [
                ("الشعلان", "Al-Shaalan"), ("الصالحية", "Al-Salihiyah"), ("أبو رمانة", "Abu Rummaneh"),
                ("المالكي", "Al-Malki"), ("الروضة", "Al-Rawda"), ("الحمرا", "Al-Hamra"), ("الطلياني", "Al-Talyani"),
                ("عرنوس", "Arnous"), ("الشهبندر", "Al-Shahbandar"), ("الجسر الأبيض", "Al-Jisr Al-Abyad"),
                ("المهاجرين", "Al-Muhajirin"), ("ساروجة", "Saruja"), ("البحصة", "Al-Bahsa"), ("المرجة", "Al-Marjeh"),
                ("الحلبوني", "Al-Halbouni"), ("البرامكة", "Al-Baramkeh"), ("القصاع", "Al-Qassaa"),
                ("باب توما", "Bab Touma"), ("العدوي", "Al-Adawi"), ("المزرعة", "Al-Mazraa"),
            ]),
            ("المناطق الأبعد", "Farther areas", Decimal("500"), True, [
                ("قدسيا", "Qudsaya"), ("ضاحية قدسيا", "Qudsaya Suburb"), ("مشروع دمر", "Mashrou Dummar"),
                ("دمر", "Dummar"), ("الهامة", "Al-Hamah"), ("المزة", "Mezzeh"), ("كفرسوسة", "Kafr Sousa"),
                ("ركن الدين", "Rukn Al-Din"), ("برزة", "Barzeh"), ("جرمانا", "Jaramana"), ("باب شرقي", "Bab Sharqi"),
                ("الميدان", "Al-Midan"), ("دويلعة", "Dwel'a"),
            ]),
        ]
        for i, (ar, en, fee, unlisted, areas) in enumerate(zones):
            zone = DeliveryZone.objects.create(name_ar=ar, name_en=en, fee=fee, is_default_for_unlisted=unlisted, sort_order=i)
            DeliveryArea.objects.bulk_create(
                [DeliveryArea(zone=zone, name_ar=a, name_en=e, sort_order=j) for j, (a, e) in enumerate(areas)]
            )

    def _coupons(self):
        Coupon.objects.get_or_create(
            code="WELCOME10",
            defaults={"kind": Coupon.PERCENT, "value": Decimal("10"), "min_order_total": Decimal("100"),
                      "max_discount": Decimal("100"), "max_uses_per_user": 1},
        )
        Coupon.objects.get_or_create(
            code="BULK50",
            defaults={"kind": Coupon.FIXED, "value": Decimal("50"), "min_order_total": Decimal("1000"),
                      "max_uses_per_user": 3, "expires_at": timezone.now() + timedelta(days=90)},
        )
