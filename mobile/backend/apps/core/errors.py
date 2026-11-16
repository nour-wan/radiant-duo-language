from rest_framework.exceptions import APIException


class BusinessError(APIException):
    """A 400 error with a stable machine code (apps translate the code)."""

    status_code = 400
    default_detail = "Request could not be completed."
    default_code = "business_error"

    def __init__(self, code, detail=None, **extra):
        super().__init__(detail or code, code)
        self.code = code
        self.extra = extra
