from django.conf import settings
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.db.models import Q

class Trip(models.Model):
    class StatusChoices(models.TextChoices):
        OPEN = "OPEN", "OPEN"
        FULL = "FULL", "FULL"
        CANCELED = "CANCELED", "CANCELED"
        CLOSED = "CLOSED", "CLOSED"
        COMPLETED = "COMPLETED", "COMPLETED"

    creator_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="trips_created",
    )
    leader_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="trips_led",
    )

    depart_name = models.CharField(max_length=80)
    depart_lat = models.DecimalField(max_digits=9, decimal_places=6)
    depart_lng = models.DecimalField(max_digits=9, decimal_places=6)

    arrive_name = models.CharField(max_length=80)
    arrive_lat = models.DecimalField(max_digits=9, decimal_places=6)
    arrive_lng = models.DecimalField(max_digits=9, decimal_places=6)

    depart_time = models.DateTimeField()
    capacity = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(2), MaxValueValidator(4)]
    )
    status = models.CharField(
        max_length=20,
        choices=StatusChoices.choices,
        default=StatusChoices.OPEN,
    )
    estimated_fare = models.PositiveIntegerField(blank=True, null=True)

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.CheckConstraint(
                condition=Q(capacity__gte=2) & Q(capacity__lte=4),
                name="trips_trip_capacity_range",
            ),
        ]

    def __str__(self):
        return f"{self.depart_name} -> {self.arrive_name} ({self.depart_time})"


class TripParticipant(models.Model):
    class RoleChoices(models.TextChoices):
        LEADER = "LEADER", "LEADER"
        MEMBER = "MEMBER", "MEMBER"

    class StatusChoices(models.TextChoices):
        JOINED = "JOINED", "JOINED"
        LEFT = "LEFT", "LEFT"
        KICKED = "KICKED", "KICKED"

    class SeatChoices(models.TextChoices):
        FRONT_PASSENGER = "FRONT_PASSENGER", "앞좌석"
        REAR_LEFT = "REAR_LEFT", "뒷좌석 왼쪽"
        REAR_RIGHT = "REAR_RIGHT", "뒷좌석 오른쪽"
        REAR_MIDDLE = "REAR_MIDDLE", "뒷좌석 가운데"

    trip = models.ForeignKey(
        Trip,
        on_delete=models.CASCADE,
        related_name="trip_participants",
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="trip_participants",
    )
    role = models.CharField(
        max_length=20,
        choices=RoleChoices.choices,
        default=RoleChoices.MEMBER,
    )
    status = models.CharField(
        max_length=20,
        choices=StatusChoices.choices,
        default=StatusChoices.JOINED,
    )
    seat_position = models.CharField(
        max_length=30,
        choices=SeatChoices.choices,
        blank=True,
        null=True,
    )
    confirmed_departure = models.BooleanField(default=False)
    joined_at = models.DateTimeField(auto_now_add=True)
    left_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["trip", "user"],
                name="unique_trip_participant",
            ),
            models.UniqueConstraint(
                fields=["trip", "seat_position"],
                condition=Q(status="JOINED", seat_position__isnull=False),
                name="unique_joined_trip_seat_position",
            ),
        ]

    def __str__(self):
        return f"{self.trip_id} - {self.user_id}"