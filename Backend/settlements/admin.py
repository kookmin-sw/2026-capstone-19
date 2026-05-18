from django.contrib import admin

from .models import PaymentChannel, Receipt, Settlement, SettlementProof


@admin.register(PaymentChannel)
class PaymentChannelAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "trip",
        "updated_by",
        "updated_at",
    )
    list_filter = ("updated_at",)
    search_fields = (
        "trip__depart_name",
        "trip__arrive_name",
        "updated_by__username",
        "updated_by__nickname",
    )
    ordering = ("-updated_at",)
    readonly_fields = ("updated_at",)


@admin.register(Receipt)
class ReceiptAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "trip",
        "uploaded_by",
        "total_amount",
        "status",
        "confirmed_at",
        "created_at",
    )
    list_filter = ("status", "created_at", "confirmed_at")
    search_fields = (
        "trip__depart_name",
        "trip__arrive_name",
        "uploaded_by__username",
        "uploaded_by__nickname",
        "image_url",
    )
    ordering = ("-created_at",)
    readonly_fields = ("created_at",)


@admin.register(Settlement)
class SettlementAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "trip",
        "receipt",
        "payer_user",
        "payee_user",
        "share_amount",
        "status",
        "requested_at",
        "confirmed_at",
        "due_at",
    )
    list_filter = ("status", "requested_at", "confirmed_at", "due_at")
    search_fields = (
        "payer_user__username",
        "payer_user__nickname",
        "payee_user__username",
        "payee_user__nickname",
        "trip__depart_name",
        "trip__arrive_name",
        "memo_code",
    )
    ordering = ("-requested_at",)
    readonly_fields = ("requested_at",)


@admin.register(SettlementProof)
class SettlementProofAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "settlement",
        "uploaded_by",
        "created_at",
    )
    search_fields = (
        "uploaded_by__username",
        "uploaded_by__nickname",
        "image_url",
    )
    ordering = ("-created_at",)
    readonly_fields = ("created_at",)