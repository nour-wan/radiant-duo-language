from decimal import Decimal

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models
from django.utils.text import slugify


class Category(models.Model):
    slug = models.SlugField(max_length=120, unique=True)
    name_ar = models.CharField(max_length=120)
    name_en = models.CharField(max_length=120)
    description_ar = models.TextField(blank=True)
    description_en = models.TextField(blank=True)
    image = models.ImageField(upload_to="categories/", blank=True)
    sort_order = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["sort_order", "id"]

    def __str__(self):
        return self.name_en

    def save(self, *args, **kwargs):
        if not self.slug:
            self.slug = slugify(self.name_en)[:120] or f"category-{Category.objects.count() + 1}"
        super().save(*args, **kwargs)


class Product(models.Model):
    slug = models.SlugField(max_length=140, unique=True)
    category = models.ForeignKey(Category, on_delete=models.PROTECT, related_name="products")
    name_ar = models.CharField(max_length=160)
    name_en = models.CharField(max_length=160)
    short_description_ar = models.CharField(max_length=300, blank=True)
    short_description_en = models.CharField(max_length=300, blank=True)
    description_ar = models.TextField(blank=True)
    description_en = models.TextField(blank=True)
    specifications = models.JSONField(default=list, blank=True)  # [{"label_ar","label_en","value_ar","value_en"}]
    keywords = models.CharField(max_length=500, blank=True)
    is_featured = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)
    sold_count = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at", "id"]

    def __str__(self):
        return self.name_en

    def save(self, *args, **kwargs):
        if not self.slug:
            base = slugify(self.name_en)[:120] or "product"
            slug, n = base, 2
            while Product.objects.filter(slug=slug).exclude(pk=self.pk).exists():
                slug, n = f"{base}-{n}", n + 1
            self.slug = slug
        super().save(*args, **kwargs)


class ProductImage(models.Model):
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name="images")
    image = models.ImageField(upload_to="products/")
    thumbnail = models.ImageField(upload_to="products/thumbs/", blank=True)
    sort_order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["sort_order", "id"]

    def delete(self, *args, **kwargs):
        image, thumb = self.image, self.thumbnail
        super().delete(*args, **kwargs)
        image.delete(save=False)
        if thumb:
            thumb.delete(save=False)


class Variant(models.Model):
    """A sellable package of a product, e.g. "25 kg bag". Price and stock live here."""

    UNITS = [("kg", "kg"), ("g", "g"), ("l", "liter"), ("ml", "ml"), ("piece", "piece"), ("carton", "carton")]

    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name="variants")
    label_ar = models.CharField(max_length=80)
    label_en = models.CharField(max_length=80)
    unit = models.CharField(max_length=10, choices=UNITS, default="kg")
    unit_quantity = models.DecimalField(max_digits=10, decimal_places=3, default=Decimal("1"))
    sku = models.CharField(max_length=60, blank=True)
    price = models.DecimalField(max_digits=10, decimal_places=2, validators=[MinValueValidator(Decimal("0.01"))])
    discount_price = models.DecimalField(
        max_digits=10, decimal_places=2, null=True, blank=True, validators=[MinValueValidator(Decimal("0.01"))]
    )
    stock = models.PositiveIntegerField(default=0)
    min_order_qty = models.PositiveIntegerField(default=1, validators=[MinValueValidator(1)])
    is_active = models.BooleanField(default=True)
    sort_order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["sort_order", "id"]

    def __str__(self):
        return f"{self.product.name_en} — {self.label_en}"

    @property
    def effective_price(self):
        if self.discount_price and self.discount_price < self.price:
            return self.discount_price
        return self.price


class Favorite(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="favorites")
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name="favorited_by")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["user", "product"], name="unique_favorite")]
        ordering = ["-created_at"]
