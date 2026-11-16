from django.urls import path

from . import views

urlpatterns = [
    path("home/", views.HomeView.as_view()),
    path("settings/", views.SettingsView.as_view()),
    path("delivery/", views.DeliveryView.as_view()),
    path("legal/<slug:slug>/", views.LegalView.as_view()),
]
