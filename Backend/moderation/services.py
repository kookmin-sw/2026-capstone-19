from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal, ROUND_HALF_UP
from typing import Optional

from django.db import transaction
from django.utils import timezone

from accounts.models import User
from moderation.models import TrustScoreLog


DECIMAL_TENTH = Decimal("0.1")
SCORE_MIN = Decimal("0.0")
SCORE_MAX = Decimal("99.9")
WARNING_THRESHOLD = Decimal("20.0")


TRUST_EVENT_BASE_SCORES: dict[str, Decimal] = {
    # Gain
    "TRIP_LEADER_SUCCESS": Decimal("4.0"),  # 방장성공
    "TRIP_PARTICIPATION_COMPLETED": Decimal("3.0"),
    "FAST_SETTLEMENT": Decimal("2.0"),
    "STREAK_BONUS": Decimal("5.0"),
    # Penalty
    "NORMAL_CANCEL": Decimal("-2.0"),
    "URGENT_CANCEL": Decimal("-5.0"),
    "NO_SHOW": Decimal("-15.0"),  # 노쇼
    "MANUAL_ADJUST": Decimal("0.0"),
}


class TrustScoreUpdateError(Exception):
    pass


class UserNotFoundError(TrustScoreUpdateError):
    pass


@dataclass(frozen=True)
class TrustScoreUpdateResult:
    user_id: int
    event_type: str
    raw_base_score: Decimal
    applied_delta: Decimal
    score_before: Decimal
    score_after: Decimal
    is_warning_triggered: bool
    log_id: int


def _q1(x: Decimal) -> Decimal:
    return x.quantize(DECIMAL_TENTH, rounding=ROUND_HALF_UP)


def _clamp_score(score: Decimal) -> Decimal:
    if score < SCORE_MIN:
        return SCORE_MIN
    if score > SCORE_MAX:
        return SCORE_MAX
    return score


def _gain_multiplier(current_score: Decimal) -> Decimal:
    """
    Actual Gain = Base Gain * min(1.0, 1.5 - (current_score / 100))
    - score < 50  -> multiplier becomes 1.0 (full gain)
    - score >= 50 -> multiplier decreases as score increases
    """
    multiplier = Decimal("1.5") - (current_score / Decimal("100"))
    if multiplier > Decimal("1.0"):
        multiplier = Decimal("1.0")
    if multiplier < Decimal("0.0"):
        multiplier = Decimal("0.0")
    return multiplier


def update_trust_score(
    *,
    user_id: int,
    event_type: str,
    raw_base_score: Optional[Decimal] = None,
    reason_detail: Optional[str] = None,
    related_trip_id: Optional[int] = None,
    created_by_system: bool = True,
    actor_user_id: Optional[int] = None,
) -> TrustScoreUpdateResult:
    """
    Updates `User.trust_score` and creates a `TrustScoreLog` receipt row atomically.
    All calculations are performed with `decimal.Decimal` to avoid floating point errors.
    """
    if raw_base_score is None:
        if event_type not in TRUST_EVENT_BASE_SCORES:
            raise TrustScoreUpdateError(f"Unknown event_type: {event_type}")
        raw_base_score = TRUST_EVENT_BASE_SCORES[event_type]

    raw_base_score = _q1(Decimal(raw_base_score))

    with transaction.atomic():
        user = (
            User.objects.select_for_update()
            .filter(id=user_id)
            .only("id", "trust_score", "is_warning_active")
            .first()
        )
        if user is None:
            raise UserNotFoundError(f"User not found: {user_id}")

        score_before = _q1(Decimal(user.trust_score))

        if raw_base_score >= Decimal("0.0"):
            multiplier = _gain_multiplier(score_before)
            applied_delta = _q1(raw_base_score * multiplier)
            direction = "ADJUST" if event_type == "MANUAL_ADJUST" else "GAIN"
            formula_multiplier: Optional[Decimal] = multiplier.quantize(
                Decimal("0.01"), rounding=ROUND_HALF_UP
            )
        else:
            applied_delta = _q1(raw_base_score)
            direction = "PENALTY"
            formula_multiplier = None

        score_after = _q1(_clamp_score(score_before + applied_delta))

        is_warning_triggered = False
        if (event_type == "NO_SHOW") and (not user.is_warning_active):
            user.is_warning_active = True
            is_warning_triggered = True
        elif score_after < WARNING_THRESHOLD and not user.is_warning_active:
            user.is_warning_active = True
            is_warning_triggered = True
        elif score_after >= WARNING_THRESHOLD and user.is_warning_active:
            user.is_warning_active = False

        user.trust_score = score_after
        user.last_score_updated_at = timezone.now()
        user.save(update_fields=["trust_score", "is_warning_active", "last_score_updated_at"])

        log = TrustScoreLog.objects.create(
            user_id=user.id,
            event_type=event_type,
            direction=direction,
            raw_base_score=raw_base_score,
            applied_delta=applied_delta,
            score_before=score_before,
            score_after=score_after,
            formula_multiplier=formula_multiplier,
            reason_detail=reason_detail,
            related_trip_id=related_trip_id,
            is_warning_triggered=is_warning_triggered,
            created_by_system=created_by_system,
            actor_user_id=actor_user_id,
            streak_count_after=None,
            related_penalty_id=None,
            related_review_id=None,
            related_settlement_id=None,
        )

    return TrustScoreUpdateResult(
        user_id=user.id,
        event_type=event_type,
        raw_base_score=raw_base_score,
        applied_delta=applied_delta,
        score_before=score_before,
        score_after=score_after,
        is_warning_triggered=is_warning_triggered,
        log_id=log.id,
    )

