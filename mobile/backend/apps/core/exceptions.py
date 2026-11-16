from rest_framework.views import exception_handler as drf_exception_handler


def exception_handler(exc, context):
    """Always return {"detail": ..., "code": ...} plus field errors so apps can show one message."""
    response = drf_exception_handler(exc, context)
    if response is None:
        return None
    data = response.data
    if isinstance(data, dict) and "detail" not in data:
        first = next(iter(data.values()), "")
        if isinstance(first, list) and first:
            first = first[0]
        response.data = {"detail": str(first), "code": "invalid", "errors": data}
    elif isinstance(data, list):
        response.data = {"detail": str(data[0]) if data else "", "code": "invalid"}
    else:
        code = getattr(getattr(exc, "detail", None), "code", None) or getattr(exc, "default_code", "error")
        response.data.setdefault("code", code)
    return response
