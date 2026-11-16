from django.conf import settings
from django.db import models


class LedgerEntry(models.Model):
    """One line of a customer's account statement (USD, products only; delivery fees are not included).

    Positive amounts increase what the customer owes (a delivered order), negative amounts reduce it
    (a payment). Entries are never edited or deleted: mistakes are corrected with an adjustment entry.
    """

    ORDER, PAYMENT, ADJUSTMENT = "order", "payment", "adjustment"
    KINDS = [(ORDER, "Delivered order"), (PAYMENT, "Payment"), (ADJUSTMENT, "Adjustment")]

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name="ledger_entries")
    kind = models.CharField(max_length=12, choices=KINDS)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    order = models.ForeignKey("orders.Order", on_delete=models.SET_NULL, null=True, blank=True, related_name="ledger_entries")
    note = models.CharField(max_length=300, blank=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name="+")
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["-created_at", "-id"]
        constraints = [
            models.UniqueConstraint(fields=["order"], condition=models.Q(kind="order"), name="one_ledger_debit_per_order"),
        ]

    def __str__(self):
        return f"{self.kind} {self.amount}"
