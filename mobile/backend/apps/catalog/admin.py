from django.contrib import admin

from .models import Category, Product, ProductImage, Variant


class VariantInline(admin.TabularInline):
    model = Variant
    extra = 0


class ImageInline(admin.TabularInline):
    model = ProductImage
    extra = 0


@admin.register(Product)
class ProductAdmin(admin.ModelAdmin):
    list_display = ["name_en", "name_ar", "category", "is_active", "is_featured", "sold_count"]
    list_filter = ["category", "is_active", "is_featured"]
    search_fields = ["name_en", "name_ar", "keywords"]
    inlines = [VariantInline, ImageInline]


@admin.register(Category)
class CategoryAdmin(admin.ModelAdmin):
    list_display = ["name_en", "name_ar", "sort_order", "is_active"]
