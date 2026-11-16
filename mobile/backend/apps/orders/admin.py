from django.contrib import admin

from .models import Order, OrderEvent, OrderItem


class ItemInline(admin.TabularInline):
    model = OrderItem
    extra = 0


class EventInline(admin.TabularInline):
    model = OrderEvent
    extra = 0


@admin.register(Order)
class OrderAdmin(admin.ModelAdmin):
    list_display = ["number", "customer_name", "business_name", "status", "total", "created_at"]
    list_filter = ["status"]
    search_fields = ["number", "customer_name", "customer_phone", "business_name"]
    inlines = [ItemInline, EventInline]
