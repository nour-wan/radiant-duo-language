from django.urls import path
from rest_framework.routers import SimpleRouter

from apps.accounts.views import AdminLoginView

from . import views

router = SimpleRouter()
router.register("categories", views.CategoryViewSet, basename="admin-category")
router.register("products", views.ProductViewSet, basename="admin-product")
router.register("orders", views.OrderViewSet, basename="admin-order")
router.register("customers", views.CustomerViewSet, basename="admin-customer")
router.register("coupons", views.CouponViewSet, basename="admin-coupon")
router.register("banners", views.BannerViewSet, basename="admin-banner")
router.register("legal", views.LegalViewSet, basename="admin-legal")
router.register("notifications", views.NotificationViewSet, basename="admin-notification")
router.register("zones", views.ZoneViewSet, basename="admin-zone")
router.register("inbox", views.AdminInboxView, basename="admin-inbox")
router.register("staff", views.StaffViewSet, basename="admin-staff")

urlpatterns = [
    path("auth/login/", AdminLoginView.as_view()),
    path("dashboard/", views.DashboardView.as_view()),
    path("settings/", views.SettingsView.as_view()),
    path("exchange-rate/", views.ExchangeRateView.as_view()),
    path("whatsapp/", views.WhatsAppConfigView.as_view()),
    path("whatsapp/link/", views.WhatsAppLinkView.as_view()),
    path("reports/", views.ReportView.as_view()),
    path("receivables/", views.ReceivablesView.as_view()),
    path("collections/", views.CollectionsView.as_view()),
    path("audit/", views.AuditLogView.as_view()),
] + router.urls
