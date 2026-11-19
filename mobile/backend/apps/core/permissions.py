from rest_framework.permissions import SAFE_METHODS, BasePermission

# How far a distributor may go into an admin view (set as `distributor_access` on the view):
#   None (default) - not at all
#   "read"         - GET only (products, categories, areas, dollar rate)
#   "scoped"       - the view itself limits everything to the distributor's own customers and orders
DISTRIBUTOR_READ, DISTRIBUTOR_SCOPED = "read", "scoped"


class IsStoreAdmin(BasePermission):
    """Only active staff accounts may use the admin API. Distributors (partner accounts) are shut
    out of every view unless the view explicitly lets them in."""

    message = "not_allowed"

    def has_permission(self, request, view):
        user = request.user
        if not (user and user.is_authenticated and user.is_active and user.is_staff):
            return False
        if getattr(user, "is_distributor", False) and not user.is_superuser:
            access = getattr(view, "distributor_access", None)
            if access == DISTRIBUTOR_READ:
                return request.method in SAFE_METHODS
            return access == DISTRIBUTOR_SCOPED
        return True


class IsOwner(BasePermission):
    """The store owner (superuser): employees, settings, account corrections, cash report."""

    message = "owner_only"

    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and user.is_active and user.is_staff and user.is_superuser)


def is_distributor(user):
    return bool(getattr(user, "is_distributor", False)) and not user.is_superuser


def scope_orders(qs, user, field="distributor"):
    """Owner: everything. Distributor: only orders of their customers. Employees: only the store's own."""
    if user.is_superuser:
        return qs
    if is_distributor(user):
        return qs.filter(**{field: user})
    return qs.filter(**{f"{field}__isnull": True})


def scope_customers(qs, user):
    """Owner: every customer. Distributor: their own customers. Employees: the store's own customers."""
    return scope_orders(qs, user, field="distributor")
