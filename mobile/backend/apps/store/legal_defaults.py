"""Initial policy texts (drafts — the store owner can edit them from the admin app).
Markup: '## ' heading, '- ' bullet, other lines are paragraphs."""

PAGES = {
    "privacy": {
        "title_ar": "سياسة الخصوصية",
        "title_en": "Privacy Policy",
        "body_ar": """توضح هذه السياسة كيف تجمع «آلاس لتجارة المواد الغذائية» («نحن») بياناتك وتستخدمها وتحميها عند استخدام تطبيق Alas Foodstuff.
## البيانات التي نجمعها
- بيانات الحساب: الاسم، رقم الهاتف (نتحقق منه برمز يصلك على واتساب)، اسم المنشأة وطبيعتها (مقهى، مطعم، معمل…)، المنطقة والعنوان التفصيلي، والأصناف التي تهمك.
- عناوين التسليم التي تحفظها.
- بيانات الطلبات: المنتجات والكميات والمبالغ وحالة الطلب.
- رمز الإشعارات الخاص بجهازك لإرسال إشعارات الطلبات والعروض.
- موقع التسليم على الخريطة: إذا اخترت تحديد مكانك على الخريطة (اختياري)، نحفظ هذا الموقع مع العنوان ليصل إليك السائق. لا نتابع موقعك، ونطلب الوصول لموقع جهازك فقط عندما تضغط «موقعي الحالي».
- أثناء توصيل طلبك نعرض لك موقع السائق على الخريطة والوقت التقريبي للوصول، ويتوقف ذلك عند تسليم الطلب.
لا نجمع بيانات بطاقات الدفع، ولا جهات الاتصال، ولا الصور من جهازك.
## كيف نستخدم البيانات
- لإنشاء حسابك وتنفيذ طلباتك وتوصيلها والتواصل معك بشأنها.
- لإرسال إشعارات حالة الطلب، وعروض على الأصناف التي تهمك إذا سمحت بالإشعارات.
- لتحسين خدماتنا ومنع الاحتيال والاستخدام غير المشروع.
## مشاركة البيانات
لا نبيع بياناتك ولا نشاركها مع أي جهة لأغراض تسويقية. تُخزَّن البيانات على خوادم خاصة بنا. نستخدم خدمة Firebase Cloud Messaging من Google فقط لإيصال الإشعارات إلى جهازك، وخدمة WhatsApp Business من Meta فقط لإرسال رمز التحقق إلى رقمك. وتُعرض الخرائط من OpenStreetMap، ولا نرسل إليها بياناتك.
## حماية البيانات
تُنقل جميع البيانات عبر اتصال مشفّر (HTTPS)، وتُحفظ كلمات المرور مشفّرة ولا يمكن لأحد الاطلاع عليها، ويقتصر الوصول إلى بيانات الطلبات على إدارة المتجر.
## الاحتفاظ بالبيانات وحذفها
نحتفظ ببياناتك ما دام حسابك فعالاً. يمكنك حذف حسابك في أي وقت من داخل التطبيق: الملف الشخصي ← حذف الحساب. عند الحذف تُزال بياناتك الشخصية وعناوينك ومفضلتك فوراً، وتبقى سجلات الطلبات السابقة لأغراض محاسبية بعد إزالة أي بيانات تعرّف بك.
## الأطفال
التطبيق موجّه للمنشآت التجارية وغير مخصص للأطفال دون 18 عاماً.
## التواصل
لأي استفسار حول الخصوصية: info@alasfoodstuff.com
قد نحدّث هذه السياسة من وقت لآخر، وسيظهر تاريخ آخر تحديث أعلى الصفحة.""",
        "body_en": """This policy explains how Alas for Foodstuff Trading ("we") collects, uses and protects your data when you use the Alas Foodstuff app.
## Data we collect
- Account data: name, phone number (verified with a code sent to you on WhatsApp), business name and type (café, restaurant, factory…), area and detailed address, and the product categories you are interested in.
- Delivery addresses you save.
- Order data: products, quantities, amounts and order status.
- Your device's push notification token, to send order and offer notifications.
- Delivery location on the map: if you choose to pin your place on the map (optional), we save it with the address so the driver can find you. We do not track you; we only use your device's location when you tap "My location".
- While your order is out for delivery, we show you the driver's position on a map and an estimated arrival time; this stops once the order is delivered.
We do not collect payment card data, contacts or photos from your device.
## How we use data
- To create your account, process and deliver your orders and contact you about them.
- To send order status notifications, and offers on the categories you are interested in if you allow notifications.
- To improve our services and prevent fraud and misuse.
## Sharing
We do not sell your data or share it for marketing. Data is stored on our own servers. We use Google Firebase Cloud Messaging only to deliver notifications to your device, and Meta's WhatsApp Business service only to send the verification code to your number. Maps are shown from OpenStreetMap; we do not send your data to it.
## Security
All data is sent over an encrypted connection (HTTPS). Passwords are stored hashed and cannot be read by anyone. Access to order data is limited to store management.
## Retention and deletion
We keep your data while your account is active. You can delete your account at any time in the app: Profile → Delete account. Your personal data, addresses and favorites are removed immediately; past order records are kept for accounting with all identifying details removed.
## Children
The app is intended for businesses and is not directed at children under 18.
## Contact
For privacy questions: info@alasfoodstuff.com
We may update this policy from time to time; the date of the last update is shown at the top of this page.""",
    },
    "terms": {
        "title_ar": "الشروط والأحكام",
        "title_en": "Terms & Conditions",
        "body_ar": """باستخدامك تطبيق Alas Foodstuff فإنك توافق على الشروط التالية.
## الحساب
- يجب أن تكون البيانات التي تقدمها صحيحة ومحدّثة.
- أنت مسؤول عن الحفاظ على سرية كلمة المرور وعن جميع الطلبات المقدمة من حسابك.
## المنتجات والأسعار
- الأسعار بالدولار الأمريكي وتُحدَّد عند تأكيد الطلب، ويحق لنا تعديلها في أي وقت قبل تقديم الطلب.
- الصور توضيحية وقد تختلف العبوة أو اللون قليلاً عن الصورة.
- الكميات المتاحة محدودة بالمخزون، ولبعض العبوات حد أدنى للطلب.
## الطلبات
- يُعد الطلب مقبولاً بعد تأكيده من فريقنا. يحق لنا رفض أو إلغاء أي طلب في حال نفاد المخزون أو خطأ في السعر أو عدم القدرة على التواصل معك.
- يمكنك إلغاء الطلب من التطبيق ما دام بحالة «قيد المراجعة».
## الدفع والتسليم
- الدفع نقداً عند الاستلام.
- يمكنك استلام طلبك من المحل مجاناً، أو اختيار التوصيل برسوم ثابتة حسب منطقتك تظهر قبل تأكيد الطلب وتُدفع عند الاستلام.
- الطلبات المقدمة عبر التطبيق تحصل على خصم خاص بالتطبيق يظهر في ملخص الطلب، ولا يشمل الطلبات بالهاتف أو بأي وسيلة أخرى.
- نتواصل معك لتنسيق موعد التسليم. يرجى فحص البضاعة عند الاستلام.
## الكوبونات
- لكل كوبون شروط (تاريخ انتهاء، حد استخدام، حد أدنى للطلب) ولا يمكن استبداله نقداً.
## المسؤولية
نبذل كل جهد لضمان دقة المعلومات وجودة المنتجات، ولا نتحمل مسؤولية سوء التخزين أو الاستخدام بعد الاستلام. يرجى اتباع إرشادات التخزين في النشرة الفنية لكل منتج.
## التعديلات
قد نعدّل هذه الشروط، واستمرارك في استخدام التطبيق يعني موافقتك على النسخة المحدّثة.""",
        "body_en": """By using the Alas Foodstuff app you agree to the following terms.
## Account
- The information you provide must be accurate and up to date.
- You are responsible for keeping your password confidential and for all orders placed from your account.
## Products and prices
- Prices are in US dollars and are fixed when the order is placed; we may change them at any time before an order is placed.
- Images are illustrative and packaging or color may differ slightly.
- Quantities are limited to available stock, and some packages have a minimum order quantity.
## Orders
- An order is accepted once confirmed by our team. We may refuse or cancel an order in case of stock shortage, pricing error or if we cannot reach you.
- You can cancel an order from the app while it is "Pending".
## Payment and delivery
- Payment is cash on delivery.
- You can pick up your order from the store for free, or choose delivery for a fixed fee based on your area, shown before you place the order and paid on delivery.
- Orders placed through the app get an app-only discount shown in the order summary; it does not apply to phone or other orders.
- We will contact you to arrange delivery. Please inspect goods on receipt.
## Coupons
- Each coupon has conditions (expiry date, usage limit, minimum order) and cannot be exchanged for cash.
## Liability
We do our best to ensure accurate information and product quality, but are not responsible for improper storage or use after delivery. Please follow the storage guidance on each product's technical sheet.
## Changes
We may update these terms; continued use of the app means you accept the updated version.""",
    },
    "returns": {
        "title_ar": "سياسة الإرجاع والاسترداد",
        "title_en": "Return & Refund Policy",
        "body_ar": """نحرص على وصول طلبك سليماً ومطابقاً. نظراً لطبيعة المواد الغذائية، تخضع عمليات الإرجاع للشروط التالية.
## الفحص عند الاستلام
- يرجى فحص البضاعة بحضور المندوب. يحق لك رفض استلام أي عبوة تالفة أو مفتوحة أو غير مطابقة للطلب دون أي تكلفة.
## الحالات المقبولة للإرجاع أو الاستبدال
- منتج تالف أو منتهي الصلاحية أو غير مطابق للطلب (نوع أو حجم أو كمية خاطئة).
- يجب الإبلاغ خلال 48 ساعة من الاستلام مع رقم الطلب وصور واضحة للمنتج والعبوة.
- يجب أن يكون المنتج في عبوته الأصلية ومخزّناً وفق الشروط الموصى بها.
## الحالات غير المقبولة
- العبوات المفتوحة أو المستخدمة جزئياً، إلا إذا ظهر عيب في الجودة.
- المنتجات التي خُزّنت بشكل غير صحيح بعد الاستلام (حرارة أو رطوبة).
- تغيير الرأي بعد استلام المنتجات الحساسة للحرارة مثل الشوكولا وقواعد الآيس كريم.
## الاسترداد
- بعد التحقق من الطلب نوفر لك أحد الخيارات: استبدال المنتج، أو رصيداً لطلبك القادم، أو استرداد المبلغ نقداً خلال 14 يوماً.
- الطلبات الملغاة قبل الشحن لا يترتب عليها أي التزام، لأن الدفع يتم عند الاستلام.
## التواصل
للإبلاغ عن مشكلة: من صفحة «تواصل معنا» في التطبيق، أو واتساب +963965747889، أو info@alasfoodstuff.com""",
        "body_en": """We want your order to arrive intact and correct. Because these are food products, returns are subject to the following conditions.
## Inspection on delivery
- Please inspect goods in the presence of the courier. You may refuse any damaged, opened or incorrect package at no cost.
## Accepted returns or replacements
- Damaged, expired or incorrect products (wrong type, size or quantity).
- Report within 48 hours of delivery with the order number and clear photos of the product and packaging.
- The product must be in its original packaging and stored as recommended.
## Not accepted
- Opened or partially used packages, unless there is a quality defect.
- Products stored improperly after delivery (heat or humidity).
- Change of mind for heat-sensitive products such as chocolate and ice cream bases after delivery.
## Refunds
- After verification we offer one of: a replacement, credit toward your next order, or a cash refund within 14 days.
- Orders cancelled before shipping carry no obligation, since payment is made on delivery.
## Contact
To report an issue: the Contact page in the app, WhatsApp +963965747889, or info@alasfoodstuff.com""",
    },
    "account-deletion": {
        "title_ar": "حذف الحساب",
        "title_en": "Account Deletion",
        "body_ar": """يمكنك حذف حسابك في تطبيق Alas Foodstuff وجميع بياناتك الشخصية في أي وقت.
## من داخل التطبيق
- افتح التطبيق وسجّل الدخول.
- اذهب إلى: الملف الشخصي ← حذف الحساب.
- أكّد الحذف (وأدخل كلمة المرور إن طُلبت).
## دون التطبيق
أرسل طلب حذف من رقمك المسجّل على واتساب +963965747889، أو إلى info@alasfoodstuff.com، بعنوان «حذف الحساب»، وسننفذ الطلب خلال 7 أيام.
## ما الذي يُحذف
- الاسم، البريد الإلكتروني، الهاتف، اسم المنشأة وطبيعتها، المنطقة، العناوين، الأصناف المفضلة، المفضلة، الإشعارات، ورموز الأجهزة: تُحذف نهائياً وفوراً.
- سجلات الطلبات السابقة وحركات كشف الحساب تبقى لأغراض محاسبية وقانونية بعد إزالة كل ما يعرّف بك.
- إذا كان على حسابك رصيد مفتوح (مبلغ متبقٍ أو رصيد لصالحك) فيجب تسويته معنا أولاً، ثم يمكنك حذف الحساب.""",
        "body_en": """You can delete your Alas Foodstuff account and all your personal data at any time.
## In the app
- Open the app and sign in.
- Go to: Profile → Delete account.
- Confirm (and enter your password if asked).
## Without the app
Send "Delete account" on WhatsApp from your registered number to +963965747889, or email info@alasfoodstuff.com; we will complete the request within 7 days.
## What is deleted
- Name, email, phone, business name and type, area, addresses, preferred categories, favorites, notifications and device tokens are permanently deleted immediately.
- Past order records and account statement entries are kept for accounting and legal purposes with all identifying details removed.
- If your account has an open balance (an amount due or a credit), it must be settled with us first; then you can delete the account.""",
    },
}

ABOUT_AR = "آلاس لتجارة المواد الغذائية شريككم في توريد المكونات والمواد الأولية للصناعات الغذائية: الشوكولا والكاكاو، المكسرات، الفواكه المجففة، مستلزمات المخابز والحلويات، الآيس كريم والألبان، النكهات، الزيوت، المحليات والمثبتات. نخدم المعامل والمخابز والمطاعم والمحال بأسعار جملة واستجابة مهنية."
ABOUT_EN = "Alas for Foodstuff Trading is your partner for food ingredients and raw materials: chocolate and cocoa, nuts, dried fruits, bakery and confectionery supplies, ice cream and dairy bases, flavors, oils, sweeteners and stabilizers. We serve factories, bakeries, restaurants and shops with wholesale prices and a professional response."
