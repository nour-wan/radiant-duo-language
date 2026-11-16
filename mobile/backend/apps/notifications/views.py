from django.db.models import Q
from django.utils import timezone
from rest_framework import generics, permissions, serializers, status
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import DeviceToken, Notification


class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = ["id", "kind", "title_ar", "title_en", "body_ar", "body_en", "data", "created_at"]


class DeviceTokenSerializer(serializers.Serializer):
    token = serializers.CharField(max_length=512)
    app = serializers.ChoiceField(choices=[DeviceToken.STORE, DeviceToken.ADMIN], default=DeviceToken.STORE)
    platform = serializers.ChoiceField(choices=["android", "ios"], default="android")
    language = serializers.ChoiceField(choices=["ar", "en"], default="ar")


def inbox_for(user):
    """Personal notifications plus broadcasts sent since the customer joined."""
    return Notification.objects.filter(
        Q(user=user) | Q(user__isnull=True, audience={}, created_at__gte=user.date_joined)
    ).order_by("-created_at", "-id")


def unread_count(user):
    qs = inbox_for(user)
    return qs.filter(created_at__gt=user.notifications_seen_at).count() if user.notifications_seen_at else qs.count()


class DeviceTokenView(APIView):
    """Register a push token. Guests may register (to receive offers); admin tokens need a staff login."""

    permission_classes = [permissions.AllowAny]

    def post(self, request):
        s = DeviceTokenSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        data = s.validated_data
        user = request.user if request.user.is_authenticated else None
        if data["app"] == DeviceToken.ADMIN and not (user and user.is_staff):
            return Response({"detail": "forbidden", "code": "forbidden"}, status=status.HTTP_403_FORBIDDEN)
        DeviceToken.objects.update_or_create(
            token=data["token"],
            defaults={"user": user, "app": data["app"], "platform": data["platform"], "language": data["language"]},
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


class InboxView(generics.ListAPIView):
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = NotificationSerializer

    def get_queryset(self):
        return inbox_for(self.request.user)

    def list(self, request, *args, **kwargs):
        response = super().list(request, *args, **kwargs)
        response.data["unread"] = unread_count(request.user)
        return response


class InboxSeenView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        request.user.notifications_seen_at = timezone.now()
        request.user.save(update_fields=["notifications_seen_at"])
        return Response(status=status.HTTP_204_NO_CONTENT)


class UnreadCountView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        return Response({"unread": unread_count(request.user)})
