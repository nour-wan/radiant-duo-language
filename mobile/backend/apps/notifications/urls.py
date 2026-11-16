from django.urls import path

from . import views

urlpatterns = [
    path("devices/", views.DeviceTokenView.as_view()),
    path("notifications/", views.InboxView.as_view()),
    path("notifications/seen/", views.InboxSeenView.as_view()),
    path("notifications/unread/", views.UnreadCountView.as_view()),
]
