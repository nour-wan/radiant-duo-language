from rest_framework.permissions import BasePermission


class IsStoreAdmin(BasePermission):
    """Only active staff accounts may use the admin API."""

    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and user.is_active and user.is_staff)
