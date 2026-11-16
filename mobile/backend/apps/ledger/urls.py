from django.urls import path

from . import views

urlpatterns = [
    path("me/statement/", views.StatementView.as_view()),
]
