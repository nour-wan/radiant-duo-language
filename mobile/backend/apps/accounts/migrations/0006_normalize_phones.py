from django.db import migrations


def forwards(apps, schema_editor):
    from apps.accounts.phone import normalize_phone

    User = apps.get_model("accounts", "User")
    for user in User.objects.exclude(phone=""):
        phone = normalize_phone(user.phone)
        if phone and phone != user.phone:
            user.phone = phone
            user.save(update_fields=["phone"])
    # Customers the store already gave a limit to keep buying on credit
    User.objects.exclude(credit_limit=None).update(credit_enabled=True)


class Migration(migrations.Migration):
    dependencies = [("accounts", "0005_phone_login_and_credit")]

    operations = [migrations.RunPython(forwards, migrations.RunPython.noop)]
