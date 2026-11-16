from rest_framework import serializers

from apps.core.images import absolute_media_url

from .models import Banner


class BannerSerializer(serializers.ModelSerializer):
    image = serializers.SerializerMethodField()

    class Meta:
        model = Banner
        fields = ["id", "image", "title_ar", "title_en", "subtitle_ar", "subtitle_en", "link_type", "link_value"]

    def get_image(self, obj):
        return absolute_media_url(obj.image)
