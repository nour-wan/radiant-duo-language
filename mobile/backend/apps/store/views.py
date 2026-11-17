import re

from django.conf import settings
from django.db.models import Q
from django.http import Http404
from django.shortcuts import render
from django.utils import timezone
from rest_framework import permissions, serializers
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.catalog.models import Category
from apps.catalog.serializers import CategorySerializer, ProductListSerializer
from apps.catalog.views import visible_products
from apps.promotions.models import Banner
from apps.promotions.serializers import BannerSerializer

from .delivery import DeliveryZone
from .models import LegalPage, StoreSettings


class PublicSettingsSerializer(serializers.ModelSerializer):
    class Meta:
        model = StoreSettings
        # Nothing about dollars or the exchange rate is shown to customers
        exclude = [
            "id", "low_stock_threshold", "usd_rate_mode", "usd_rate_side", "usd_rate_manual", "syp_rounding",
            "usd_rate_error", "usd_rate_alerted_at", "syp_converted_rate",
        ]


class LegalPageSerializer(serializers.ModelSerializer):
    url = serializers.SerializerMethodField()

    class Meta:
        model = LegalPage
        fields = ["slug", "title_ar", "title_en", "body_ar", "body_en", "updated_at", "url"]

    def get_url(self, obj):
        request = self.context.get("request")
        return request.build_absolute_uri(f"/legal/{obj.slug}/") if request else f"/legal/{obj.slug}/"


class DeliveryView(APIView):
    """Delivery options and the list of areas (each belongs to a zone with a fixed fee)."""

    permission_classes = [permissions.AllowAny]

    def get(self, request):
        store = StoreSettings.load()
        zones = DeliveryZone.objects.filter(is_active=True).prefetch_related("areas")
        return Response(
            {
                "pickup_enabled": store.pickup_enabled,
                "pickup_address_ar": store.pickup_address_ar,
                "pickup_address_en": store.pickup_address_en,
                "delivery_enabled": store.delivery_enabled,
                "currency_ar": store.delivery_currency_ar,
                "currency_en": store.delivery_currency_en,
                "app_discount_percent": str(store.app_discount_percent) if store.app_discount_enabled else "0",
                "zones": [
                    {
                        "id": z.id, "name_ar": z.name_ar, "name_en": z.name_en, "fee": str(z.fee),
                        "is_default_for_unlisted": z.is_default_for_unlisted,
                        "areas": [
                            {"id": a.id, "name_ar": a.name_ar, "name_en": a.name_en or a.name_ar}
                            for a in z.areas.all() if a.is_active
                        ],
                    }
                    for z in zones
                ],
            }
        )


class SettingsView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        return Response(PublicSettingsSerializer(StoreSettings.load()).data)


class LegalView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request, slug):
        page = LegalPage.objects.filter(slug=slug).first()
        if not page:
            raise Http404
        return Response(LegalPageSerializer(page, context={"request": request}).data)


class HomeView(APIView):
    """Everything the home screen needs in one request."""

    permission_classes = [permissions.AllowAny]

    def get(self, request):
        now = timezone.now()
        banners = Banner.objects.filter(is_active=True).filter(
            Q(starts_at__isnull=True) | Q(starts_at__lte=now), Q(ends_at__isnull=True) | Q(ends_at__gte=now)
        )
        products = visible_products()
        ctx = {"request": request}
        return Response(
            {
                "banners": BannerSerializer(banners, many=True, context=ctx).data,
                "categories": CategorySerializer(Category.objects.filter(is_active=True), many=True, context=ctx).data,
                "featured": ProductListSerializer(products.filter(is_featured=True).order_by("-id")[:10], many=True).data,
                "offers": ProductListSerializer(products.filter(on_sale=True).order_by("-id")[:10], many=True).data,
                "best_sellers": ProductListSerializer(products.order_by("-sold_count", "id")[:10], many=True).data,
                "newest": ProductListSerializer(products.order_by("-created_at", "-id")[:10], many=True).data,
            }
        )


def legal_page_html(request, slug):
    """Public web page (used as the Privacy Policy / account deletion URL on Google Play)."""
    page = LegalPage.objects.filter(slug=slug).first()
    if not page:
        raise Http404
    lang = "en" if request.GET.get("lang") == "en" else "ar"
    return render(
        request,
        "legal/page.html",
        {
            "lang": lang,
            "title": page.title_en if lang == "en" else page.title_ar,
            "blocks": text_blocks(page.body_en if lang == "en" else page.body_ar),
            "updated_at": page.updated_at,
            "slug": page.slug,
            "store": StoreSettings.load(),
            "pages": [(p.slug, p.title_en if lang == "en" else p.title_ar) for p in LegalPage.objects.all()],
        },
    )


APK_NAME = re.compile(r"^alas-foodstuff-(?P<version>[0-9][0-9A-Za-z.+-]*)\.apk$")


def latest_apk():
    """Newest store APK in DOWNLOADS_DIR, named alas-foodstuff-<version>.apk."""
    folder = settings.DOWNLOADS_DIR
    if not folder.is_dir():
        return None
    files = [f for f in folder.iterdir() if f.is_file() and APK_NAME.match(f.name)]
    if not files:
        return None
    newest = max(files, key=lambda f: f.stat().st_mtime)
    stat = newest.stat()
    return {
        "name": newest.name,
        "version": APK_NAME.match(newest.name)["version"],
        "size_mb": f"{stat.st_size / 1024 / 1024:.0f}",
        "updated_at": timezone.datetime.fromtimestamp(stat.st_mtime, tz=timezone.get_current_timezone()),
    }


def download_page(request):
    """Public page with a direct APK download for customers who can't use Google Play."""
    lang = "en" if request.GET.get("lang") == "en" else "ar"
    return render(request, "download/page.html", {"lang": lang, "apk": latest_apk(), "store": StoreSettings.load()})


def text_blocks(body):
    """Tiny markup used in policy texts: '## ' heading, '- ' bullet, blank line = new paragraph."""
    blocks = []
    for raw in body.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("## "):
            blocks.append(("h2", line[3:]))
        elif line.startswith("- "):
            if blocks and blocks[-1][0] == "ul":
                blocks[-1][1].append(line[2:])
            else:
                blocks.append(("ul", [line[2:]]))
        else:
            blocks.append(("p", line))
    return blocks
