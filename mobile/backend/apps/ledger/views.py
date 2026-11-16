from rest_framework import permissions
from rest_framework.views import APIView

from apps.core.pagination import Pagination

from . import services
from .serializers import LedgerEntrySerializer, summary_payload


def statement_response(request, view, user, serializer_class):
    paginator = Pagination()
    page = paginator.paginate_queryset(services.statement(user), request, view=view)
    response = paginator.get_paginated_response(serializer_class(page, many=True).data)
    response.data["summary"] = summary_payload(services.credit_info(user))
    return response


class StatementView(APIView):
    """The signed-in customer's account statement: balance, credit limit and all entries."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        return statement_response(request, self, request.user, LedgerEntrySerializer)
