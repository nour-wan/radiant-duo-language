"""Phone numbers in one form (+963...) so the same number always matches."""

import re

_DIGITS = re.compile(r"\d+")


def normalize_phone(raw):
    """'0944 123 456', '944123456', '00963944123456', '+963 944-123-456' -> '+963944123456'.

    Numbers from other countries must start with + or 00. Returns None when it isn't a phone number.
    """
    if not raw:
        return None
    raw = str(raw).strip()
    digits = "".join(_DIGITS.findall(raw.translate(str.maketrans("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹", "01234567890123456789"))))
    plus = raw.startswith("+")
    if not plus and digits.startswith("00"):
        digits, plus = digits[2:], True
    if not plus:
        if digits.startswith("963"):
            pass
        elif digits.startswith("09") and len(digits) == 10:
            digits = "963" + digits[1:]
        elif digits.startswith("9") and len(digits) == 9:
            digits = "963" + digits
        else:
            return None
    if digits.startswith("963"):
        # Syrian mobiles: 9 digits after the country code, starting with 9
        local = digits[3:]
        if local.startswith("0"):
            local = local[1:]
        if not (len(local) == 9 and local.startswith("9")):
            return None
        return "+963" + local
    if not 8 <= len(digits) <= 15:
        return None
    return "+" + digits
