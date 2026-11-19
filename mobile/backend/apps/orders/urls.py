from django.urls import path

from . import views

urlpatterns = [
    path("cart/quote/", views.QuoteView.as_view()),
    path("orders/", views.OrderListCreateView.as_view()),
    path("orders/<int:pk>/", views.OrderDetailView.as_view()),
    path("orders/<int:pk>/cancel/", views.OrderCancelView.as_view()),
    path("orders/<int:pk>/tracking/", views.OrderTrackingView.as_view()),
    path("orders/<int:pk>/invoice/", views.OrderInvoiceView.as_view()),
]
