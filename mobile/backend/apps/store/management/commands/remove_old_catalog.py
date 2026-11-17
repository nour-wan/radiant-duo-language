"""Delete the original sample categories (hidden since the switch to the owner's 5 categories) and
their products, images included. Orders keep their own copy of product names and prices, so past
orders and invoices are not affected.

    python manage.py remove_old_catalog --dry-run
    python manage.py remove_old_catalog
"""

from django.core.management.base import BaseCommand
from django.db import transaction

from apps.catalog.models import Category, Product, ProductImage
from apps.promotions.models import Banner

from .restructure_catalog import CATEGORIES, OLD_CATEGORIES


class Command(BaseCommand):
    help = "Delete the old sample categories and their products; keep only the owner's categories."

    def add_arguments(self, parser):
        parser.add_argument("--dry-run", action="store_true")

    def handle(self, *args, dry_run=False, **opts):
        keep = [c[0] for c in CATEGORIES]
        if Category.objects.filter(slug__in=keep).count() != len(keep):
            self.stderr.write("The owner's categories are not all there yet (run restructure_catalog first). Nothing deleted.")
            return
        old = Category.objects.filter(slug__in=OLD_CATEGORIES)
        products = Product.objects.filter(category__in=old)
        images = list(ProductImage.objects.filter(product__in=products))
        category_ids = [str(i) for i in old.values_list("id", flat=True)]
        product_ids = [str(i) for i in products.values_list("id", flat=True)]
        banners = Banner.objects.filter(link_type="category", link_value__in=category_ids) | Banner.objects.filter(
            link_type="product", link_value__in=product_ids
        )
        summary = f"{old.count()} categories, {products.count()} products, {len(images)} images, {banners.count()} banners"
        if dry_run:
            self.stdout.write(f"would delete: {summary}")
            return
        files = [f for img in images for f in (img.image, img.thumbnail) if f]
        category_files = [c.image for c in old if c.image]
        banner_files = [b.image for b in banners if b.image]
        with transaction.atomic():
            banners.delete()
            products.delete()  # variants, images and favorites go with them; order lines keep their snapshot
            old.delete()
        for f in files + category_files + banner_files:
            try:
                f.storage.delete(f.name)
            except Exception:  # a missing file is fine
                pass
        self.stdout.write(self.style.SUCCESS(f"deleted: {summary}"))
