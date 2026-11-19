import os
from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import Address, User
from apps.catalog.models import Category, Favorite, Product, Variant
from apps.orders.models import Order
from apps.promotions.models import Coupon
from apps.store.delivery import DeliveryArea, DeliveryZone
from apps.store.models import StoreSettings


class Base(TestCase):
    def setUp(self):
        from django.core.cache import cache

        cache.clear()  # throttling counters
        self.client = APIClient()
        self.cat = Category.objects.create(slug="nuts", name_ar="مكسرات", name_en="Nuts")
        self.product = Product.objects.create(slug="pistachio", category=self.cat, name_ar="فستق", name_en="Pistachio")
        self.v1 = Variant.objects.create(product=self.product, label_ar="كيس 1 كغ", label_en="1 kg bag", price=Decimal("28.00"), stock=50, min_order_qty=5)
        self.v10 = Variant.objects.create(
            product=self.product, label_ar="كرتونة 10 كغ", label_en="10 kg box", price=Decimal("260.00"),
            discount_price=Decimal("240.00"), stock=3,
        )
        self.user = User.objects.create_user("buyer@example.com", "Str0ng-pass!", full_name="Buyer", phone="0999")
        self.admin = User.objects.create_superuser("info@alasfoodstuff.com", "Adm1n-pass!")
        # Most tests check product pricing only: the app discount is switched off unless a test enables it
        s = StoreSettings.load()
        s.app_discount_enabled = False
        # A fixed rate of 1 keeps the numbers in these tests readable (prices become whole pounds)
        s.usd_rate_mode, s.usd_rate_manual, s.syp_rounding = "manual", Decimal("1"), 1
        s.save()
        from apps.store import fx

        fx.clear_cache()
        self.near = DeliveryZone.objects.create(name_ar="قريبة", name_en="Near", fee=250)
        self.far = DeliveryZone.objects.create(name_ar="بعيدة", name_en="Far", fee=500, is_default_for_unlisted=True)
        self.shaalan = DeliveryArea.objects.create(zone=self.near, name_ar="الشعلان", name_en="Shaalan")
        self.qudsaya = DeliveryArea.objects.create(zone=self.far, name_ar="قدسيا", name_en="Qudsaya")

    def login(self, user):
        self.client.force_authenticate(user)

    def order(self, items, **extra):
        payload = {"items": items, "customer_name": "Buyer", "customer_phone": "0999", "delivery_method": "delivery",
                   "delivery_area_id": self.shaalan.id, "address_details": "Bldg 3", **extra}
        return self.client.post("/api/v1/orders/", payload, format="json")


class PricingTests(Base):
    def test_quote_uses_server_prices_and_discount(self):
        r = self.client.post("/api/v1/cart/quote/", {"items": [
            {"variant_id": self.v1.id, "quantity": 5, "unit_price": "0.01"},
            {"variant_id": self.v10.id, "quantity": 2},
        ]}, format="json")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["subtotal"], "620.00")  # 5*28 + 2*240, client price ignored
        self.assertTrue(r.data["ok"])

    def test_min_qty_and_stock_problems(self):
        r = self.client.post("/api/v1/cart/quote/", {"items": [
            {"variant_id": self.v1.id, "quantity": 2},
            {"variant_id": self.v10.id, "quantity": 4},
        ]}, format="json")
        problems = {line["variant_id"]: line["problem"] for line in r.data["lines"]}
        self.assertEqual(problems[self.v1.id], "below_min_qty")
        self.assertEqual(problems[self.v10.id], "insufficient_stock")
        self.assertFalse(r.data["ok"])

    def test_percent_coupon_with_cap_and_min_total(self):
        Coupon.objects.create(code="welcome10", kind="percent", value=10, min_order_total=100, max_discount=20)
        r = self.client.post("/api/v1/cart/quote/", {"items": [{"variant_id": self.v10.id, "quantity": 1}], "coupon_code": "WELCOME10"}, format="json")
        self.assertEqual(r.data["discount"], "20.00")  # 10% of 240 = 24, capped to 20
        self.assertEqual(r.data["total"], "220.00")
        r = self.client.post("/api/v1/cart/quote/", {"items": [{"variant_id": self.v1.id, "quantity": 5}], "coupon_code": "WELCOME10"}, format="json")
        self.assertEqual(r.data["coupon_problem"], None)
        Coupon.objects.filter(code="WELCOME10").update(min_order_total=500)
        r = self.client.post("/api/v1/cart/quote/", {"items": [{"variant_id": self.v1.id, "quantity": 5}], "coupon_code": "welcome10"}, format="json")
        self.assertEqual(r.data["coupon_problem"], "coupon_min_total")

    def test_expired_coupon(self):
        Coupon.objects.create(code="OLD", kind="fixed", value=5, expires_at=timezone.now() - timedelta(days=1))
        r = self.client.post("/api/v1/cart/quote/", {"items": [{"variant_id": self.v1.id, "quantity": 5}], "coupon_code": "OLD"}, format="json")
        self.assertEqual(r.data["coupon_problem"], "coupon_expired")


class OrderTests(Base):
    def test_guest_cannot_order(self):
        self.assertEqual(self.order([{"variant_id": self.v1.id, "quantity": 5}]).status_code, 401)

    def test_order_deducts_stock_and_applies_coupon_once(self):
        Coupon.objects.create(code="ONCE", kind="fixed", value=10, max_uses_per_user=1)
        self.login(self.user)
        r = self.order([{"variant_id": self.v1.id, "quantity": 10}], coupon_code="ONCE", business_name="Cafe Rose")
        self.assertEqual(r.status_code, 201, r.data)
        self.assertEqual(r.data["total"], "270.00")
        self.v1.refresh_from_db()
        self.assertEqual(self.v1.stock, 40)
        self.assertEqual(Coupon.objects.get(code="ONCE").used_count, 1)
        self.user.refresh_from_db()
        self.assertEqual(self.user.business_name, "Cafe Rose")
        r = self.order([{"variant_id": self.v1.id, "quantity": 5}], coupon_code="ONCE")
        self.assertEqual(r.status_code, 400)
        self.assertEqual(r.data["code"], "coupon_already_used")

    def test_cannot_oversell(self):
        self.login(self.user)
        r = self.order([{"variant_id": self.v10.id, "quantity": 4}])
        self.assertEqual(r.data["code"], "insufficient_stock")
        self.assertEqual(Order.objects.count(), 0)

    def test_duplicate_submit_creates_one_order(self):
        self.login(self.user)
        self.order([{"variant_id": self.v1.id, "quantity": 5}], client_ref="abc")
        self.order([{"variant_id": self.v1.id, "quantity": 5}], client_ref="abc")
        self.assertEqual(Order.objects.count(), 1)
        self.v1.refresh_from_db()
        self.assertEqual(self.v1.stock, 45)

    def test_customer_cancel_restores_stock(self):
        self.login(self.user)
        order_id = self.order([{"variant_id": self.v1.id, "quantity": 5}]).data["id"]
        r = self.client.post(f"/api/v1/orders/{order_id}/cancel/")
        self.assertEqual(r.data["status"], "cancelled")
        self.v1.refresh_from_db()
        self.assertEqual(self.v1.stock, 50)

    def test_orders_disabled_and_min_total(self):
        self.login(self.user)
        s = StoreSettings.load()
        s.min_order_total = 1000
        s.save()
        self.assertEqual(self.order([{"variant_id": self.v1.id, "quantity": 5}]).data["code"], "below_min_order_total")

    def test_customers_only_see_their_orders(self):
        self.login(self.user)
        order_id = self.order([{"variant_id": self.v1.id, "quantity": 5}]).data["id"]
        other = User.objects.create_user("other@example.com", "Str0ng-pass!")
        self.login(other)
        self.assertEqual(self.client.get(f"/api/v1/orders/{order_id}/").status_code, 404)
        self.assertEqual(self.client.get("/api/v1/orders/").data["count"], 0)


class AdminSecurityTests(Base):
    def test_customer_cannot_use_admin_api(self):
        self.login(self.user)
        for url in ["/api/v1/admin/dashboard/", "/api/v1/admin/orders/", "/api/v1/admin/customers/", "/api/v1/admin/settings/"]:
            self.assertEqual(self.client.get(url).status_code, 403, url)
        self.assertEqual(self.client.post("/api/v1/admin/products/", {}, format="json").status_code, 403)

    def test_anonymous_cannot_use_admin_api(self):
        self.assertEqual(self.client.get("/api/v1/admin/orders/").status_code, 401)

    def test_admin_login_rejects_customers(self):
        r = self.client.post("/api/v1/admin/auth/login/", {"email": "buyer@example.com", "password": "Str0ng-pass!"}, format="json")
        self.assertEqual(r.data["code"], "invalid_credentials")
        r = self.client.post("/api/v1/admin/auth/login/", {"email": "info@alasfoodstuff.com", "password": "Adm1n-pass!"}, format="json")
        self.assertEqual(r.status_code, 200)
        self.assertIn("access", r.data["tokens"])

    def test_customer_cannot_register_admin_device(self):
        self.login(self.user)
        r = self.client.post("/api/v1/devices/", {"token": "t1", "app": "admin"}, format="json")
        self.assertEqual(r.status_code, 403)

    def test_status_flow_and_cancel_restock(self):
        self.login(self.user)
        order_id = self.order([{"variant_id": self.v1.id, "quantity": 5}]).data["id"]
        self.login(self.admin)
        r = self.client.post(f"/api/v1/admin/orders/{order_id}/status/", {"status": "delivered"}, format="json")
        self.assertEqual(r.data["code"], "invalid_status_change")
        for st in ["confirmed", "shipped"]:
            self.assertEqual(self.client.post(f"/api/v1/admin/orders/{order_id}/status/", {"status": st}, format="json").data["status"], st)
        self.client.post(f"/api/v1/admin/orders/{order_id}/status/", {"status": "cancelled"}, format="json")
        self.v1.refresh_from_db()
        self.assertEqual(self.v1.stock, 50)

    def test_status_note_reaches_customer(self):
        self.login(self.user)
        order_id = self.order([{"variant_id": self.v1.id, "quantity": 5}]).data["id"]
        self.login(self.admin)
        with self.captureOnCommitCallbacks(execute=True):
            self.client.post(f"/api/v1/admin/orders/{order_id}/status/", {"status": "confirmed", "note": "التوصيل بكرا الصبح"}, format="json")
        self.login(self.user)
        events = self.client.get(f"/api/v1/orders/{order_id}/").data["events"]
        self.assertEqual(events[-1]["note"], "التوصيل بكرا الصبح")
        inbox = self.client.get("/api/v1/notifications/").data["results"]
        self.assertIn("التوصيل بكرا الصبح", inbox[0]["body_ar"])

    def test_admin_product_crud_with_variants(self):
        self.login(self.admin)
        r = self.client.post("/api/v1/admin/products/", {
            "category": self.cat.id, "name_ar": "لوز", "name_en": "Almonds",
            "variants": [{"label_ar": "كيس 1 كغ", "label_en": "1 kg", "price": "9.50", "stock": 10}],
        }, format="json")
        self.assertEqual(r.status_code, 201, r.data)
        pid, vid = r.data["id"], r.data["variants"][0]["id"]
        r = self.client.patch(f"/api/v1/admin/products/{pid}/", {"variants": [
            {"id": vid, "label_ar": "كيس 1 كغ", "label_en": "1 kg", "price": "9.00", "stock": 12},
            {"label_ar": "كرتونة 10 كغ", "label_en": "10 kg", "price": "85.00", "stock": 5},
        ]}, format="json")
        self.assertEqual([v["price"] for v in r.data["variants"]], ["9.00", "85.00"])
        r = self.client.patch(f"/api/v1/admin/products/{pid}/", {"variants": [
            {"label_ar": "x", "label_en": "x", "price": "10", "discount_price": "12", "stock": 1}]}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_hidden_product_not_public(self):
        self.product.is_active = False
        self.product.save()
        self.assertEqual(self.client.get("/api/v1/products/").data["count"], 0)
        self.assertEqual(self.client.get(f"/api/v1/products/{self.product.slug}/").status_code, 404)

    def test_tax_like_fields_absent(self):
        self.login(self.admin)
        data = self.client.get("/api/v1/admin/settings/").data
        self.assertNotIn("tax_rate", data)


class AccountTests(Base):
    def send_code(self, phone, purpose="register", **extra):
        """No WhatsApp API in tests: the code goes to the admin inbox, as on a server without it."""
        from apps.notifications.models import AdminNotification

        self.client.credentials()
        self.client.force_authenticate(user=extra.pop("user", None))
        r = self.client.post("/api/v1/auth/phone-code/", {"phone": phone, "purpose": purpose}, format="json")
        n = AdminNotification.objects.order_by("-id").first()
        return r, (n.body_en.split("code: ")[1][:6] if n and "code: " in n.body_en else None)

    def register_payload(self, code, **extra):
        return {"phone": "0944 123 456", "code": code, "password": "Str0ng-pass!", "full_name": "N",
                "business_name": "Cafe Rose", "business_type": "cafe", "delivery_area": self.shaalan.id,
                "address": "Shaalan st, bldg 5", "interests": [self.cat.id], **extra}

    def test_register_requires_business_profile(self):
        r = self.client.post("/api/v1/auth/register/", {"phone": "0944123456", "password": "Str0ng-pass!", "full_name": "N"}, format="json")
        self.assertEqual(r.status_code, 400)
        for f in ["code", "business_name", "business_type", "address"]:
            self.assertIn(f, r.data["errors"])

    def test_register_needs_the_whatsapp_code(self):
        r, code = self.send_code("0944123456")
        self.assertEqual((r.status_code, r.data["phone"], r.data["channel"]), (200, "+963944123456", "manual"), r.data)
        wrong = "000000" if code != "000000" else "111111"
        r = self.client.post("/api/v1/auth/register/", self.register_payload(wrong), format="json")
        self.assertEqual(r.data["code"], "code_invalid")
        r = self.client.post("/api/v1/auth/register/", self.register_payload(code), format="json")
        self.assertEqual(r.status_code, 201, r.data)
        u = User.objects.get(phone="+963944123456")
        self.assertTrue(u.phone_verified)
        self.assertIsNone(u.email)
        # The code works once, and the number can't be registered twice
        r = self.client.post("/api/v1/auth/register/", self.register_payload(code), format="json")
        self.assertEqual(r.status_code, 400)
        r, _ = self.send_code("+963 944 123 456")
        self.assertEqual(r.data["code"], "phone_taken")

    def test_code_rate_limit_and_attempts(self):
        r, code = self.send_code("0944123456")
        r, _ = self.send_code("0944123456")
        self.assertEqual(r.data["code"], "code_too_soon")
        wrong = "000000" if code != "000000" else "111111"
        for _ in range(5):
            self.client.post("/api/v1/auth/register/", self.register_payload(wrong), format="json")
        r = self.client.post("/api/v1/auth/register/", self.register_payload(code), format="json")
        self.assertEqual(r.data["code"], "code_invalid")  # too many wrong guesses: ask for a new code

    def test_register_saves_profile_and_default_address(self):
        _, code = self.send_code("0944123456")
        r = self.client.post("/api/v1/auth/register/", self.register_payload(code), format="json")
        self.assertEqual(r.status_code, 201, r.data)
        u = User.objects.get(phone="+963944123456")
        self.assertEqual((u.business_type, u.area_name, list(u.interests.all())), ("cafe", "الشعلان", [self.cat]))
        self.assertTrue(r.data["user"]["profile_complete"])
        a = u.addresses.get()
        self.assertEqual((a.delivery_area, a.details, a.is_default), (self.shaalan, "Shaalan st, bldg 5", True))

    def test_register_login_with_phone_and_me(self):
        _, code = self.send_code("0944123456")
        r = self.client.post("/api/v1/auth/register/", self.register_payload(code, area_name="منطقة جديدة", delivery_area=None), format="json")
        self.assertEqual(r.data["user"]["area_name"], "منطقة جديدة")
        r = self.client.post("/api/v1/auth/login/", {"phone": "00963944123456", "password": "wrong-pass"}, format="json")
        self.assertEqual(r.data["code"], "invalid_credentials")
        r = self.client.post("/api/v1/auth/login/", {"phone": "0944123456", "password": "Str0ng-pass!"}, format="json")
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {r.data['tokens']['access']}")
        me = self.client.get("/api/v1/me/").data
        self.assertEqual((me["phone"], me["credit_enabled"], me["show_statement"]), ("+963944123456", False, True))
        # The phone can't be changed without a code
        self.client.patch("/api/v1/me/", {"phone": "0999999999"}, format="json")
        self.assertEqual(self.client.get("/api/v1/me/").data["phone"], "+963944123456")

    def test_old_email_accounts_sign_in_with_their_phone(self):
        self.user.phone = "+963999111222"
        self.user.save()
        r = self.client.post("/api/v1/auth/login/", {"phone": "0999111222", "password": "Str0ng-pass!"}, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        r = self.client.post("/api/v1/auth/login/", {"email": "buyer@example.com", "password": "Str0ng-pass!"}, format="json")
        self.assertEqual(r.status_code, 200)  # older app versions

    def test_password_reset_with_phone(self):
        self.user.phone = "+963999111222"
        self.user.set_unusable_password()  # e.g. signed up with Google
        self.user.save()
        r, code = self.send_code("0999111222", "reset")
        r = self.client.post("/api/v1/auth/password-reset/confirm/", {"phone": "0999111222", "code": code, "new_password": "N3w-pass-123"}, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("N3w-pass-123"))
        self.assertTrue(self.user.phone_verified)
        # Unknown number: same answer, nothing sent
        r, _ = self.send_code("0999000000", "reset")
        self.assertEqual(r.status_code, 200)

    def test_change_phone(self):
        r, code = self.send_code("0933222111", "change", user=self.user)
        self.assertEqual(r.status_code, 200, r.data)
        r = self.client.post("/api/v1/me/phone/", {"phone": "0933222111", "code": code}, format="json")
        self.assertEqual((r.status_code, r.data["phone"], r.data["phone_verified"]), (200, "+963933222111", True))
        r, _ = self.send_code("0933222111", "register")
        self.assertEqual(r.data["code"], "phone_taken")

    def test_cannot_make_self_staff(self):
        self.login(self.user)
        self.client.patch("/api/v1/me/", {"is_staff": True, "full_name": "X"}, format="json")
        self.user.refresh_from_db()
        self.assertFalse(self.user.is_staff)

    def test_password_reset_flow(self):
        from django.core import mail

        self.client.post("/api/v1/auth/password-reset/", {"email": "buyer@example.com"}, format="json")
        code = mail.outbox[-1].body.split(": ")[1][:6]
        r = self.client.post("/api/v1/auth/password-reset/confirm/", {"email": "buyer@example.com", "code": "000000" if code != "000000" else "111111", "new_password": "N3w-pass-123"}, format="json")
        self.assertEqual(r.status_code, 400)
        r = self.client.post("/api/v1/auth/password-reset/confirm/", {"email": "buyer@example.com", "code": code, "new_password": "N3w-pass-123"}, format="json")
        self.assertEqual(r.status_code, 200)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("N3w-pass-123"))

    def test_delete_account_anonymizes_orders(self):
        self.login(self.user)
        self.client.post("/api/v1/addresses/", {"recipient_name": "B", "phone": "1", "area": "x", "details": "y"}, format="json")
        Favorite.objects.create(user=self.user, product=self.product)
        self.order([{"variant_id": self.v1.id, "quantity": 5}])
        r = self.client.post("/api/v1/me/delete/", {"password": "wrong", "confirm": True}, format="json")
        self.assertEqual(r.data["code"], "wrong_password")
        r = self.client.post("/api/v1/me/delete/", {"password": "Str0ng-pass!", "confirm": True}, format="json")
        self.assertEqual(r.status_code, 204)
        self.assertFalse(User.objects.filter(email="buyer@example.com").exists())
        self.assertEqual(Address.objects.count(), 0)
        order = Order.objects.get()
        self.assertEqual((order.user, order.customer_name, order.customer_phone, order.customer_deleted), (None, "", "", True))

    def test_addresses_are_private(self):
        self.login(self.user)
        addr = self.client.post("/api/v1/addresses/", {"recipient_name": "B", "phone": "1", "area": "x", "details": "y"}, format="json").data
        self.assertTrue(addr["is_default"])
        other = User.objects.create_user("o@example.com", "Str0ng-pass!")
        self.login(other)
        self.assertEqual(self.client.get(f"/api/v1/addresses/{addr['id']}/").status_code, 404)
        self.assertEqual(self.order([{"variant_id": self.v1.id, "quantity": 5}], address_id=addr["id"]).status_code, 404)


class CatalogTests(Base):
    def test_filters_and_sorting(self):
        cheap = Product.objects.create(slug="salt", category=self.cat, name_ar="ملح", name_en="Salt")
        Variant.objects.create(product=cheap, label_ar="كيس", label_en="Bag", price=Decimal("9"), stock=5)
        r = self.client.get("/api/v1/products/?sort=price_asc")
        self.assertEqual([p["slug"] for p in r.data["results"]], ["salt", "pistachio"])
        self.assertEqual(self.client.get("/api/v1/products/?q=فستق").data["count"], 1)
        self.assertEqual(self.client.get("/api/v1/products/?max_price=10").data["count"], 1)
        self.assertEqual(self.client.get("/api/v1/products/?on_sale=1").data["count"], 1)
        home = self.client.get("/api/v1/home/").data
        self.assertEqual(len(home["offers"]), 1)

    def test_legal_html_page(self):
        from django.core.management import call_command

        call_command("seed_store", "--no-images", verbosity=0)
        r = self.client.get("/legal/privacy/")
        self.assertContains(r, "سياسة الخصوصية")
        self.assertContains(self.client.get("/legal/privacy/?lang=en"), "Privacy Policy")


class DeliveryAndAppDiscountTests(Base):
    def quote(self, **extra):
        return self.client.post("/api/v1/cart/quote/", {"items": [{"variant_id": self.v1.id, "quantity": 5}], **extra}, format="json").data

    def enable_app_discount(self, on=True):
        s = StoreSettings.load()
        s.app_discount_enabled = on
        s.save()

    def test_delivery_fee_by_area_and_pickup_free(self):
        self.assertEqual(self.quote(delivery_method="delivery", delivery_area_id=self.shaalan.id)["delivery_fee"], "250.00")
        self.assertEqual(self.quote(delivery_method="delivery", delivery_area_id=self.qudsaya.id)["delivery_fee"], "500.00")
        unlisted = self.quote(delivery_method="delivery")
        self.assertEqual((unlisted["delivery_fee"], unlisted["delivery_area_listed"]), ("500.00", False))
        self.assertEqual(self.quote(delivery_method="pickup")["delivery_fee"], "0")

    def test_app_discount_two_percent_after_coupon(self):
        self.enable_app_discount()
        Coupon.objects.create(code="TEN", kind="fixed", value=10)
        q = self.quote(coupon_code="TEN")
        self.assertEqual((q["subtotal"], q["discount"], q["app_discount"], q["total"]), ("140.00", "10.00", "3.00", "127.00"))  # whole Syrian pounds
        self.enable_app_discount(False)
        self.assertEqual(self.quote()["total"], "140.00")

    def test_order_stores_delivery_and_discount(self):
        self.enable_app_discount()
        self.login(self.user)
        r = self.order([{"variant_id": self.v1.id, "quantity": 5}], delivery_area_id=self.qudsaya.id)
        self.assertEqual(r.status_code, 201, r.data)
        self.assertEqual((r.data["delivery_fee"], r.data["delivery_zone"], r.data["app_discount"], r.data["total"]),
                         ("500.00", "بعيدة", "3.00", "137.00"))
        self.assertEqual(r.data["area"], "قدسيا")

    def test_pickup_order_needs_no_address(self):
        self.login(self.user)
        r = self.client.post("/api/v1/orders/", {"items": [{"variant_id": self.v1.id, "quantity": 5}],
                                                  "delivery_method": "pickup"}, format="json")
        self.assertEqual(r.status_code, 201, r.data)
        self.assertEqual((r.data["delivery_method"], r.data["delivery_fee"]), ("pickup", "0.00"))

    def test_delivery_requires_address(self):
        self.login(self.user)
        r = self.client.post("/api/v1/orders/", {"items": [{"variant_id": self.v1.id, "quantity": 5}],
                                                  "delivery_method": "delivery"}, format="json")
        self.assertEqual(r.data["code"], "address_required")

    def test_targeted_broadcast(self):
        from apps.notifications.models import Notification

        cafe = User.objects.create_user("cafe@example.com", "Str0ng-pass!", business_type="cafe")
        cafe.interests.add(self.cat)
        factory = User.objects.create_user("factory@example.com", "Str0ng-pass!", business_type="factory")
        self.login(self.admin)
        r = self.client.post("/api/v1/admin/notifications/audience/", {"target_interests": [self.cat.id]}, format="json")
        self.assertEqual(r.data["count"], 1)
        self.client.post("/api/v1/admin/notifications/", {"title_ar": "عرض", "title_en": "Offer", "target_interests": [self.cat.id]}, format="json")
        self.login(cafe)
        self.assertEqual(self.client.get("/api/v1/notifications/").data["count"], 1)
        self.login(factory)
        self.assertEqual(self.client.get("/api/v1/notifications/").data["count"], 0)
        self.login(self.admin)
        self.client.post("/api/v1/admin/notifications/", {"title_ar": "للجميع", "title_en": "All"}, format="json")
        self.login(factory)
        self.assertEqual(self.client.get("/api/v1/notifications/").data["count"], 1)
        self.assertEqual(Notification.objects.filter(user__isnull=True).count(), 2)

    def test_admin_edits_zones(self):
        self.login(self.admin)
        r = self.client.patch(f"/api/v1/admin/zones/{self.near.id}/", {"fee": "300", "areas": [
            {"id": self.shaalan.id, "name_ar": "الشعلان", "name_en": "Shaalan"}, {"name_ar": "الروضة", "name_en": "Rawda"}]}, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual(len(r.data["areas"]), 2)
        self.assertEqual(self.client.get("/api/v1/delivery/").data["zones"][0]["fee"], "300.00")


class BannerUploadTests(Base):
    def test_create_banner_with_image(self):
        import io

        from django.core.files.uploadedfile import SimpleUploadedFile
        from PIL import Image

        buf = io.BytesIO()
        Image.new("RGB", (40, 20), (200, 10, 10)).save(buf, "PNG")
        self.login(self.admin)
        r = self.client.post("/api/v1/admin/banners/", {"title_ar": "عرض", "link_type": "none",
                                                         "image": SimpleUploadedFile("b.png", buf.getvalue(), "image/png")}, format="multipart")
        self.assertEqual(r.status_code, 201, r.data)
        self.assertTrue(r.data["image"].endswith(".jpg"))
        r = self.client.post("/api/v1/admin/banners/", {"title_ar": "x"}, format="multipart")
        self.assertEqual(r.data["code"], "image_required")
        bad = SimpleUploadedFile("evil.png", b"<?php echo 1; ?>", "image/png")
        r = self.client.post("/api/v1/admin/banners/", {"title_ar": "x", "image": bad}, format="multipart")
        self.assertEqual(r.status_code, 400)


class DownloadPageTests(TestCase):
    def test_download_page_lists_newest_apk(self):
        import os
        import tempfile
        from pathlib import Path

        with tempfile.TemporaryDirectory() as folder, self.settings(DOWNLOADS_DIR=Path(folder)):
            self.assertContains(self.client.get("/download/"), "قريباً")
            old, new = Path(folder, "alas-foodstuff-1.0.0.apk"), Path(folder, "alas-foodstuff-1.0.1.apk")
            old.write_bytes(b"old")
            new.write_bytes(b"new")
            Path(folder, "other.apk").write_bytes(b"ignored")
            os.utime(old, (1, 1))
            r = self.client.get("/download/")
            self.assertContains(r, "/download/files/alas-foodstuff-1.0.1.apk")
            self.assertNotContains(r, "alas-foodstuff-1.0.0.apk")
            self.assertContains(self.client.get("/download/?lang=en"), "Download the app")


class AdminInboxTests(Base):
    def test_new_order_reaches_admin_inbox(self):
        self.login(self.user)
        with self.captureOnCommitCallbacks(execute=True):
            self.assertEqual(self.order([{"variant_id": self.v1.id, "quantity": 5}]).status_code, 201)
        self.login(self.admin)
        r = self.client.get("/api/v1/admin/inbox/")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["unread"], 1)
        self.assertIn("order_id", r.data["results"][0]["data"])
        self.assertEqual(self.client.get("/api/v1/admin/dashboard/").data["unread_inbox"], 1)
        self.client.post("/api/v1/admin/inbox/seen/")
        self.assertEqual(self.client.get("/api/v1/admin/inbox/").data["unread"], 0)

    def test_customer_cannot_read_admin_inbox(self):
        self.client.force_authenticate(self.user)
        self.assertEqual(self.client.get("/api/v1/admin/inbox/").status_code, 403)


class RestructureCatalogTests(TestCase):
    def test_switch_to_owner_categories(self):
        from django.core.management import call_command

        call_command("seed_store", "--no-images", stdout=open(os.devnull, "w"))
        call_command("restructure_catalog", "--no-images", stdout=open(os.devnull, "w"))
        call_command("restructure_catalog", "--no-images", stdout=open(os.devnull, "w"))  # idempotent
        r = self.client.get("/api/v1/categories/")
        rows = r.data["results"] if isinstance(r.data, dict) else r.data
        self.assertEqual([c["slug"] for c in rows], ["canned-fruits", "syrups", "fruit-purees", "raw-cocoa", "cocoa-butter"])
        self.assertEqual(Product.objects.get(slug="cocoa-butter").category.slug, "cocoa-butter")
        self.assertEqual(Product.objects.filter(category__slug="syrups").count(), 6)
        self.assertFalse(Category.objects.get(slug="nuts-seeds").is_active)
        # Running the seed again must not bring the old categories back
        call_command("seed_store", "--no-images", stdout=open(os.devnull, "w"))
        self.assertFalse(Category.objects.get(slug="nuts-seeds").is_active)
        # Deleting the old sample catalog: only the owner's 5 categories remain, past orders keep their lines
        from apps.orders.models import Order, OrderItem

        old = Product.objects.filter(category__slug="nuts-seeds").first()
        order = Order.objects.create(customer_name="x", customer_phone="1", city="d", subtotal=10, total=10)
        OrderItem.objects.create(order=order, product=old, product_name_ar=old.name_ar, product_name_en=old.name_en,
                                 variant_label_ar="a", variant_label_en="a", unit_price=10, quantity=1, line_total=10)
        call_command("remove_old_catalog", stdout=open(os.devnull, "w"))
        self.assertEqual(sorted(Category.objects.values_list("slug", flat=True)),
                         sorted(["canned-fruits", "syrups", "fruit-purees", "raw-cocoa", "cocoa-butter"]))
        self.assertFalse(Product.objects.filter(category__slug="nuts-seeds").exists())
        self.assertEqual(Product.objects.get(slug="cocoa-butter").category.slug, "cocoa-butter")
        self.assertEqual(order.items.get().product_name_en, old.name_en)
        call_command("seed_store", "--no-images", stdout=open(os.devnull, "w"))
        self.assertEqual(Category.objects.count(), 5)


class InvoiceTests(Base):
    def test_invoice_pdf_for_owner_and_admin_only(self):
        self.login(self.user)
        order_id = self.order([{"variant_id": self.v1.id, "quantity": 5}]).data["id"]
        r = self.client.get(f"/api/v1/orders/{order_id}/invoice/")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r["Content-Type"], "application/pdf")
        self.assertTrue(r.content.startswith(b"%PDF"))
        self.assertEqual(self.client.get(f"/api/v1/orders/{order_id}/invoice/?lang=en").status_code, 200)
        other = User.objects.create_user("other@example.com", "Str0ng-pass!")
        self.login(other)
        self.assertEqual(self.client.get(f"/api/v1/orders/{order_id}/invoice/").status_code, 404)
        self.assertEqual(self.client.get(f"/api/v1/admin/orders/{order_id}/invoice/").status_code, 403)
        self.login(self.admin)
        self.assertTrue(self.client.get(f"/api/v1/admin/orders/{order_id}/invoice/").content.startswith(b"%PDF"))


class WhatsAppConfigTests(Base):
    def test_token_is_write_only_and_admin_only(self):
        self.login(self.user)
        self.assertEqual(self.client.get("/api/v1/admin/whatsapp/").status_code, 403)
        self.login(self.admin)
        r = self.client.patch("/api/v1/admin/whatsapp/", {"phone_number_id": "123456789", "access_token": "SECRET-TOKEN", "otp_template": "alas_otp"}, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        self.assertNotIn("access_token", r.data)
        self.assertTrue(r.data["token_saved"] and r.data["configured"])
        # Empty token keeps the saved one; nothing leaks through the public store settings
        r = self.client.patch("/api/v1/admin/whatsapp/", {"access_token": ""}, format="json")
        self.assertTrue(r.data["token_saved"])
        self.assertNotIn("SECRET-TOKEN", str(self.client.get("/api/v1/settings/").content))

    def test_codes_use_the_saved_number(self):
        from unittest import mock

        from apps.accounts.models import WhatsAppConfig

        WhatsAppConfig.objects.create(phone_number_id="555", access_token="T", otp_template="alas_otp")
        with mock.patch("apps.accounts.whatsapp._call", return_value={}) as call:
            r = self.client.post("/api/v1/auth/phone-code/", {"phone": "0944123456", "purpose": "register"}, format="json")
        self.assertEqual(r.data["channel"], "whatsapp")
        url, token, body = call.call_args.args
        self.assertEqual((url.rsplit("/", 2)[-2], token, body["to"], body["template"]["name"]), ("555", "T", "963944123456", "alas_otp"))


class WhatsAppGatewayTests(Base):
    def test_codes_go_through_the_linked_number(self):
        from unittest import mock

        with mock.patch("apps.accounts.whatsapp.gateway", return_value={"ok": True}) as gw:
            r = self.client.post("/api/v1/auth/phone-code/", {"phone": "0944123456", "purpose": "register"}, format="json")
        self.assertEqual(r.data["channel"], "whatsapp")
        method, path, body = gw.call_args.args
        self.assertEqual((method, path, body["to"]), ("POST", "/send", "+963944123456"))
        self.assertIn("رمز التحقق", body["text"])

    def test_number_without_whatsapp_is_reported(self):
        from unittest import mock

        from apps.accounts.whatsapp import WhatsAppError

        with mock.patch("apps.accounts.whatsapp.gateway", side_effect=WhatsAppError("not_on_whatsapp")):
            r = self.client.post("/api/v1/auth/phone-code/", {"phone": "0944123456", "purpose": "register"}, format="json")
        self.assertEqual(r.data["code"], "not_on_whatsapp")

    def test_gateway_down_falls_back_to_admin(self):
        from unittest import mock

        from apps.accounts.whatsapp import WhatsAppError

        with mock.patch("apps.accounts.whatsapp.gateway", side_effect=WhatsAppError("not_linked")):
            r = self.client.post("/api/v1/auth/phone-code/", {"phone": "0944123456", "purpose": "register"}, format="json")
        self.assertEqual(r.data["channel"], "manual")

    def test_link_status_is_admin_only(self):
        self.login(self.user)
        self.assertEqual(self.client.get("/api/v1/admin/whatsapp/link/").status_code, 403)
        self.login(self.admin)
        r = self.client.get("/api/v1/admin/whatsapp/link/")
        self.assertEqual((r.status_code, r.data["status"]), (200, "unavailable"))  # no gateway in tests


class StaffTests(Base):
    def add_employee(self, name="Ahmad", phone="0933111222"):
        self.login(self.admin)
        r = self.client.post("/api/v1/admin/staff/", {"full_name": name, "phone": phone, "password": "Empl0yee-pass!"}, format="json")
        self.assertEqual(r.status_code, 201, r.data)
        return User.objects.get(pk=r.data["id"])

    def test_owner_adds_employee_who_signs_in_with_phone(self):
        emp = self.add_employee()
        self.assertTrue(emp.is_staff and not emp.is_superuser)
        self.client.force_authenticate(user=None)
        r = self.client.post("/api/v1/admin/auth/login/", {"phone": "0933111222", "password": "Empl0yee-pass!"}, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        self.assertFalse(r.data["user"]["is_owner"])
        # A customer can't use the admin login with their phone
        self.user.phone = "+963999111222"
        self.user.save()
        r = self.client.post("/api/v1/admin/auth/login/", {"phone": "0999111222", "password": "Str0ng-pass!"}, format="json")
        self.assertEqual(r.data["code"], "invalid_credentials")

    def test_employee_cannot_use_owner_screens(self):
        emp = self.add_employee()
        self.login(emp)
        for url in ["/api/v1/admin/staff/", "/api/v1/admin/settings/", "/api/v1/admin/collections/", "/api/v1/admin/whatsapp/"]:
            self.assertEqual(self.client.get(url).status_code, 403, url)
        r = self.client.post(f"/api/v1/admin/customers/{self.user.id}/adjustments/", {"amount": "-50", "note": "x"}, format="json")
        self.assertEqual(r.status_code, 403)
        r = self.client.patch(f"/api/v1/admin/customers/{self.user.id}/", {"credit_enabled": True}, format="json")
        self.assertEqual(r.status_code, 403)
        # Day-to-day work is allowed
        self.assertEqual(self.client.get("/api/v1/admin/orders/").status_code, 200)

    def test_who_delivered_and_took_the_cash(self):
        emp = self.add_employee()
        self.login(self.user)
        order_id = self.order([{"variant_id": self.v1.id, "quantity": 5}]).data["id"]
        self.login(self.admin)
        self.client.post(f"/api/v1/admin/orders/{order_id}/status/", {"status": "confirmed"}, format="json")
        self.client.post(f"/api/v1/admin/orders/{order_id}/status/", {"status": "shipped"}, format="json")
        self.login(emp)
        r = self.client.post(f"/api/v1/admin/orders/{order_id}/status/", {"status": "delivered", "paid_amount": "100"}, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual(r.data["events"][-1]["by_name"], "Ahmad")
        self.assertEqual((r.data["payments"][0]["amount"], r.data["payments"][0]["by_name"]), ("100.00", "Ahmad"))
        # The owner's cash report
        self.login(self.admin)
        r = self.client.get(f"/api/v1/admin/collections/?staff={emp.id}")
        self.assertEqual((r.data["total"], r.data["staff"][0]["name"], r.data["staff"][0]["count"]), ("100.00", "Ahmad", 1))
        self.assertEqual(r.data["entries"][0]["order_id"], order_id)
        # Customers never see staff names
        self.login(self.user)
        self.assertNotIn("by_name", str(self.client.get(f"/api/v1/orders/{order_id}/").data))

    def test_disabled_employee_is_locked_out(self):
        emp = self.add_employee()
        r = self.client.patch(f"/api/v1/admin/staff/{emp.id}/", {"is_active": False}, format="json")
        self.assertFalse(r.data["is_active"])
        self.client.force_authenticate(user=None)
        r = self.client.post("/api/v1/admin/auth/login/", {"phone": "0933111222", "password": "Empl0yee-pass!"}, format="json")
        self.assertEqual(r.status_code, 400)
        r = self.client.patch(f"/api/v1/admin/staff/{self.admin.id}/", {"is_active": False}, format="json")
        self.login(self.admin)
        r = self.client.patch(f"/api/v1/admin/staff/{self.admin.id}/", {"is_active": False}, format="json")
        self.assertEqual(r.status_code, 400)


class AuditAndOrderingTests(Base):
    def test_admin_actions_are_logged_for_the_owner(self):
        self.login(self.admin)
        r = self.client.post("/api/v1/admin/staff/", {"full_name": "Ahmad", "phone": "0933111222", "password": "Empl0yee-pass!"}, format="json")
        emp = User.objects.get(pk=r.data["id"])
        self.client.force_authenticate(user=None)
        r = self.client.post("/api/v1/admin/auth/login/", {"phone": "0933111222", "password": "Empl0yee-pass!"}, format="json")
        emp.refresh_from_db()
        self.assertIsNotNone(emp.last_login)  # shown to the owner as last activity
        self.client.post("/api/v1/admin/auth/login/", {"phone": "0933111222", "password": "wrong"}, format="json")
        self.login(emp)
        self.client.patch(f"/api/v1/admin/products/{self.product.id}/", {"name_ar": "اسم جديد"}, format="json")
        self.assertEqual(self.client.get("/api/v1/admin/audit/").status_code, 403)
        self.login(self.admin)
        r = self.client.get("/api/v1/admin/audit/")
        actions = [(e["actor_name"], e["action_en"]) for e in r.data["results"]]
        self.assertIn(("Ahmad", "Product edited"), actions)
        self.assertIn(("Ahmad", "Signed in"), actions)
        self.assertIn(("", "Failed sign-in"), actions)
        self.assertIn(("info@alasfoodstuff.com", "Employee added"), actions)
        # Passwords never reach the log
        self.assertNotIn("Empl0yee-pass!", str(r.data))
        r = self.client.get("/api/v1/admin/audit/?format=csv")
        self.assertIn("Product edited".encode() if False else "تعديل منتج".encode(), r.content)

    def test_orders_newest_first(self):
        self.login(self.user)
        ids = [self.order([{"variant_id": self.v1.id, "quantity": 5}]).data["id"] for _ in range(3)]
        self.login(self.admin)
        listed = [o["id"] for o in self.client.get("/api/v1/admin/orders/").data["results"]]
        self.assertEqual(listed[:3], ids[::-1])
        self.login(self.user)
        listed = [o["id"] for o in self.client.get("/api/v1/orders/").data["results"]]
        self.assertEqual(listed[:3], ids[::-1])


class LanguageTests(Base):
    def test_server_messages_follow_the_app_language(self):
        payload = {"phone": "0944123456", "code": "123456", "password": "12345678", "full_name": "N",
                   "business_name": "B", "business_type": "cafe", "address": "x", "area_name": "y"}
        r = self.client.post("/api/v1/auth/register/", payload, format="json", HTTP_ACCEPT_LANGUAGE="en")
        self.assertIn("too common", str(r.data["errors"]["password"]))
        r = self.client.post("/api/v1/auth/register/", payload, format="json")  # older apps: Arabic
        self.assertIn("شائعة", str(r.data["errors"]["password"]))


class DeliveryTrackingTests(Base):
    """Map pin on the address, copied to the order; the driver's live position while shipped."""

    def setUp(self):
        super().setUp()
        self.driver = User.objects.create_user("driver@alasfoodstuff.com", "Dr1ver-pass!", full_name="Samer", is_staff=True)
        self.other = User.objects.create_user("other@alasfoodstuff.com", "0ther-pass!", full_name="Rami", is_staff=True)
        self.login(self.user)
        addr = self.client.post("/api/v1/addresses/", {
            "recipient_name": "B", "phone": "1", "area": "x", "details": "y", "latitude": "33.513800", "longitude": "36.276500",
        }, format="json")
        self.assertEqual(addr.status_code, 201, addr.data)
        r = self.order([{"variant_id": self.v1.id, "quantity": 5}], address_id=addr.data["id"])
        self.order_id = r.data["id"]
        self.assertEqual((r.data["latitude"], r.data["longitude"]), (33.5138, 36.2765))
        self.assertIsNone(r.data["tracking"])

    def ship(self, by):
        self.login(by)
        for st in ("confirmed", "shipped"):
            self.assertEqual(self.client.post(f"/api/v1/admin/orders/{self.order_id}/status/", {"status": st}, format="json").status_code, 200)

    def report(self, by, lat="33.500000", lng="36.300000"):
        self.login(by)
        return self.client.post(f"/api/v1/admin/orders/{self.order_id}/location/", {"latitude": lat, "longitude": lng}, format="json")

    def test_pin_needs_both_coordinates(self):
        r = self.client.post("/api/v1/addresses/", {"recipient_name": "B", "phone": "1", "area": "x", "details": "y", "latitude": "33.5"}, format="json")
        self.assertEqual(r.status_code, 400)
        r = self.client.post("/api/v1/addresses/", {
            "recipient_name": "B", "phone": "1", "area": "x", "details": "y", "latitude": "95", "longitude": "36"}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_customer_sees_driver_and_eta_only_while_shipped(self):
        self.assertEqual(self.report(self.driver).data, {"tracking": False})  # not out for delivery yet
        self.ship(self.driver)
        self.assertEqual(Order.objects.get(pk=self.order_id).driver_id, self.driver.id)
        self.assertEqual(self.report(self.driver).data, {"tracking": True})
        self.login(self.user)
        t = self.client.get(f"/api/v1/orders/{self.order_id}/tracking/").data
        self.assertEqual(t["status"], "shipped")
        self.assertEqual((t["tracking"]["latitude"], t["tracking"]["longitude"]), (33.5, 36.3))
        self.assertGreater(t["tracking"]["eta_minutes"], 3)
        self.assertLess(t["tracking"]["eta_minutes"], 20)
        self.assertEqual(self.client.get(f"/api/v1/orders/{self.order_id}/").data["tracking"]["latitude"], 33.5)
        # Delivered: nothing is shared any more and the driver's phone is told to stop
        self.login(self.driver)
        self.client.post(f"/api/v1/admin/orders/{self.order_id}/status/", {"status": "delivered"}, format="json")
        self.assertEqual(self.report(self.driver).data, {"tracking": False})
        self.login(self.user)
        self.assertIsNone(self.client.get(f"/api/v1/orders/{self.order_id}/tracking/").data["tracking"])

    def test_stale_position_is_hidden(self):
        self.ship(self.driver)
        self.report(self.driver)
        Order.objects.filter(pk=self.order_id).update(driver_location_at=timezone.now() - timedelta(minutes=30))
        self.login(self.user)
        self.assertIsNone(self.client.get(f"/api/v1/orders/{self.order_id}/tracking/").data["tracking"])

    def test_another_employee_takes_over(self):
        self.ship(self.driver)
        self.report(self.driver)
        self.login(self.other)
        r = self.client.post(f"/api/v1/admin/orders/{self.order_id}/take-delivery/")
        self.assertEqual((r.data["driver_id"], r.data["driver_name"]), (self.other.id, self.other.display_name))
        self.assertEqual((r.data["latitude"], r.data["longitude"]), (33.5138, 36.2765))  # the customer's pin
        self.assertIsNone(r.data["tracking"])  # the old driver's position is cleared
        self.assertEqual(self.report(self.driver).data, {"tracking": False})  # the old driver's phone stops
        self.assertEqual(self.report(self.other).data, {"tracking": True})

    def test_customers_cannot_report_or_see_others(self):
        self.ship(self.driver)
        self.assertEqual(self.report(self.user).status_code, 403)
        stranger = User.objects.create_user("s@example.com", "Str0ng-pass!", full_name="S", phone="0888")
        self.login(stranger)
        self.assertEqual(self.client.get(f"/api/v1/orders/{self.order_id}/tracking/").status_code, 404)

    def test_bad_coordinates_rejected(self):
        self.ship(self.driver)
        self.assertEqual(self.report(self.driver, lat="abc").status_code, 400)
        self.assertEqual(self.report(self.driver, lat="91").status_code, 400)
