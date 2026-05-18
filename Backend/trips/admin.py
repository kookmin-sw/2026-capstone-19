from django.contrib import admin

from .models import Trip, TripParticipant


@admin.register(Trip)
class TripAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "creator_user",
        "leader_user",
        "depart_name",
        "arrive_name",
        "depart_time",
        "capacity",
        "status",
        "estimated_fare",
        "created_at",
    )

    list_filter = (
        "status",
        "capacity",
        "created_at",
    )

    search_fields = (
        "creator_user__username",
        "creator_user__nickname",
        "leader_user__username",
        "leader_user__nickname",
        "depart_name",
        "arrive_name",
    )

    ordering = ("-id",)

    readonly_fields = ("created_at",)


@admin.register(TripParticipant)
class TripParticipantAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "trip",
        "user",
        "role",
        "status",
        "seat_position",
        "confirmed_departure",
        "joined_at",
        "left_at",
    )

    list_filter = (
        "role",
        "status",
        "confirmed_departure",
        "seat_position",
        "joined_at",
    )

    search_fields = (
        "trip__id",
        "user__username",
        "user__nickname",
    )

    ordering = ("-id",)

    readonly_fields = (
        "joined_at",
    )