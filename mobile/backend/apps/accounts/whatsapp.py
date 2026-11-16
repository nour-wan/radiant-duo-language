"""Delivers phone verification codes on WhatsApp, trying in order:

1. WhatsApp Cloud API (Meta), when configured in the admin app or the server env.
2. The local gateway (wa_gateway/): the store's number linked by QR, like WhatsApp Web.
3. The admin app: the admin taps the notification and WhatsApp opens with the message ready.
"""

import json
import logging
import urllib.error
import urllib.parse
import urllib.request

from django.conf import settings

log = logging.getLogger(__name__)

AUTO, MANUAL = "whatsapp", "manual"


def message_text(code, language):
    if language == "en":
        return f"Your Alas Foodstuff verification code is: {code}\nDo not share this code with anyone."
    return f"رمز التحقق الخاص بك في تطبيق آلاس: {code}\nلا تشارك هذا الرمز مع أحد."


GRAPH = "https://graph.facebook.com/v21.0"


class WhatsAppError(Exception):
    pass


def config():
    """(token, phone_number_id, template, lang): the admin app's settings, else the server env."""
    from .models import WhatsAppConfig

    c = WhatsAppConfig.load()
    return (
        c.access_token or settings.WHATSAPP_TOKEN,
        c.phone_number_id or settings.WHATSAPP_PHONE_NUMBER_ID,
        c.otp_template or settings.WHATSAPP_OTP_TEMPLATE,
        c.template_lang or settings.WHATSAPP_OTP_TEMPLATE_LANG,
    )


def configured():
    return all(config()[:3])


def _call(url, token, body=None):
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST" if body is not None else "GET",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as res:
            return json.loads(res.read() or b"{}")
    except urllib.error.HTTPError as e:
        # Meta explains what is wrong (expired token, template not approved, number not registered…)
        try:
            err = json.loads(e.read()).get("error", {})
            msg = err.get("error_user_msg") or err.get("message") or str(e)
        except ValueError:
            msg = str(e)
        raise WhatsAppError(msg) from e
    except (urllib.error.URLError, OSError) as e:
        raise WhatsAppError(str(e)) from e


def sender_number():
    """The business number the codes come from, as Meta shows it (also checks the token)."""
    token, phone_id, _, _ = config()
    info = _call(f"{GRAPH}/{phone_id}?fields=display_phone_number,verified_name", token)
    return info.get("display_phone_number", ""), info.get("verified_name", "")


def _send_template(phone, code, language):
    token, phone_id, template, lang = config()
    body = {
        "messaging_product": "whatsapp",
        "to": phone.lstrip("+"),
        "type": "template",
        "template": {
            "name": template,
            "language": {"code": lang},
            "components": [
                {"type": "body", "parameters": [{"type": "text", "text": code}]},
                # Authentication templates have a "copy code" button that also takes the code
                {"type": "button", "sub_type": "url", "index": "0", "parameters": [{"type": "text", "text": code}]},
            ],
        },
    }
    _call(f"{GRAPH}/{phone_id}/messages", token, body)
    return True


def _send_to_admins(phone, code, language, purpose):
    from apps.notifications.events import phone_code_for_admin

    link = f"https://wa.me/{phone.lstrip('+')}?text={urllib.parse.quote(message_text(code, language))}"
    phone_code_for_admin(phone, code, purpose, link)


def _gateway_key():
    try:
        with open(settings.WA_GATEWAY_KEY_FILE, encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return ""


def gateway(method, path, body=None, timeout=25):
    """Calls the local gateway; raises WhatsAppError with its error code."""
    key = _gateway_key()
    if not key:
        raise WhatsAppError("gateway_not_installed")
    req = urllib.request.Request(
        settings.WA_GATEWAY_URL.rstrip("/") + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"X-Api-Key": key, "Content-Type": "application/json"},
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as res:
            return json.loads(res.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            raise WhatsAppError(json.loads(e.read()).get("error") or str(e)) from e
        except ValueError:
            raise WhatsAppError(str(e)) from e
    except (urllib.error.URLError, OSError) as e:
        raise WhatsAppError("gateway_unavailable") from e


def gateway_status():
    """{'status': 'open' | 'qr' | 'connecting' | 'closed' | 'unavailable', 'qr': data-URL or None, 'me': number}"""
    try:
        return gateway("GET", "/status", timeout=5)
    except WhatsAppError as e:
        return {"status": "unavailable", "qr": None, "me": None, "error": str(e)}


def send_via_gateway(phone, text):
    gateway("POST", "/send", {"to": phone, "text": text})


def send_code(phone, code, language, purpose):
    """Returns the channel used: 'whatsapp' (sent automatically) or 'manual' (sent by an admin)."""
    if configured():
        try:
            if _send_template(phone, code, language):
                return AUTO
        except WhatsAppError:
            log.exception("WhatsApp code to %s failed; trying the next way", phone)
    try:
        send_via_gateway(phone, message_text(code, language))
        return AUTO
    except WhatsAppError as e:
        if str(e) == "not_on_whatsapp":
            # Nobody could deliver it: tell the customer instead of waiting for nothing
            from apps.core.errors import BusinessError

            raise BusinessError("not_on_whatsapp")
        if str(e) not in ("gateway_not_installed",):
            log.warning("WhatsApp gateway could not send to %s (%s); sending through the admin app", phone, e)
    _send_to_admins(phone, code, language, purpose)
    return MANUAL
