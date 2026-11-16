# تطبيقات آلاس للمواد الغذائية — Alas Foodstuff Apps

هذا المجلد مستقل تماماً عن الموقع، ويحتوي على:

| المجلد | الوصف |
|---|---|
| `backend/` | الخادم: Django REST + PostgreSQL، يعمل على السيرفر الخاص على `https://api.alasfoodstuff.com` |
| `shared/` | حزمة Dart مشتركة بين التطبيقين: النماذج، الاتصال بالخادم، الألوان والخطوط، الترجمة، الإشعارات |
| `store_app/` | تطبيق الزبائن (Flutter) — يُنشر على Google Play باسم **Alas Foodstuff** وحزمة `com.alasfoodstuff.store` |
| `admin_app/` | تطبيق الإدارة (Flutter) — **خاص**، يُثبّت كملف APK على هاتفك فقط، حزمة `com.alasfoodstuff.admin` |
| `keys/` | مفاتيح التوقيع (**سرية**، غير مرفوعة إلى git) |
| `PLAY_STORE.md` | نصوص صفحة المتجر، قائمة الصور المطلوبة، وملاحظات نموذج Data Safety |

---

## 1) الخادم (backend)

### ما الموجود على السيرفر
| البند | القيمة |
|---|---|
| الكود | `/opt/alas-api` (ملك root، للقراءة فقط من التطبيق) |
| الصور المرفوعة | `/var/lib/alas-api/media` |
| الأسرار (كلمة سر قاعدة البيانات، المفتاح السري، إعدادات البريد و FCM) | `/etc/alas-api/env` (صلاحية 640) |
| المستخدم الذي يشغّل التطبيق | `alasapi` (بدون صلاحيات root) |
| الخدمة | `alas-api.service` (Gunicorn على `127.0.0.1:8100`) |
| Nginx | `/etc/nginx/sites-available/api.alasfoodstuff.com` + شهادة Let's Encrypt تتجدد تلقائياً |
| قاعدة البيانات | PostgreSQL محلية، قاعدة `alas` ومستخدم `alas`، تستمع على localhost فقط |
| النسخ الاحتياطي | يومياً 03:30 إلى `/var/backups/alas-api` (آخر 14 يوماً) |
| جدار الحماية | `ufw` يسمح فقط بـ 22 و80 و443 (+ قاعدة قديمة 8080 كانت موجودة)، و`alas-docker-guard.service` يمنع الوصول الخارجي لمنفذ 5433 |
| حماية SSH | `fail2ban` (حظر ساعة بعد 6 محاولات فاشلة) |

### أوامر مفيدة على السيرفر
```sh
systemctl status alas-api            # حالة الخادم
journalctl -u alas-api -n 100        # آخر السجلات
systemctl restart alas-api           # إعادة تشغيل
curl https://api.alasfoodstuff.com/health/
```

### تحديث الخادم بعد تعديل الكود (من جهازك)
```sh
cd mobile/backend
tar --exclude=.venv --exclude=media --exclude=db.sqlite3 --exclude=__pycache__ -czf - . \
  | ssh -i ~/.ssh/alas_vps_ed25519 root@169.58.223.105 \
    'rm -rf /root/alas-api-src && mkdir -p /root/alas-api-src && tar -xzf - -C /root/alas-api-src && bash /root/alas-api-src/deploy/install.sh'
```
سكربت `install.sh` آمن للتشغيل أكثر من مرة: يحدّث الكود، يطبّق migrations، ويعيد تشغيل الخدمة. لا يغيّر الأسرار الموجودة، ولا يلمس الموقعين الآخرين.

### تشغيل الخادم محلياً للتطوير
```sh
cd mobile/backend
python -m venv .venv && .venv/Scripts/pip install -r requirements.txt
.venv/Scripts/python manage.py migrate
.venv/Scripts/python manage.py seed_store         # البيانات الأولية (66 منتجاً)
.venv/Scripts/python manage.py test tests         # 36 اختباراً
.venv/Scripts/python manage.py runserver 0.0.0.0:8100
```
(محلياً تُستخدم SQLite تلقائياً عند عدم وجود `DB_NAME`.)

### إعداد البريد الإلكتروني (رموز استعادة كلمة المرور + إشعار الطلبات بالبريد)
حتى يتم هذا الإعداد، رموز الاستعادة لا تصل للزبون (تُكتب فقط في سجل الخادم).
1. اعرف من مزوّد بريد `info@alasfoodstuff.com` بيانات **SMTP**: الخادم (مثلاً `mail.alasfoodstuff.com`)، المنفذ (587 أو 465)، اسم المستخدم وكلمة المرور.
2. على السيرفر: `nano /etc/alas-api/env` واملأ:
   ```
   EMAIL_HOST=mail.example.com
   EMAIL_PORT=587
   EMAIL_HOST_USER=info@alasfoodstuff.com
   EMAIL_HOST_PASSWORD=كلمة-السر
   EMAIL_USE_TLS=1
   ```
   (للمنفذ 465 استخدم `EMAIL_USE_TLS=0` و`EMAIL_USE_SSL=1`.)
3. `systemctl restart alas-api`

### إعداد Firebase (الإشعارات + الدخول عبر Google) — مجاني، بدون بطاقة
Firebase يُستخدم **فقط** لإيصال الإشعارات ولتسجيل الدخول بـ Google. كل البيانات تبقى على سيرفرك.
1. ادخل https://console.firebase.google.com بحساب Google الخاص بالشركة → **Add project** → الاسم `Alas Foodstuff` → عطّل Google Analytics → Create. (الخطة تبقى **Spark** المجانية، لا تضغط Upgrade.)
2. **Add app → Android**:
   - Package name: `com.alasfoodstuff.store` ← حمّل `google-services.json` وضعه في `mobile/store_app/android/app/`
   - أضف تطبيقاً آخر بـ `com.alasfoodstuff.admin` ← ضع ملفه في `mobile/admin_app/android/app/`
   - أضف بصمة **SHA-1** لكل تطبيق (من الأمر `keytool -list -v -keystore mobile/keys/alas-store.jks` — وبعد الرفع إلى Google Play أضف أيضاً بصمة **App signing key** من Play Console ← Setup ← App integrity).
3. **Project settings → Service accounts → Generate new private key** ← انقل الملف إلى السيرفر:
   ```sh
   scp -i ~/.ssh/alas_vps_ed25519 key.json root@169.58.223.105:/etc/alas-api/fcm-service-account.json
   ssh -i ~/.ssh/alas_vps_ed25519 root@169.58.223.105 'chown root:alasapi /etc/alas-api/fcm-service-account.json && chmod 640 /etc/alas-api/fcm-service-account.json'
   ```
   ثم في `/etc/alas-api/env`: `FCM_PROJECT_ID=` (معرّف المشروع من Project settings) و`systemctl restart alas-api`.
4. **Google Sign-in**: Firebase Console → Authentication → Sign-in method → فعّل Google (هذا يُنشئ OAuth clients تلقائياً). ثم من Project settings → General → Web client ID (أو من Google Cloud Console → APIs & Services → Credentials) انسخ **Web client ID**:
   - في `/etc/alas-api/env`: `GOOGLE_CLIENT_IDS=<web-client-id>` ثم أعد تشغيل الخادم.
   - عند بناء تطبيق المتجر أضف: `--dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>` (زر Google يظهر فقط عند وجود هذا المعرّف).
5. أعد بناء التطبيقين بعد إضافة ملفات `google-services.json`. (بدونها يعمل التطبيقان طبيعياً، والإشعارات تظهر فقط داخل صندوق الإشعارات في التطبيق.)

---

## 2) أدوات التطوير على جهازك (مثبتة)
| الأداة | المكان |
|---|---|
| Flutter 3.47.9 | `C:\dev\flutter` |
| Android SDK 36 | `C:\dev\android-sdk` |
| JDK 17 | `C:\Program Files\Microsoft\jdk-17.0.21.21-hotspot` |
| مفتاح SSH للسيرفر | `C:\Users\user\.ssh\alas_vps_ed25519` |

أضف إلى PATH (مرة واحدة، من PowerShell):
```powershell
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\dev\flutter\bin", "User")
```

## 3) مفاتيح التوقيع — مهم جداً ⚠️
| الملف | الاستخدام |
|---|---|
| `mobile/keys/alas-store.jks` | **Upload key** لتطبيق المتجر على Google Play |
| `mobile/keys/alas-admin.jks` | توقيع تطبيق الإدارة |
| `mobile/store_app/android/key.properties` و `mobile/admin_app/android/key.properties` | كلمات السر الخاصة بالمفاتيح |

- هذه الملفات **غير مرفوعة إلى git** عمداً.
- **انسخها الآن** (المجلد `keys/` + ملفي `key.properties`) إلى مكانين آمنين على الأقل: فلاشة USB محفوظة + خزنة كلمات سر (مثل Bitwarden) أو Google Drive مشفّر.
- مع **Play App Signing** (مفعّل افتراضياً) تحتفظ Google بمفتاح التوقيع النهائي؛ إن ضاع `alas-store.jks` يمكن طلب إعادة تعيين upload key من Play Console، لكنه يأخذ أياماً.
- إن ضاع `alas-admin.jks` فلن تستطيع تحديث تطبيق الإدارة المثبت — ستحتاج حذفه وتثبيته من جديد.

## 4) تطبيق المتجر (store_app)

### تشغيل للتجربة على هاتف متصل (USB debugging)
```sh
cd mobile/store_app
flutter run
# للتجربة مع خادم محلي:  flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8100
```

### APK تجريبي للتثبيت المباشر
```sh
flutter build apk --release
# الناتج: build/app/outputs/flutter-apk/app-release.apk
```

### إصدار جديد على Google Play
1. ارفع رقم الإصدار في `store_app/pubspec.yaml`: `version: 1.0.1+2` (الرقم بعد + يجب أن يزيد في كل رفع).
2. ابنِ ملف AAB:
   ```sh
   flutter build appbundle --release
   # مع Google Sign-in:  --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com
   # الناتج: build/app/outputs/bundle/release/app-release.aab
   ```
3. Play Console → التطبيق → **Production** (أو Internal testing أولاً) → Create new release → ارفع `app-release.aab` → Save → Review → Start rollout.

### أول نشر على Google Play (مرة واحدة)
1. https://play.google.com/console → **Create app**: الاسم `Alas Foodstuff`، اللغة الافتراضية العربية، App، Free.
2. **App content** (كلها مطلوبة):
   - Privacy policy: `https://api.alasfoodstuff.com/legal/privacy/`
   - App access: «All functionality is available without special access» **أو** أعطِ Google حساب تجربة (بريد وكلمة سر لزبون تجريبي) لأن إتمام الطلب يحتاج تسجيل دخول — **الأفضل إعطاء حساب تجريبي**.
   - Ads: No ads.
   - Content rating: املأ الاستبيان (تطبيق تسوّق، لا محتوى حساس).
   - Target audience: 18+.
   - Data safety: انظر `PLAY_STORE.md`.
   - Account deletion URL: `https://api.alasfoodstuff.com/legal/account-deletion/`
   - Government apps / Financial features / Health: No.
3. **Store listing**: النصوص والصور من `PLAY_STORE.md`.
4. **Countries**: اختر الدول (سوريا + غيرها حسب رغبتك).
5. ⚠️ حسابات المطورين الشخصية الجديدة تتطلب **Closed testing** مع 12 مختبراً لمدة 14 يوماً قبل Production. إن كان حسابك حساب شركة (Organization) فلا يلزم.
6. أنشئ release في Internal testing أولاً، جرّب، ثم Production.

## 5) تطبيق الإدارة (admin_app) — خاص

### البناء
```sh
cd mobile/admin_app
flutter build apk --release
# الناتج: build/app/outputs/flutter-apk/app-release.apk  (أعد تسميته alas-admin-1.0.0.apk)
```

### التثبيت على هاتفك
1. انقل ملف APK إلى الهاتف (واتساب لنفسك، Google Drive، أو كابل USB).
2. افتح الملف من الهاتف ← سيطلب أندرويد السماح بـ «تثبيت تطبيقات من مصادر غير معروفة» للتطبيق الذي فتحت منه الملف (مثلاً «الملفات» أو «Chrome») ← اسمح ← Install.
3. إن ظهر تحذير Play Protect اختر «Install anyway» (لأن التطبيق غير منشور على المتجر، وهذا طبيعي).
4. سجّل الدخول بـ `info@alasfoodstuff.com` وكلمة السر التي أعطيتك إياها، ثم **غيّرها فوراً** من: المزيد ← تغيير كلمة المرور.

### التحديث لاحقاً
1. ارفع `version` في `admin_app/pubspec.yaml` (مثلاً `1.0.1+2`).
2. ابنِ APK جديد **بنفس المفتاح** (`alas-admin.jks` — يتم تلقائياً من `key.properties`).
3. ثبّته فوق القديم — تبقى البيانات وتسجيل الدخول.

### الأمان
- لا يوجد تسجيل عام في تطبيق الإدارة؛ الخادم يرفض أي حساب ليس `staff` حتى لو كانت كلمة السر صحيحة.
- لإضافة مدير آخر (على السيرفر):
  ```sh
  cd /opt/alas-api && sudo -u alasapi bash -c 'set -a; . /etc/alas-api/env; set +a; .venv/bin/python manage.py createsuperuser --email someone@alasfoodstuff.com'
  ```
- لا تشارك ملف APK الإدارة مع أحد (لا يحتوي أسراراً، لكنه بوابة للوحة التحكم).

## 6) ما يحسبه الخادم (لا يمكن التلاعب به من التطبيق)
- أسعار المنتجات وأسعار الخصم (يتجاهل أي سعر يرسله التطبيق).
- الكوبونات: الصلاحية، التاريخ، حدود الاستخدام، الحد الأدنى للطلب.
- **خصم الطلب عبر التطبيق** (2% افتراضياً — يُعدّل أو يُوقف من الإدارة ← إعدادات المتجر).
- رسوم التوصيل حسب المنطقة (250 / 500 ل.س افتراضياً — تُعدّل من الإدارة ← مناطق التوصيل). الاستلام من المحل مجاني.
- خصم المخزون عند الطلب (مع قفل يمنع بيع نفس الكمية مرتين) وإرجاعه عند الإلغاء.
- حذف الحساب: يحذف كل البيانات الشخصية، ويُبقي الطلبات للمحاسبة بدون أي بيانات تعريف.

## 7) المرحلة الثانية: iOS (لاحقاً)
الكود مكتوب بحزم تدعم iOS، وما يلزم تقريباً:
1. جهاز **Mac** مع Xcode (أو خدمة بناء سحابية مثل Codemagic).
2. `cd store_app && flutter create --platforms ios .` (ونفس الشيء لـ admin_app).
3. Bundle IDs: `com.alasfoodstuff.store` و`com.alasfoodstuff.admin` في Apple Developer.
4. Firebase: إضافة تطبيقي iOS، ورفع **APNs key** من Apple Developer إلى Firebase (للإشعارات)، ووضع `GoogleService-Info.plist`.
5. **Sign in with Apple** إلزامي على iOS لأن التطبيق يقدم الدخول عبر Google: يُضاف زر Apple في التطبيق + نقطة تحقق في الخادم (`/auth/apple/`) على نفس نمط Google.
6. تفعيل `ios: true` في إعدادات `flutter_launcher_icons` و`flutter_native_splash` وتوليد الأيقونات.
7. تطبيق الإدارة على الآيفون: عبر **TestFlight** (internal testing) دون نشره على App Store.
8. صفحة الخصوصية وحذف الحساب جاهزة ومقبولة لـ App Store أيضاً.
