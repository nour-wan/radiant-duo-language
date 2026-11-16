from django.urls import path
from rest_framework.routers import SimpleRouter
from rest_framework_simplejwt.views import TokenRefreshView

from . import views

router = SimpleRouter()
router.register("addresses", views.AddressViewSet, basename="address")

urlpatterns = [
    path("auth/register/", views.RegisterView.as_view()),
    path("auth/login/", views.LoginView.as_view()),
    path("auth/google/", views.GoogleLoginView.as_view()),
    path("auth/refresh/", TokenRefreshView.as_view()),
    path("auth/logout/", views.LogoutView.as_view()),
    path("auth/password-reset/", views.PasswordResetRequestView.as_view()),
    path("auth/password-reset/confirm/", views.PasswordResetConfirmView.as_view()),
    path("auth/phone-code/", views.PhoneCodeView.as_view()),
    path("me/phone/", views.ChangePhoneView.as_view()),
    path("me/", views.MeView.as_view()),
    path("me/password/", views.ChangePasswordView.as_view()),
    path("me/delete/", views.DeleteAccountView.as_view()),
] + router.urls
