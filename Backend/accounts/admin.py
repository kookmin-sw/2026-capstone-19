from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin

from .models import User, WithdrawalBlock


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    list_display = (
        "id",
        "username",
        "nickname",
        "user_real_name",
        "phone_number",
        "gender",
        "trust_score",
        "penalty_points",
        "is_suspended",
        "is_warning_active",
        "is_active",
        "is_staff",
        "date_joined",
    )

    list_filter = (
        "gender",
        "is_suspended",
        "is_warning_active",
        "is_active",
        "is_staff",
        "is_superuser",
    )

    search_fields = (
        "username",
        "nickname",
        "user_real_name",
        "phone_number",
    )

    ordering = ("-id",)

    fieldsets = (
        ("로그인 정보", {
            "fields": ("username", "password")
        }),
        ("기본 정보", {
            "fields": ("user_real_name", "nickname", "phone_number", "gender", "profile_img_url")
        }),
        ("신뢰/패널티 정보", {
            "fields": (
                "trust_score",
                "penalty_points",
                "successful_streak_count",
                "is_warning_active",
                "last_score_updated_at",
            )
        }),
        ("정지 정보", {
            "fields": (
                "is_suspended",
                "suspended_until",
            )
        }),
        ("권한 정보", {
            "fields": (
                "is_active",
                "is_staff",
                "is_superuser",
                "groups",
                "user_permissions",
            )
        }),
        ("기록", {
            "fields": (
                "last_login",
                "date_joined",
                "created_at",
                "updated_at",
            )
        }),
    )

    readonly_fields = (
        "last_login",
        "date_joined",
        "created_at",
        "updated_at",
    )

    add_fieldsets = (
        (
            "회원 생성",
            {
                "classes": ("wide",),
                "fields": (
                    "username",
                    "nickname",
                    "user_real_name",
                    "phone_number",
                    "gender",
                    "password1",
                    "password2",
                    "is_active",
                    "is_staff",
                    "is_superuser",
                ),
            },
        ),
    )


@admin.register(WithdrawalBlock)
class WithdrawalBlockAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "phone_number",
        "status",
        "trust_score_at_withdrawal",
        "blocked_until",
        "withdrawn_user",
        "created_at",
    )

    list_filter = (
        "status",
        "created_at",
        "blocked_until",
    )

    search_fields = (
        "phone_number",
        "withdrawn_user__username",
        "withdrawn_user__nickname",
    )

    ordering = ("-created_at",)

    readonly_fields = (
        "created_at",
        "updated_at",
    )