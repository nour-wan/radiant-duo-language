from rest_framework import serializers

from apps.core.images import absolute_media_url

from .models import Category, Product, ProductImage, Variant


class CategorySerializer(serializers.ModelSerializer):
    image = serializers.SerializerMethodField()
    product_count = serializers.IntegerField(read_only=True, default=None)

    class Meta:
        model = Category
        fields = ["id", "slug", "name_ar", "name_en", "description_ar", "description_en", "image", "sort_order", "product_count"]

    def get_image(self, obj):
        return absolute_media_url(obj.image)


class ImageSerializer(serializers.ModelSerializer):
    url = serializers.SerializerMethodField()
    thumbnail = serializers.SerializerMethodField()

    class Meta:
        model = ProductImage
        fields = ["id", "url", "thumbnail", "sort_order"]

    def get_url(self, obj):
        return absolute_media_url(obj.image)

    def get_thumbnail(self, obj):
        return absolute_media_url(obj.thumbnail or obj.image)


class VariantSerializer(serializers.ModelSerializer):
    in_stock = serializers.SerializerMethodField()

    class Meta:
        model = Variant
        fields = [
            "id", "label_ar", "label_en", "unit", "unit_quantity", "sku", "price", "discount_price",
            "stock", "in_stock", "min_order_qty",
        ]

    def get_in_stock(self, obj):
        return obj.stock >= obj.min_order_qty


def _active_variants(product):
    return [v for v in product.variants.all() if v.is_active]


class ProductListSerializer(serializers.ModelSerializer):
    """Compact card data for lists."""

    thumbnail = serializers.SerializerMethodField()
    price = serializers.SerializerMethodField()
    discount_price = serializers.SerializerMethodField()
    in_stock = serializers.SerializerMethodField()
    category_id = serializers.IntegerField(read_only=True)

    class Meta:
        model = Product
        fields = [
            "id", "slug", "name_ar", "name_en", "short_description_ar", "short_description_en", "category_id",
            "thumbnail", "price", "discount_price", "in_stock", "is_featured", "sold_count",
        ]

    def _cheapest(self, obj):
        variants = _active_variants(obj)
        return min(variants, key=lambda v: v.effective_price) if variants else None

    def get_thumbnail(self, obj):
        images = list(obj.images.all())
        return absolute_media_url(images[0].thumbnail or images[0].image) if images else None

    def get_price(self, obj):
        v = self._cheapest(obj)
        return str(v.price) if v else None

    def get_discount_price(self, obj):
        v = self._cheapest(obj)
        return str(v.discount_price) if v and v.discount_price and v.discount_price < v.price else None

    def get_in_stock(self, obj):
        return any(v.stock >= v.min_order_qty for v in _active_variants(obj))


class ProductDetailSerializer(ProductListSerializer):
    images = ImageSerializer(many=True, read_only=True)
    variants = serializers.SerializerMethodField()
    category = CategorySerializer(read_only=True)

    class Meta(ProductListSerializer.Meta):
        fields = ProductListSerializer.Meta.fields + [
            "description_ar", "description_en", "specifications", "images", "variants", "category",
        ]

    def get_variants(self, obj):
        return VariantSerializer(_active_variants(obj), many=True).data
