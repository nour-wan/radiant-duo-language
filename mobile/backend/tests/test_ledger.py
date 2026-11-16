from decimal import Decimal

from django.core.cache import cache

from apps.store.models import StoreSettings

from .test_api import Base


class LedgerTests(Base):
    """Customer account: delivered orders add to the balance, payments reduce it."""

    def setUp(self):
        super().setUp()
        cache.clear()  # order throttling is per user and would carry over between tests

    def deliver(self, order_id, paid=None):
        self.login(self.admin)
        for st in ["confirmed", "shipped", "delivered"]:
            body = {"status": st}
            if st == "delivered" and paid is not None:
                body["paid_amount"] = paid
            with self.captureOnCommitCallbacks(execute=True):
                r = self.client.post(f"/api/v1/admin/orders/{order_id}/status/", body, format="json")
            self.assertEqual(r.status_code, 200, r.data)
        return r

    def place(self, qty=10):  # 10 x 28 = 280 USD
        self.login(self.user)
        r = self.order([{"variant_id": self.v1.id, "quantity": qty}])
        self.assertEqual(r.status_code, 201, r.data)
        return r.data["id"]

    def statement(self):
        self.login(self.user)
        return self.client.get("/api/v1/me/statement/").data

    def test_partial_payment_on_delivery(self):
        order_id = self.place()
        r = self.deliver(order_id, paid="100")
        self.assertEqual(r.data["paid_amount"], "100.00")
        self.assertEqual(r.data["remaining"], "180.00")
        data = self.statement()
        self.assertEqual(data["summary"]["balance"], "180.00")
        self.assertEqual([e["kind"] for e in data["results"]], ["payment", "order"])
        self.assertEqual([e["balance_after"] for e in data["results"]], ["180.00", "280.00"])
        inbox = self.client.get("/api/v1/notifications/").data["results"]
        self.assertIn("180.00", inbox[0]["body_ar"])

    def test_general_payment_and_overpayment_credit(self):
        self.deliver(self.place())
        self.login(self.admin)
        r = self.client.post(f"/api/v1/admin/customers/{self.user.id}/payments/", {"amount": "300", "note": "نقداً"}, format="json")
        self.assertEqual(r.status_code, 201, r.data)
        self.assertEqual(self.statement()["summary"]["balance"], "-20.00")  # 20 USD credit for the customer
        self.login(self.admin)
        r = self.client.get("/api/v1/admin/receivables/")
        self.assertEqual(r.data["total"], "0.00", r.data)

    def test_adjustment_requires_reason_and_entries_are_immutable(self):
        self.login(self.admin)
        url = f"/api/v1/admin/customers/{self.user.id}/adjustments/"
        self.assertEqual(self.client.post(url, {"amount": "5"}, format="json").status_code, 400)
        r = self.client.post(url, {"amount": "-5", "note": "تصحيح"}, format="json")
        self.assertEqual(r.status_code, 201)
        eid = r.data["id"]
        self.assertEqual(self.client.delete(f"/api/v1/admin/customers/{self.user.id}/statement/{eid}/").status_code, 404)

    def test_customer_cannot_record_payments_or_see_others(self):
        self.deliver(self.place())
        self.login(self.user)
        r = self.client.post(f"/api/v1/admin/customers/{self.user.id}/payments/", {"amount": "280"}, format="json")
        self.assertEqual(r.status_code, 403)
        self.assertEqual(self.statement()["summary"]["balance"], "280.00")

    def test_credit_limit_blocks_new_orders(self):
        s = StoreSettings.load()
        s.default_credit_limit = Decimal("500")
        s.save()
        self.deliver(self.place())  # owes 280
        self.login(self.user)
        # Credit is off until the store enables it for this customer: no limit, nothing shown
        r = self.client.post("/api/v1/cart/quote/", {"items": [{"variant_id": self.v1.id, "quantity": 10}]}, format="json")
        self.assertEqual((r.data["order_problem"], r.data["credit_limit"]), (None, None))
        self.assertIsNone(self.client.get("/api/v1/me/statement/").data["summary"]["credit_limit"])
        self.login(self.admin)
        r = self.client.patch(f"/api/v1/admin/customers/{self.user.id}/", {"credit_enabled": True}, format="json")
        self.assertTrue(r.data["credit_enabled"])
        self.user.refresh_from_db()
        self.login(self.user)
        self.assertTrue(self.client.get("/api/v1/me/").data["show_statement"])
        r = self.client.post("/api/v1/cart/quote/", {"items": [{"variant_id": self.v1.id, "quantity": 10}]}, format="json")
        self.assertEqual(r.data["order_problem"], "credit_limit_exceeded")
        self.assertEqual(r.data["credit_available"], "220.00")
        self.assertEqual(self.order([{"variant_id": self.v1.id, "quantity": 10}]).data["code"], "credit_limit_exceeded")
        self.assertEqual(self.order([{"variant_id": self.v1.id, "quantity": 5}]).status_code, 201)  # 140 fits
        # A customer-specific limit overrides the default
        self.login(self.admin)
        r = self.client.patch(f"/api/v1/admin/customers/{self.user.id}/", {"credit_limit": "2000"}, format="json")
        self.assertEqual(r.data["credit_limit"], "2000.00")
        self.assertEqual(r.data["balance"], "280.00")
        self.user.refresh_from_db()  # force_authenticate reuses this object
        self.login(self.user)
        r = self.order([{"variant_id": self.v1.id, "quantity": 10}])
        self.assertEqual(r.status_code, 201, r.data)

    def test_no_limit_by_default(self):
        self.deliver(self.place(qty=25))
        self.assertTrue(self.place(qty=25))

    def test_cannot_delete_account_with_balance(self):
        self.deliver(self.place())
        self.login(self.user)
        r = self.client.post("/api/v1/me/delete/", {"confirm": True, "password": "Str0ng-pass!"}, format="json")
        self.assertEqual(r.data["code"], "account_has_balance")

    def test_cancelled_order_not_on_account(self):
        order_id = self.place()
        self.login(self.admin)
        self.client.post(f"/api/v1/admin/orders/{order_id}/status/", {"status": "cancelled"}, format="json")
        self.assertEqual(self.statement()["summary"]["balance"], "0.00")
        self.login(self.admin)
        r = self.client.post(f"/api/v1/admin/orders/{order_id}/payment/", {"amount": "10"}, format="json")
        self.assertEqual(r.data["code"], "invalid_order")

    def test_dashboard_shows_receivables(self):
        self.deliver(self.place(), paid="80")
        self.login(self.admin)
        self.assertEqual(self.client.get("/api/v1/admin/dashboard/").data["receivables_total"], "200.00")
        self.assertEqual(self.client.get("/api/v1/admin/customers/?owing=1").data["count"], 1)
        csv = self.client.get(f"/api/v1/admin/customers/{self.user.id}/statement/?format=csv").content.decode("utf-8")
        self.assertIn("200.00", csv)

    def test_report_csv_export(self):
        self.login(self.admin)
        r = self.client.get("/api/v1/admin/reports/?format=csv")
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r["Content-Type"].startswith("text/csv"))
