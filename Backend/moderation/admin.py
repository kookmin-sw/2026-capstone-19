from django.contrib import admin

from .models import Review, Penalty, Report, TrustScoreLog


@admin.register(Review)
class ReviewAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "trip",
        "from_user",
        "to_user",
        "rating",
        "created_at",
    )
    search_fields = (
        "from_user__username",
        "to_user__username",
        "from_user__nickname",
        "to_user__nickname",
        "comment",
    )
    list_filter = ("rating", "created_at")
    ordering = ("-created_at",)
    readonly_fields = ("created_at",)


@admin.register(Penalty)
class PenaltyAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "user",
        "trip",
        "type",
        "points",
        "created_at",
    )
    search_fields = (
        "user__username",
        "user__nickname",
        "type",
        "reason",
    )
    list_filter = ("type", "created_at")
    ordering = ("-created_at",)
    readonly_fields = ("created_at",)


@admin.register(Report)
class ReportAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "trip",
        "reporter_user",
        "reported_user",
        "reason",
        "status",
        "created_at",
    )
    list_filter = ("status", "created_at")
    search_fields = (
        "reporter_user__username",
        "reported_user__username",
        "reporter_user__nickname",
        "reported_user__nickname",
        "reason",
        "detail",
    )
    ordering = ("-created_at",)
    readonly_fields = ("created_at",)


@admin.register(TrustScoreLog)
class TrustScoreLogAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "user",
        "event_type",
        "direction",
        "raw_base_score",
        "applied_delta",
        "score_before",
        "score_after",
        "created_at",
    )
    list_filter = (
        "event_type",
        "direction",
        "is_warning_triggered",
        "created_by_system",
        "created_at",
    )
    search_fields = (
        "user__username",
        "user__nickname",
        "reason_detail",
    )
    ordering = ("-created_at",)
    readonly_fields = ("created_at",)