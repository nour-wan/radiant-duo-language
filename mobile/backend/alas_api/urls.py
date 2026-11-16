from django.conf import settings
from django.contrib import admin
from django.http import JsonResponse
from django.urls import include, path
from django.views.static import serve

from apps.store.views import download_page, legal_page_html


def health(_request):
    return JsonResponse({"status": "ok"})


urlpatterns = [
    path("health/", health),
    path("api/v1/", include("apps.accounts.urls")),
    path("api/v1/", include("apps.catalog.urls")),
    path("api/v1/", include("apps.orders.urls")),
    path("api/v1/", include("apps.store.urls")),
    path("api/v1/", include("apps.notifications.urls")),
    path("api/v1/", include("apps.ledger.urls")),
    path("api/v1/admin/", include("apps.adminapi.urls")),
    path("legal/<slug:slug>/", legal_page_html, name="legal-page"),
    path("download/", download_page, name="download-page"),
    path("django-admin/", admin.site.urls),
]

if settings.DEBUG:
    # In production Nginx serves /media/ directly.
    urlpatterns += [
        path("media/<path:path>", serve, {"document_root": settings.MEDIA_ROOT}),
        path("download/files/<path:path>", serve, {"document_root": settings.DOWNLOADS_DIR}),
    ]
