"""Switch the store to the owner's five categories (Nov 2026).

Creates the new categories, moves the matching existing products into them, adds
starter products (prices are estimates for the owner to edit) and hides the old
seed categories. Nothing is deleted: hidden categories can be shown again from
the admin app. Safe to run more than once.
"""

from decimal import Decimal
from pathlib import Path

from django.conf import settings
from django.core.files import File
from django.core.management.base import BaseCommand
from django.db import transaction

from apps.catalog.models import Category, Product, ProductImage, Variant
from apps.core.images import process_upload
from apps.promotions.models import Banner

IMAGES = Path(settings.BASE_DIR) / "seed" / "images" / "products"

OLD_CATEGORIES = [
    "chocolate-cocoa", "nuts-seeds", "dried-fruits", "bakery-confectionery", "ice-cream-dairy",
    "flavors-colors", "oils-fats", "sugars-sweeteners", "stabilizers-emulsifiers", "general-food-ingredients",
]

TIN = ("تنكة 3 كغ", "3 kg tin", "kg", 3)
TIN_BOX = ("كرتونة 6 تنكات × 3 كغ", "Box of 6 × 3 kg tins", "kg", 18)
BOTTLE = ("عبوة 1 لتر", "1 L bottle", "l", 1)
BOTTLE_BOX = ("كرتونة 6 عبوات × 1 لتر", "Box of 6 × 1 L bottles", "l", 6)
TUB_1 = ("علبة 1 كغ", "1 kg tub", "kg", 1)
TUB_5 = ("سطل 5 كغ", "5 kg tub", "kg", 5)
BAG_1 = ("كيس 1 كغ", "1 kg bag", "kg", 1)
BAG_5 = ("كيس 5 كغ", "5 kg bag", "kg", 5)
BAG_25 = ("كيس 25 كغ", "25 kg bag", "kg", 25)
SACK_60 = ("شوال 60 كغ", "60 kg jute sack", "kg", 60)
BOX_5 = ("كرتونة 5 كغ", "5 kg box", "kg", 5)
BOX_25 = ("كرتونة 25 كغ", "25 kg box", "kg", 25)

# slug, Arabic name, English name, Arabic description, English description, image, existing products to move
CATEGORIES = [
    ("canned-fruits", "فواكه معلبة", "Canned Fruits",
     "فواكه معلبة بالشراب للحلويات والكاتو والعصائر والمطاعم، بعبوات جملة.",
     "Fruits canned in syrup for desserts, cakes, juices and restaurants, in wholesale packs.",
     "canned-tropical-fruits.jpg", ["canned-tropical-fruits"]),
    ("syrups", "سيروبات", "Syrups",
     "سيروبات النكهات للمقاهي والعصائر والحلويات والآيس كريم.",
     "Flavored syrups for cafés, juices, desserts and ice cream.",
     "syrups.jpg", ["syrups"]),
    ("fruit-purees", "فواكه مهروسة", "Fruit Purees",
     "هريس فواكه جاهز للحشوات والعصائر والكوكتيلات والآيس كريم.",
     "Ready fruit purees for fillings, juices, cocktails and ice cream.",
     "fruit-purees.jpg", ["fruit-purees"]),
    ("raw-cocoa", "كاكاو خام", "Raw Cocoa",
     "حبوب الكاكاو وكتلته ومسحوقه الطبيعي لمعامل الشوكولا والحلويات.",
     "Cocoa beans, nibs, mass and natural powder for chocolate and confectionery makers.",
     "cocoa-mass.jpg", ["cocoa-mass", "natural-cocoa"]),
    ("cocoa-butter", "زبدة الكاكاو", "Cocoa Butter",
     "زبدة الكاكاو الطبيعية والمنزوعة الرائحة وبدائلها لصناعة الشوكولا ومستحضرات الحلويات.",
     "Natural and deodorized cocoa butter and substitutes for chocolate and confectionery.",
     "cocoa-butter.jpg", ["cocoa-butter", "cocoa-butter-substitute"]),
]

# category, slug, Arabic name, English name, Arabic short description, English short description, image, [(pack, price)]
NEW_PRODUCTS = [
    ("canned-fruits", "canned-peach-halves", "خوخ معلب أنصاف", "Canned Peach Halves",
     "أنصاف خوخ أصفر بالشراب الخفيف، مثالية للكاتو والتارت والكوكتيل.",
     "Yellow peach halves in light syrup, ideal for cakes, tarts and cocktails.",
     "canned-tropical-fruits.jpg", [(TIN, "6.50"), (TIN_BOX, "37.00")]),
    ("canned-fruits", "canned-pineapple-slices", "أناناس معلب شرائح", "Canned Pineapple Slices",
     "شرائح أناناس بالشراب للحلويات والعصائر وأطباق المطاعم.",
     "Pineapple slices in syrup for desserts, juices and restaurant dishes.",
     "canned-tropical-fruits.jpg", [(TIN, "7.00"), (TIN_BOX, "40.00")]),
    ("canned-fruits", "canned-fruit-cocktail", "كوكتيل فواكه معلب", "Canned Fruit Cocktail",
     "مزيج فواكه مقطعة بالشراب للسلطات والحلويات والكاتو.",
     "Mixed diced fruits in syrup for fruit salads, desserts and cakes.",
     "canned-tropical-fruits.jpg", [(TIN, "6.80"), (TIN_BOX, "39.00")]),
    ("canned-fruits", "canned-mango-slices", "مانجو معلبة شرائح", "Canned Mango Slices",
     "شرائح مانجو بالشراب للعصائر والحلويات والآيس كريم.",
     "Mango slices in syrup for juices, desserts and ice cream.",
     "canned-tropical-fruits.jpg", [(TIN, "8.00"), (TIN_BOX, "46.00")]),
    ("canned-fruits", "maraschino-cherries", "كرز ماراسكينو", "Maraschino Cherries",
     "كرز أحمر بالشراب لتزيين الكاتو والحلويات والمشروبات.",
     "Red cherries in syrup for decorating cakes, desserts and drinks.",
     "canned-tropical-fruits.jpg", [(TIN, "14.00"), (TIN_BOX, "80.00")]),
    ("syrups", "vanilla-syrup", "سيروب فانيلا", "Vanilla Syrup",
     "سيروب فانيلا للقهوة والمشروبات الباردة والحلويات.",
     "Vanilla syrup for coffee, iced drinks and desserts.",
     "syrups.jpg", [(BOTTLE, "5.50"), (BOTTLE_BOX, "30.00")]),
    ("syrups", "caramel-syrup", "سيروب كراميل", "Caramel Syrup",
     "سيروب كراميل للقهوة والميلك شيك والحلويات.",
     "Caramel syrup for coffee, milkshakes and desserts.",
     "syrups.jpg", [(BOTTLE, "5.50"), (BOTTLE_BOX, "30.00")]),
    ("syrups", "hazelnut-syrup", "سيروب بندق", "Hazelnut Syrup",
     "سيروب بنكهة البندق للقهوة والمشروبات.",
     "Hazelnut-flavored syrup for coffee and drinks.",
     "syrups.jpg", [(BOTTLE, "6.00"), (BOTTLE_BOX, "33.00")]),
    ("syrups", "strawberry-syrup", "سيروب فراولة", "Strawberry Syrup",
     "سيروب فراولة للعصائر والكوكتيلات والآيس كريم.",
     "Strawberry syrup for juices, mocktails and ice cream.",
     "syrups.jpg", [(BOTTLE, "5.00"), (BOTTLE_BOX, "27.00")]),
    ("syrups", "chocolate-syrup", "سيروب شوكولا", "Chocolate Syrup",
     "سيروب شوكولا للموكا والميلك شيك وتزيين الحلويات.",
     "Chocolate syrup for mochas, milkshakes and dessert toppings.",
     "syrups.jpg", [(BOTTLE, "6.00"), (BOTTLE_BOX, "33.00")]),
    ("fruit-purees", "strawberry-puree", "هريس فراولة", "Strawberry Puree",
     "هريس فراولة للعصائر والحشوات والآيس كريم.",
     "Strawberry puree for juices, fillings and ice cream.",
     "fruit-purees.jpg", [(TUB_1, "5.00"), (TUB_5, "23.00")]),
    ("fruit-purees", "mango-puree", "هريس مانجو", "Mango Puree",
     "هريس مانجو للعصائر والسموذي والحلويات.",
     "Mango puree for juices, smoothies and desserts.",
     "fruit-purees.jpg", [(TUB_1, "5.50"), (TUB_5, "25.00")]),
    ("fruit-purees", "raspberry-puree", "هريس توت أحمر", "Raspberry Puree",
     "هريس توت أحمر للحشوات والموس والكوكتيلات.",
     "Raspberry puree for fillings, mousses and mocktails.",
     "fruit-purees.jpg", [(TUB_1, "8.00"), (TUB_5, "37.00")]),
    ("fruit-purees", "passion-fruit-puree", "هريس باشن فروت", "Passion Fruit Puree",
     "هريس فاكهة العاطفة للعصائر والحلويات الفاخرة.",
     "Passion fruit puree for juices and fine pastry.",
     "fruit-purees.jpg", [(TUB_1, "9.00"), (TUB_5, "42.00")]),
    ("fruit-purees", "apricot-puree", "هريس مشمش", "Apricot Puree",
     "هريس مشمش للحشوات والمربيات والعصائر.",
     "Apricot puree for fillings, jams and juices.",
     "fruit-purees.jpg", [(TUB_1, "4.50"), (TUB_5, "20.00")]),
    ("raw-cocoa", "raw-cocoa-beans", "حبوب كاكاو خام", "Raw Cocoa Beans",
     "حبوب كاكاو مخمّرة ومجففة لمعامل الشوكولا والتحميص.",
     "Fermented, dried cocoa beans for chocolate makers and roasters.",
     "cocoa-mass.jpg", [(BAG_25, "175.00"), (SACK_60, "400.00")]),
    ("raw-cocoa", "cocoa-nibs", "كاكاو نيبس", "Cocoa Nibs",
     "حبوب كاكاو محمصة ومكسرة للحلويات والمخبوزات والتزيين.",
     "Roasted, crushed cocoa beans for desserts, baking and toppings.",
     "cocoa-mass.jpg", [(BAG_1, "12.00"), (BAG_5, "55.00")]),
    ("cocoa-butter", "deodorized-cocoa-butter", "زبدة كاكاو منزوعة الرائحة", "Deodorized Cocoa Butter",
     "زبدة كاكاو نقية منزوعة الرائحة للشوكولا البيضاء والحشوات.",
     "Pure deodorized cocoa butter for white chocolate and fillings.",
     "cocoa-butter.jpg", [(BOX_5, "95.00"), (BOX_25, "450.00")]),
    ("cocoa-butter", "cocoa-butter-callets", "زبدة كاكاو أقراص", "Cocoa Butter Callets",
     "زبدة كاكاو طبيعية بشكل أقراص سهلة الوزن والإذابة للتمبرة.",
     "Natural cocoa butter in easy-to-weigh callets for tempering.",
     "cocoa-butter.jpg", [(BAG_1, "22.00"), (BAG_5, "100.00")]),
]


class Command(BaseCommand):
    help = "Switch the catalog to the five owner categories (idempotent)"

    def add_arguments(self, parser):
        parser.add_argument("--no-images", action="store_true", help="Skip image processing (faster, for tests)")

    def _image(self, name):
        with open(IMAGES / name, "rb") as fh:
            return process_upload(File(fh, name=name))

    @transaction.atomic
    def handle(self, *args, no_images=False, **options):
        categories = {}
        for index, (slug, name_ar, name_en, desc_ar, desc_en, image, moved) in enumerate(CATEGORIES):
            cat, created = Category.objects.get_or_create(
                slug=slug,
                defaults={"name_ar": name_ar, "name_en": name_en, "description_ar": desc_ar,
                          "description_en": desc_en, "sort_order": index},
            )
            if created and not no_images:
                main, _ = self._image(image)
                cat.image.save(main.name, main, save=True)
            categories[slug] = cat
            if created:
                Product.objects.filter(slug__in=moved).update(category=cat)

        added = 0
        for cat_slug, slug, name_ar, name_en, short_ar, short_en, image, packs in NEW_PRODUCTS:
            if Product.objects.filter(slug=slug).exists():
                continue
            product = Product.objects.create(
                slug=slug, category=categories[cat_slug], name_ar=name_ar, name_en=name_en,
                short_description_ar=short_ar, short_description_en=short_en,
                description_ar=short_ar, description_en=short_en, keywords=f"{name_ar} {name_en}",
            )
            for i, ((label_ar, label_en, unit, qty), price) in enumerate(packs):
                Variant.objects.create(
                    product=product, label_ar=label_ar, label_en=label_en, unit=unit,
                    unit_quantity=Decimal(str(qty)), sku=f"{slug[:12].upper()}-{qty}", price=Decimal(price),
                    stock=50, min_order_qty=1, sort_order=i,
                )
            if not no_images:
                main, thumb = self._image(image)
                img = ProductImage(product=product, sort_order=0)
                img.image.save(main.name, main, save=False)
                img.thumbnail.save(thumb.name, thumb, save=False)
                img.save()
            added += 1

        hidden = Category.objects.filter(slug__in=OLD_CATEGORIES, is_active=True)
        hidden_ids = [str(i) for i in hidden.values_list("id", flat=True)]
        hidden_count = hidden.update(is_active=False)
        # Banners that open a now-hidden category would lead to an empty page
        banners = Banner.objects.filter(link_type="category", link_value__in=hidden_ids, is_active=True).update(is_active=False)
        self.stdout.write(self.style.SUCCESS(
            f"{len(categories)} categories ready, {added} products added, {hidden_count} old categories hidden, {banners} banners hidden"
        ))
