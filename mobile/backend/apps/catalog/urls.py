from django.urls import path

from . import views

urlpatterns = [
    path("categories/", views.CategoryListView.as_view()),
    path("products/", views.ProductListView.as_view()),
    path("products/<str:key>/", views.ProductDetailView.as_view()),
    path("favorites/", views.FavoriteListView.as_view()),
    path("favorites/ids/", views.FavoriteIdsView.as_view()),
    path("favorites/<int:product_id>/", views.FavoriteToggleView.as_view()),
]
