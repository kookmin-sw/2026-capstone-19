from rest_framework import serializers

from .models import PaymentChannel, Receipt, Settlement, SettlementProof


class PaymentChannelSerializer(serializers.ModelSerializer):
    trip_id = serializers.IntegerField(source="trip.id", read_only=True)

    class Meta:
        model = PaymentChannel
        fields = [
            "id",
            "trip_id",
            "provider",
            "kakaopay_link",
            "updated_by",
            "updated_at",
        ]
        read_only_fields = [
            "id",
            "trip_id",
            "updated_by",
            "updated_at",
        ]


class PaymentChannelUpsertSerializer(serializers.ModelSerializer):
    class Meta:
        model = PaymentChannel
        fields = [
            "provider",
            "kakaopay_link",
        ]

    def validate_kakaopay_link(self, value):
        if not value:
            raise serializers.ValidationError("송금 링크를 입력해야 합니다.")

        if not value.startswith("http://") and not value.startswith("https://"):
            raise serializers.ValidationError("송금 링크는 http:// 또는 https://로 시작해야 합니다.")
        if "qr.kakaopay.com" not in value:
                raise serializers.ValidationError("올바른 카카오페이 송금 링크 형식이 아닙니다.")

        return value


class ReceiptSerializer(serializers.ModelSerializer):
    trip_id = serializers.IntegerField(source="trip.id", read_only=True)
    uploaded_by_id = serializers.IntegerField(source="uploaded_by.id", read_only=True)
    receipt_image_url = serializers.SerializerMethodField()

    class Meta:
        model = Receipt
        fields = [
            "id",
            "trip_id",
            "uploaded_by_id",
            "image",
            "image_url",
            "receipt_image_url",
            "total_amount",
            "ocr_raw_text",
            "extracted_total_amount",
            "extracted_departure_name",
            "extracted_arrival_name",
            "extracted_ride_time",
            "ocr_status",
            "status",
            "confirmed_at",
            "created_at",
            "updated_at",
        ]
        read_only_fields = [
            "id",
            "trip_id",
            "uploaded_by_id",
            "receipt_image_url",
            "ocr_raw_text",
            "extracted_total_amount",
            "extracted_departure_name",
            "extracted_arrival_name",
            "extracted_ride_time",
            "ocr_status",
            "status",
            "confirmed_at",
            "created_at",
            "updated_at",
        ]

    def get_receipt_image_url(self, obj):
        request = self.context.get("request")
        image_url = obj.get_display_image_url()

        if image_url and request:
            return request.build_absolute_uri(image_url)

        return image_url


class ReceiptCreateSerializer(serializers.ModelSerializer):
    reset_existing = serializers.BooleanField(
        required=False,
        default=False,
        write_only=True,
    )

    class Meta:
        model = Receipt
        fields = [
            "image",
            "image_url",
            "total_amount",
            "reset_existing",
        ]
        extra_kwargs = {
            "image": {"required": False},
            "image_url": {"required": False},
            "total_amount": {"required": False},
        }

    def validate(self, attrs):
        image = attrs.get("image")
        image_url = attrs.get("image_url")

        if not image and not image_url:
            raise serializers.ValidationError("영수증 이미지 또는 이미지 URL이 필요합니다.")

        return attrs


class ReceiptOCRResultSerializer(serializers.ModelSerializer):
    trip_id = serializers.IntegerField(source="trip.id", read_only=True)
    uploaded_by_id = serializers.IntegerField(source="uploaded_by.id", read_only=True)
    receipt_image_url = serializers.SerializerMethodField()

    class Meta:
        model = Receipt
        fields = [
            "id",
            "trip_id",
            "uploaded_by_id",
            "receipt_image_url",
            "ocr_status",
            "ocr_raw_text",
            "extracted_total_amount",
            "extracted_departure_name",
            "extracted_arrival_name",
            "extracted_ride_time",
            "total_amount",
            "status",
            "confirmed_at",
            "created_at",
            "updated_at",
        ]

    def get_receipt_image_url(self, obj):
        request = self.context.get("request")
        image_url = obj.get_display_image_url()

        if image_url and request:
            return request.build_absolute_uri(image_url)

        return image_url


class ReceiptConfirmAmountSerializer(serializers.Serializer):
    total_amount = serializers.IntegerField(min_value=0, max_value=300000)


class SettlementProofSerializer(serializers.ModelSerializer):
    uploaded_by_id = serializers.IntegerField(source="uploaded_by.id", read_only=True)

    class Meta:
        model = SettlementProof
        fields = [
            "id",
            "uploaded_by_id",
            "image_url",
            "created_at",
        ]
        read_only_fields = [
            "id",
            "uploaded_by_id",
            "created_at",
        ]


class SettlementSerializer(serializers.ModelSerializer):
    trip_id = serializers.IntegerField(source="trip.id", read_only=True)
    receipt_id = serializers.IntegerField(source="receipt.id", read_only=True)
    payer_user_id = serializers.IntegerField(source="payer_user.id", read_only=True)
    payee_user_id = serializers.IntegerField(source="payee_user.id", read_only=True)
    verified_by_id = serializers.IntegerField(source="verified_by.id", read_only=True)
    proofs = SettlementProofSerializer(many=True, read_only=True)

    total_amount = serializers.IntegerField(source="receipt.total_amount", read_only=True)
    receipt_image_url = serializers.SerializerMethodField()
    payment_channel = serializers.SerializerMethodField()

    class Meta:
        model = Settlement
        fields = [
            "id",
            "trip_id",
            "receipt_id",
            "payer_user_id",
            "payee_user_id",
            "share_amount",
            "memo_code",
            "status",
            "verification_method",
            "verified_by_id",
            "requested_at",
            "link_opened_at",
            "paid_self_at",
            "confirmed_at",
            "due_at",
            "total_amount",
            "receipt_image_url",
            "payment_channel",
            "proofs",
        ]

    def get_receipt_image_url(self, obj):
        request = self.context.get("request")
        image_url = obj.receipt.get_display_image_url()

        if image_url and request:
            return request.build_absolute_uri(image_url)

        return image_url

    def get_payment_channel(self, obj):
        channel = getattr(obj.trip, "payment_channel", None)

        if not channel:
            return None

        return {
            "provider": channel.provider,
            "kakaopay_link": channel.kakaopay_link,
        }


class SettlementPaySelfSerializer(serializers.Serializer):
    pass


class SettlementLinkOpenSerializer(serializers.Serializer):
    pass


class SettlementConfirmSerializer(serializers.Serializer):
    pass


class SettlementDisputeSerializer(serializers.Serializer):
    pass


class SettlementProofCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = SettlementProof
        fields = ["image_url"]