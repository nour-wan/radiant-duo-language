from decimal import Decimal, InvalidOperation

from django.db.models import Case, Count, Exists, F, Min, OuterRef, Prefetch, Q, When
from django.shortcuts import get_object_or_404
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import Category, Favorite, Product, ProductImage, Variant
from .serializers import CategorySerializer, ProductDetailSerializer, ProductListSerializer

SORTS = {
    "newest": ["-created_at", "-id"],
    "price_asc": ["min_price", "id"],
    "price_desc": ["-min_price", "-id"],
    "popular": ["-sold_count", "-id"],
    "name": ["name_en", "id"],
}


def visible_products():
    """Active products in active categories, with the data list cards need."""
    effective = Case(
        When(
            variants__discount_price__isnull=False,
            variants__discount_price__lt=F("variants__price"),
            then=F("variants__discount_price"),
        ),
        default=F("variants__price"),
    )
    on_sale = Variant.objects.filter(
        product=OuterRef("pk"), is_active=True, discount_price__isnull=False, discount_price__lt=F("price")
    )
    return (
        Product.objects.filter(is_active=True, category__is_active=True)
        .annotate(min_price=Min(effective, filter=Q(variants__is_active=True)), on_sale=Exists(on_sale))
        .prefetch_related(
            Prefetch("images", queryset=ProductImage.objects.order_by("sort_order", "id")),
            Prefetch("variants", queryset=Variant.objects.order_by("sort_order", "id")),
        )
    )


def _decimal(value):
    try:
        return Decimal(value)
    except (InvalidOperation, TypeError):
        return None


def filter_products(qs, params):
    q = (params.get("q") or "").strip()
    if q:
        qs = qs.filter(
            Q(name_ar__icontains=q) | Q(name_en__icontains=q) | Q(keywords__icontains=q)
            | Q(short_description_ar__icontains=q) | Q(short_description_en__icontains=q)
        )
    if params.get("category"):
        qs = qs.filter(category_id=params["category"]) if str(params["category"]).isdigit() else qs.filter(category__slug=params["category"])
    if (low := _decimal(params.get("min_price"))) is not None:
        qs = qs.filter(min_price__gte=low)
    if (high := _decimal(params.get("max_price"))) is not None:
        qs = qs.filter(min_price__lte=high)
    if params.get("featured") in ("1", "true"):
        qs = qs.filter(is_featured=True)
    if params.get("on_sale") in ("1", "true"):
        qs = qs.filter(on_sale=True)
    if params.get("ids"):
        qs = qs.filter(id__in=[i for i in params["ids"].split(",") if i.isdigit()])
    return qs.order_by(*SORTS.get(params.get("sort"), SORTS["newest"]))


class CategoryListView(generics.ListAPIView):
    serializer_class = CategorySerializer
    permission_classes = [permissions.AllowAny]
    pagination_class = None

    def get_queryset(self):
        return Category.objects.filter(is_active=True).annotate(
            product_count=Count("products", filter=Q(products__is_active=True))
        )


class ProductListView(generics.ListAPIView):
    serializer_class = ProductListSerializer
    permission_classes = [permissions.AllowAny]

    def get_queryset(self):
        return filter_products(visible_products(), self.request.query_params)


class ProductDetailView(generics.RetrieveAPIView):
    serializer_class = ProductDetailSerializer
    permission_classes = [permissions.AllowAny]

    def get_object(self):
        key = self.kwargs["key"]
        qs = visible_products().select_related("category")
        return get_object_or_404(qs, pk=key) if key.isdigit() else get_object_or_404(qs, slug=key)


class FavoriteListView(generics.ListAPIView):
    serializer_class = ProductListSerializer
    permission_classes = [permissions.IsAuthenticated]
    pagination_class = None

    def get_queryset(self):
        return visible_products().filter(favorited_by__user=self.request.user).order_by("-favorited_by__created_at")


class FavoriteToggleView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def put(self, request, product_id):
        product = get_object_or_404(Product, pk=product_id, is_active=True)
        Favorite.objects.get_or_create(user=request.user, product=product)
        return Response(status=status.HTTP_204_NO_CONTENT)

    def delete(self, request, product_id):
        Favorite.objects.filter(user=request.user, product_id=product_id).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class FavoriteIdsView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        return Response(list(Favorite.objects.filter(user=request.user).values_list("product_id", flat=True)))
