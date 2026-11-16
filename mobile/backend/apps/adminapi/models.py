from django.conf import settings
from django.db import models


class AuditLog(models.Model):
    """Every change made from the admin app, and every admin sign-in. Read by the owner only.

    The actor's name is copied in, so the log still reads correctly if the account is renamed or disabled.
    """

    actor = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name="+")
    actor_name = models.CharField(max_length=150, blank=True)
    action_ar = models.CharField(max_length=120)
    action_en = models.CharField(max_length=120)
    target = models.CharField(max_length=200, blank=True)
    details = models.JSONField(default=dict, blank=True)
    method = models.CharField(max_length=8, blank=True)
    path = models.CharField(max_length=200, blank=True)
    ip = models.GenericIPAddressField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["-created_at", "-id"]
