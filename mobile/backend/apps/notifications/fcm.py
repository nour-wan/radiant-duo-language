"""Send push notifications through FCM HTTP v1, directly from this server.

Only the Firebase *messaging* service is used (free Spark plan). If FCM is not
configured, sending is skipped and notifications still appear in the in-app inbox.
"""

import logging
import threading

import requests
from django.conf import settings

log = logging.getLogger(__name__)
SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_credentials = None
_lock = threading.Lock()


def is_configured():
    return bool(settings.FCM_PROJECT_ID and settings.FCM_SERVICE_ACCOUNT_FILE)


def _access_token():
    global _credentials
    from google.auth.transport.requests import Request
    from google.oauth2 import service_account

    with _lock:
        if _credentials is None:
            _credentials = service_account.Credentials.from_service_account_file(
                settings.FCM_SERVICE_ACCOUNT_FILE, scopes=[SCOPE]
            )
        if not _credentials.valid:
            _credentials.refresh(Request())
        return _credentials.token


def send(tokens, title, body, data=None):
    """Send one message to each token. Returns (sent, invalid_tokens)."""
    if not tokens or not is_configured():
        return 0, []
    url = f"https://fcm.googleapis.com/v1/projects/{settings.FCM_PROJECT_ID}/messages:send"
    payload_data = {k: str(v) for k, v in (data or {}).items()}
    sent, invalid = 0, []
    try:
        headers = {"Authorization": f"Bearer {_access_token()}"}
    except Exception:
        log.exception("FCM credentials error")
        return 0, []
    with requests.Session() as session:
        for token in tokens:
            message = {
                "message": {
                    "token": token,
                    "notification": {"title": title, "body": body},
                    "data": payload_data,
                    "android": {"priority": "high", "notification": {"channel_id": "alas_default"}},
                }
            }
            try:
                r = session.post(url, json=message, headers=headers, timeout=10)
            except requests.RequestException:
                log.warning("FCM request failed")
                continue
            if r.status_code == 200:
                sent += 1
            elif r.status_code in (400, 404) and ("UNREGISTERED" in r.text or "INVALID_ARGUMENT" in r.text):
                invalid.append(token)
            else:
                log.warning("FCM error %s: %s", r.status_code, r.text[:300])
    return sent, invalid


def send_localized_async(device_tokens, texts, data, notification_id=None):
    """Send in a background thread so requests stay fast.

    device_tokens: iterable of DeviceToken; texts: {"ar": (title, body), "en": (title, body)}.
    """
    if not is_configured():
        return
    groups = {"ar": [], "en": []}
    for t in device_tokens:
        groups["en" if t.language == "en" else "ar"].append(t.token)
    if not any(groups.values()):
        return

    def run():
        from .models import DeviceToken, Notification

        total = 0
        for lang, tokens in groups.items():
            title, body = texts[lang]
            sent, invalid = send(tokens, title, body, data)
            total += sent
            if invalid:
                DeviceToken.objects.filter(token__in=invalid).delete()
        if notification_id:
            Notification.objects.filter(pk=notification_id).update(sent_count=total)

    threading.Thread(target=run, daemon=True).start()
