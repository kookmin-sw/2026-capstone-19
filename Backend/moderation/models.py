from decimal import Decimal

from django.conf import settings
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.db.models import Q

from trips.models import Trip
from settlements.models import Settlement

class Review(models.Model):
    trip = models.ForeignKey(
        Trip,
        on_delete=models.CASCADE,
        related_name="reviews",
    )
    from_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="reviews_written",
    )
    to_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="reviews_received",
    )
    rating = models.IntegerField(
        validators=[MinValueValidator(1), MaxValueValidator(5)]
    )
    tags = models.JSONField(blank=True, null=True)
    comment = models.CharField(max_length=200, blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["trip", "from_user", "to_user"],
                name="unique_trip_review_pair",
            ),
            models.CheckConstraint(
                condition=Q(rating__gte=1) & Q(rating__lte=5),
                name="moderation_review_rating_range",
            ),
        ]

    def __str__(self):
        return f"Review {self.id}"


class Penalty(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="penalties",
    )
    trip = models.ForeignKey(
        Trip,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="penalties",
    )
    type = models.CharField(max_length=30)
    points = models.IntegerField(validators=[MinValueValidator(1)])
    reason = models.CharField(max_length=200, blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        constraints = [
            models.CheckConstraint(
                condition=Q(points__gt=0),
                name="moderation_penalty_points_positive",
            ),
        ]

    def __str__(self):
        return f"Penalty {self.id}"


class Report(models.Model):
    STATUS_CHOICES = [
        ("OPEN", "OPEN"),
        ("REVIEWED", "REVIEWED"),
        ("ACTIONED", "ACTIONED"),
    ]

    trip = models.ForeignKey(
        Trip,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="reports",
    )
    reporter_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="reports_made",
    )
    reported_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="reports_received",
    )
    reason = models.CharField(max_length=50)
    detail = models.TextField(blank=True, null=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default="OPEN")
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Report {self.id}"
    
class TrustScoreLog(models.Model):
    DIRECTION_CHOICES = [
        ("GAIN", "GAIN"),
        ("PENALTY", "PENALTY"),
        ("ADJUST", "ADJUST"),
    ]

    EVENT_TYPE_CHOICES = [
        ("TRIP_LEADER_SUCCESS", "TRIP_LEADER_SUCCESS"),
        ("TRIP_PARTICIPATION_COMPLETE", "TRIP_PARTICIPATION_COMPLETE"),
        ("FAST_SETTLEMENT", "FAST_SETTLEMENT"),
        ("STREAK_BONUS", "STREAK_BONUS"),
        ("NORMAL_CANCEL", "NORMAL_CANCEL"),
        ("URGENT_CANCEL", "URGENT_CANCEL"),
        ("NO_SHOW", "NO_SHOW"),
        ("MANUAL_ADJUST", "MANUAL_ADJUST"),
    ]

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="trust_score_logs",
    )

    event_type = models.CharField(max_length=40, choices=EVENT_TYPE_CHOICES)
    direction = models.CharField(max_length=10, choices=DIRECTION_CHOICES)

    raw_base_score = models.DecimalField(
        max_digits=4,
        decimal_places=1,
        validators=[
            MinValueValidator(Decimal("-20.0")),
            MaxValueValidator(Decimal("20.0")),
        ],
    )
    applied_delta = models.DecimalField(
        max_digits=4,
        decimal_places=1,
        validators=[
            MinValueValidator(Decimal("-20.0")),
            MaxValueValidator(Decimal("20.0")),
        ],
    )

    score_before = models.DecimalField(
        max_digits=4,
        decimal_places=1,
        validators=[
            MinValueValidator(Decimal("0.0")),
            MaxValueValidator(Decimal("99.9")),
        ],
    )
    score_after = models.DecimalField(
        max_digits=4,
        decimal_places=1,
        validators=[
            MinValueValidator(Decimal("0.0")),
            MaxValueValidator(Decimal("99.9")),
        ],
    )

    formula_multiplier = models.DecimalField(
        max_digits=4,
        decimal_places=2,
        blank=True,
        null=True,
    )

    reason_detail = models.TextField(blank=True, null=True)

    related_trip = models.ForeignKey(
        Trip,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="trust_score_logs",
    )
    related_penalty = models.ForeignKey(
        "moderation.Penalty",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="trust_score_logs",
    )
    related_review = models.ForeignKey(
        "moderation.Review",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="trust_score_logs",
    )
    related_settlement = models.ForeignKey(
        Settlement,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="trust_score_logs",
    )

    streak_count_after = models.PositiveIntegerField(blank=True, null=True)
    is_warning_triggered = models.BooleanField(default=False)

    created_by_system = models.BooleanField(default=False)
    actor_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="performed_trust_score_logs",
    )

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.CheckConstraint(
                condition=Q(raw_base_score__gte=-20.0) & Q(raw_base_score__lte=20.0),
                name="moderation_trustscorelog_raw_base_score_range",
            ),
            models.CheckConstraint(
                condition=Q(applied_delta__gte=-20.0) & Q(applied_delta__lte=20.0),
                name="moderation_trustscorelog_applied_delta_range",
            ),
            models.CheckConstraint(
                condition=Q(score_before__gte=0.0) & Q(score_before__lte=99.9),
                name="moderation_trustscorelog_score_before_range",
            ),
            models.CheckConstraint(
                condition=Q(score_after__gte=0.0) & Q(score_after__lte=99.9),
                name="moderation_trustscorelog_score_after_range",
            ),
            models.CheckConstraint(
                condition=Q(streak_count_after__isnull=True) | Q(streak_count_after__gte=0),
                name="moderation_trustscorelog_streak_count_nonnegative_or_null",
            ),
        ]

    def __str__(self):
        return f"{self.user_id} {self.event_type} {self.applied_delta}"