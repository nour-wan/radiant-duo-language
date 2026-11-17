"""Prices entered in USD, shown to customers only in Syrian pounds at today's rate."""

from decimal import Decimal
from io import StringIO

from django.core.management import call_command

from apps.ledger.models import LedgerEntry
from apps.orders.models import Order
from apps.store import fx
from apps.store.models import ExchangeRate, StoreSettings

from .test_api import Base

PAGE = (
    '<script>self.__next_f.push([1,"5:[\\"$\\",{\\"rates\\":[{\\"code\\":\\"USD\\",\\"slug\\":\\"us-dollar\\",'
    '\\"cities\\":{\\"damascus\\":{\\"buy\\":14875,\\"sell\\":14950,\\"change\\":-0.17},'
    '\\"alhasakah\\":{\\"buy\\":14925,\\"sell\\":15025}},\\"updated_at\\":\\"2026-11-17T10:26:03+03:00\\"},'
    '{\\"code\\":\\"EUR\\",\\"cities\\":{\\"damascus\\":{\\"buy\\":16220,\\"sell\\":16440}}}]}"])</script>'
)


def reading(buy, sell):
    return lambda: {"buy": Decimal(buy), "sell": Decimal(sell), "updated_at": ""}


class ExchangeRateTests(Base):
    def setUp(self):
        super().setUp()
        s = StoreSettings.load()
        s.usd_rate_mode, s.usd_rate_manual, s.syp_rounding = "auto", None, 10
        s.save()
        fx.clear_cache()
        fx.update_from_source(reading("148.75", "149.50"))

    def test_parse_page_converts_old_pounds_to_new(self):
        r = fx.parse_sp_today(PAGE)
        self.assertEqual((r["buy"], r["sell"]), (Decimal("148.75"), Decimal("149.50")))

    def test_customer_prices_are_syp_rounded(self):
        # 28 USD × 149.50 = 4186 → 4190 ; 240 × 149.50 = 35880 ; 260 × 149.50 = 38870
        r = self.client.get(f"/api/v1/products/{self.product.slug}/")
        prices = [(v["price"], v["discount_price"]) for v in r.data["variants"]]
        self.assertEqual(prices, [("4190.00", None), ("38870.00", "35880.00")])
        r = self.client.get("/api/v1/products/")
        self.assertEqual((r.data["results"][0]["price"], r.data["results"][0]["discount_price"]), ("4190.00", None))

    def test_order_fixed_in_syp_with_rate(self):
        self.login(self.user)
        r = self.order([{"variant_id": self.v1.id, "quantity": 5}])
        self.assertEqual(r.status_code, 201, r.data)
        self.assertEqual(r.data["total"], "20950.00")
        for key in ("total_usd", "exchange_rate", "currency"):
            self.assertNotIn(key, r.data)
        self.assertNotIn("unit_price_usd", r.data["items"][0])
        o = Order.objects.get(pk=r.data["id"])
        self.assertEqual((o.exchange_rate, o.total_usd, o.currency), (Decimal("149.50"), Decimal("140.00"), "SYP"))
        # The rate moves: the placed order keeps its amount
        fx.update_from_source(reading("150", "152"))
        o.refresh_from_db()
        self.assertEqual(o.total, Decimal("20950.00"))
        self.login(self.admin)
        r = self.client.get(f"/api/v1/admin/orders/{o.id}/")
        self.assertEqual((r.data["total"], r.data["total_usd"], r.data["exchange_rate"]), ("20950.00", "140.00", "149.50"))

    def test_prices_changed_since_quote(self):
        self.login(self.user)
        r = self.order([{"variant_id": self.v1.id, "quantity": 5}], expected_total="20000")
        self.assertEqual(r.data["code"], "prices_changed")
        r = self.order([{"variant_id": self.v1.id, "quantity": 5}], expected_total="20950")
        self.assertEqual(r.status_code, 201)

    def test_buy_side_and_manual_rate(self):
        s = StoreSettings.load()
        s.usd_rate_side = "buy"
        s.save()
        fx.clear_cache()
        self.assertEqual(fx.current_rate(), Decimal("148.75"))
        s.usd_rate_mode, s.usd_rate_manual = "manual", Decimal("100")
        s.save()
        fx.clear_cache()
        r = self.client.get(f"/api/v1/products/{self.product.slug}/")
        self.assertEqual(r.data["variants"][0]["price"], "2800.00")

    def test_big_jump_is_held_until_owner_accepts(self):
        entry, problem = fx.update_from_source(reading("200", "201"))
        self.assertEqual(problem, "jump_held")
        fx.clear_cache()
        self.assertEqual(fx.current_rate(), Decimal("149.50"))
        self.login(self.admin)
        st = self.client.get("/api/v1/admin/exchange-rate/").data
        self.assertEqual(st["held"]["id"], entry.id)
        st = self.client.post("/api/v1/admin/exchange-rate/", {"action": "accept", "id": entry.id}, format="json").data
        self.assertEqual((st["rate"], st["held"]), ("201.00", None))

    def test_failure_keeps_last_rate(self):
        def broken():
            raise fx.RateUnavailable("usd_not_found")

        entry, problem = fx.update_from_source(broken)
        self.assertIsNone(entry)
        self.assertEqual(fx.current_rate(), Decimal("149.50"))

    def test_no_rate_at_all(self):
        ExchangeRate.objects.all().delete()
        fx.clear_cache()
        self.login(self.user)
        r = self.order([{"variant_id": self.v1.id, "quantity": 5}])
        self.assertEqual(r.data["code"], "prices_unavailable")
        r = self.client.get(f"/api/v1/products/{self.product.slug}/")
        self.assertIsNone(r.data["variants"][0]["price"])

    def test_nothing_about_dollars_in_public_settings(self):
        data = self.client.get("/api/v1/settings/").data
        self.assertFalse([k for k in data if "usd" in k or "rate" in k or "syp" in k])

    def test_admin_sees_usd_and_syp(self):
        self.login(self.admin)
        r = self.client.get(f"/api/v1/admin/products/{self.product.id}/")
        v = r.data["variants"][0]
        self.assertEqual((v["price"], v["price_syp"]), ("28.00", "4190.00"))
        self.assertEqual(self.client.get("/api/v1/admin/dashboard/").data["exchange_rate"]["rate"], "149.50")

    def test_employee_cannot_change_rate(self):
        from apps.accounts.models import User

        emp = User.objects.create_user(phone="0933111222", password="Empl0yee-pass!", full_name="E", is_staff=True)
        self.login(emp)
        self.assertEqual(self.client.get("/api/v1/admin/exchange-rate/").status_code, 200)
        self.assertEqual(self.client.post("/api/v1/admin/exchange-rate/", {"action": "refresh"}, format="json").status_code, 403)

    def test_manual_rate_validation(self):
        self.login(self.admin)
        r = self.client.patch("/api/v1/admin/settings/", {"usd_rate_mode": "manual"}, format="json")
        self.assertEqual(r.status_code, 400)
        r = self.client.patch("/api/v1/admin/settings/", {"usd_rate_mode": "manual", "usd_rate_manual": "14950"}, format="json")
        self.assertEqual(r.status_code, 400)  # old pounds by mistake
        r = self.client.patch("/api/v1/admin/settings/", {"usd_rate_mode": "manual", "usd_rate_manual": "150"}, format="json")
        self.assertEqual(r.status_code, 200)


class ConvertToSypTests(Base):
    def test_existing_usd_money_is_converted_once(self):
        self.login(self.user)
        r = self.order([{"variant_id": self.v1.id, "quantity": 10}])  # 280 at rate 1
        o = Order.objects.get(pk=r.data["id"])
        Order.objects.filter(pk=o.pk).update(currency="USD", exchange_rate=None, total_usd=None)
        LedgerEntry.objects.create(user=self.user, kind="order", amount=Decimal("280.00"), order=o)
        LedgerEntry.objects.create(user=self.user, kind="payment", amount=Decimal("-100.50"))
        self.user.credit_limit = Decimal("500")
        self.user.save()
        call_command("convert_to_syp", "--rate", "150", stdout=StringIO())
        o.refresh_from_db()
        self.assertEqual((o.total, o.total_usd, o.currency, o.exchange_rate), (Decimal("42000.00"), Decimal("280.00"), "SYP", Decimal("150.00")))
        self.assertEqual(o.items.first().unit_price, Decimal("4200.00"))
        amounts = sorted(LedgerEntry.objects.values_list("amount", "original_usd"))
        self.assertEqual(amounts, [(Decimal("-15075.00"), Decimal("-100.50")), (Decimal("42000.00"), Decimal("280.00"))])
        self.user.refresh_from_db()
        self.assertEqual(self.user.credit_limit, Decimal("75000.00"))
        with self.assertRaises(Exception):
            call_command("convert_to_syp", "--rate", "150", stdout=StringIO())
