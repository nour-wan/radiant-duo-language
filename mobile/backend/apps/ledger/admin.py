from django.contrib import admin

from .models import LedgerEntry


@admin.register(LedgerEntry)
class LedgerEntryAdmin(admin.ModelAdmin):
    """Read-only: entries are created through the admin app and corrected with adjustments."""

    list_display = ["created_at", "user", "kind", "amount", "order", "note", "created_by"]
    list_filter = ["kind"]
    search_fields = ["user__email", "user__full_name", "user__business_name", "order__number"]

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    def has_add_permission(self, request):
        return False
