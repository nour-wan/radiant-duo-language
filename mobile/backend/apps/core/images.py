"""Validate and normalize uploaded images: re-encode (drops EXIF/GPS and any
embedded payload), cap the size, and build a thumbnail."""

import io
import uuid

from django.conf import settings
from django.core.files.base import ContentFile
from PIL import Image, ImageOps, UnidentifiedImageError
from rest_framework.exceptions import ValidationError

ALLOWED_FORMATS = {"JPEG", "PNG", "WEBP"}
MAX_SIDE = 1600
THUMB_SIDE = 480


def _encode(img, max_side):
    img = img.copy()
    img.thumbnail((max_side, max_side))
    out = io.BytesIO()
    img.save(out, format="JPEG", quality=85, optimize=True, progressive=True)
    return out.getvalue()


def process_upload(uploaded):
    """Return (main ContentFile, thumb ContentFile) or raise ValidationError."""
    if uploaded.size > settings.MAX_IMAGE_UPLOAD_BYTES:
        raise ValidationError({"image": "Image is larger than 8 MB."})
    try:
        img = Image.open(uploaded)
        fmt = img.format
        img.verify()
        uploaded.seek(0)
        img = Image.open(uploaded)
    except (UnidentifiedImageError, OSError, SyntaxError):
        raise ValidationError({"image": "File is not a valid image."})
    if fmt not in ALLOWED_FORMATS:
        raise ValidationError({"image": "Only JPEG, PNG or WEBP images are allowed."})
    if img.width * img.height > 40_000_000:
        raise ValidationError({"image": "Image dimensions are too large."})
    img = ImageOps.exif_transpose(img)
    if img.mode in ("RGBA", "LA", "P"):
        img = img.convert("RGBA")
        background = Image.new("RGB", img.size, (255, 255, 255))
        background.paste(img, mask=img.split()[-1])
        img = background
    else:
        img = img.convert("RGB")
    name = uuid.uuid4().hex
    return (
        ContentFile(_encode(img, MAX_SIDE), name=f"{name}.jpg"),
        ContentFile(_encode(img, THUMB_SIDE), name=f"{name}_t.jpg"),
    )


def absolute_media_url(field):
    if not field:
        return None
    return f"{settings.PUBLIC_BASE_URL}{field.url}"
