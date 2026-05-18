import re

from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import PermissionDenied, ValidationError

from trips.models import TripParticipant
from .models import PaymentChannel, Receipt, Settlement, SettlementProof
import base64
import json
import mimetypes
import time
import uuid
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from django.conf import settings
from datetime import timedelta
from chat.models import ChatRoom
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer


def _validate_trip_leader(*, trip, user):
    if trip.leader_user_id != user.id:
        raise PermissionDenied("방장만 수행할 수 있습니다.")


def _validate_trip_participant(*, trip, user):
    exists = TripParticipant.objects.filter(
        trip=trip,
        user=user,
        status="JOINED",
    ).exists()
    if not exists:
        raise PermissionDenied("현재 참가 중인 사용자만 수행할 수 있습니다.")


@transaction.atomic
def upsert_payment_channel(*, trip, user, validated_data):
    _validate_trip_leader(trip=trip, user=user)

    channel, _ = PaymentChannel.objects.update_or_create(
        trip=trip,
        defaults={
            "provider": validated_data.get("provider", "KAKAOPAY"),
            "kakaopay_link": validated_data.get("kakaopay_link"),
            "updated_by": user,
        },
    )
    return channel


def extract_total_amount_from_text(raw_text: str):
    """
    OCR 원문에서 결제 금액 후보를 추출한다.
    MVP에서는 완전한 진위 검증이 아니라 금액 자동 입력 보조 기능으로 사용한다.
    """
    if not raw_text:
        return None

    text = raw_text.replace("\n", " ")

    patterns = [
        r"(?:결제\s*금액|총\s*결제\s*금액|총\s*금액|합계|결제금액|택시요금|운임)[^\d]{0,20}([\d,]{4,})\s*원?",
        r"([\d,]{4,})\s*원",
    ]

    candidates = []

    for pattern in patterns:
        matches = re.findall(pattern, text)
        for match in matches:
            amount = int(match.replace(",", ""))
            if 1000 <= amount <= 300000:
                candidates.append(amount)

    if not candidates:
        return None

    return max(candidates)


def extract_ride_time_from_text(raw_text: str, *, base_depart_time=None):
    """
    OCR 원문에서 실제 택시 운행 시작 시각을 추출한다.

    카카오T 이용내역 기준:
    - 결제일시에서는 날짜만 사용한다. 예: 26.05.13 16:30 -> 2026-05-13
    - 운행시간에서는 출발시간만 사용한다. 예: 15:50 - 16:30 -> 15:50
    - 최종 검증 시각은 결제일시의 날짜 + 운행시간의 출발시간이다.
    """
    if not raw_text:
        return None

    text = raw_text.replace("\n", " ")

    def normalize_year(year_text):
        year = int(year_text)
        if year < 100:
            return 2000 + year
        return year

    def get_base_date():
        """
        결제일시에서 날짜를 우선 추출한다.
        결제일시 날짜를 못 찾으면 모집 출발시각의 날짜를 사용한다.
        """
        payment_date_patterns = [
            r"결제\s*일시[^\d]{0,20}(20\d{2}|\d{2})[.\-/년\s]+(\d{1,2})[.\-/월\s]+(\d{1,2})",
            r"(20\d{2}|\d{2})[.\-/](\d{1,2})[.\-/](\d{1,2})\s+\d{1,2}[:시]\d{2}",
        ]

        for pattern in payment_date_patterns:
            match = re.search(pattern, text)
            if match:
                year_text, month_text, day_text = match.groups()
                return (
                    normalize_year(year_text),
                    int(month_text),
                    int(day_text),
                )

        if base_depart_time:
            local_base_depart_time = (
                timezone.localtime(base_depart_time)
                if timezone.is_aware(base_depart_time)
                else base_depart_time
            )
            return (
                local_base_depart_time.year,
                local_base_depart_time.month,
                local_base_depart_time.day,
            )

        return None

    base_date = get_base_date()
    if not base_date:
        return None

    year, month, day = base_date

    # 운행시간 15:50 - 16:30 / 운행 시간 15:50~16:30
    ride_time_patterns = [
        r"운행\s*시간[^\d]{0,30}(\d{1,2})[:시](\d{2})\s*(?:[-~–—]|부터|→|to)\s*(\d{1,2})[:시](\d{2})",
        r"(?<!\d)(\d{1,2})[:시](\d{2})\s*(?:[-~–—]|부터|→|to)\s*(\d{1,2})[:시](\d{2})(?!\d)",
    ]

    for pattern in ride_time_patterns:
        match = re.search(pattern, text)
        if match:
            start_hour, start_minute = int(match.group(1)), int(match.group(2))

            if 0 <= start_hour <= 23 and 0 <= start_minute <= 59:
                try:
                    return timezone.make_aware(
                        timezone.datetime(year, month, day, start_hour, start_minute),
                        timezone.get_current_timezone(),
                    )
                except ValueError:
                    return None

    return None


def run_ocr_for_receipt(receipt: Receipt) -> str:
    """
    Naver CLOVA OCR API를 호출하여 영수증/이용내역 이미지의 전체 텍스트를 반환한다.
    반환된 원문에서 금액 추출은 extract_total_amount_from_text()가 담당한다.
    """
    ocr_url = getattr(settings, "CLOVA_OCR_URL", "")
    ocr_secret = getattr(settings, "CLOVA_OCR_SECRET", "")

    if not ocr_url or not ocr_secret:
        raise ValidationError("CLOVA OCR URL 또는 Secret Key가 설정되지 않았습니다.")

    if not receipt.image:
        raise ValidationError("현재 CLOVA OCR 테스트는 업로드된 이미지 파일 기준으로 처리합니다.")

    file_name = receipt.image.name
    mime_type, _ = mimetypes.guess_type(file_name)
    image_format = "jpg"

    if mime_type:
        image_format = mime_type.split("/")[-1]
        if image_format == "jpeg":
            image_format = "jpg"

    receipt.image.open("rb")
    try:
        image_bytes = receipt.image.read()
    finally:
        receipt.image.close()

    image_base64 = base64.b64encode(image_bytes).decode("utf-8")

    request_body = {
        "version": "V2",
        "requestId": str(uuid.uuid4()),
        "timestamp": int(time.time() * 1000),
        "images": [
            {
                "format": image_format,
                "name": "receipt",
                "data": image_base64,
            }
        ],
    }

    request_data = json.dumps(request_body).encode("utf-8")

    request = Request(
        ocr_url,
        data=request_data,
        headers={
            "Content-Type": "application/json",
            "X-OCR-SECRET": ocr_secret,
        },
        method="POST",
    )

    try:
        with urlopen(request, timeout=15) as response:
            response_body = response.read().decode("utf-8")
            result = json.loads(response_body)

    except HTTPError as e:
        error_body = e.read().decode("utf-8", errors="ignore")
        raise ValidationError(f"CLOVA OCR 호출 실패: HTTP {e.code} / {error_body}")

    except URLError as e:
        raise ValidationError(f"CLOVA OCR 연결 실패: {e.reason}")

    except Exception as e:
        raise ValidationError(f"CLOVA OCR 처리 중 오류가 발생했습니다: {str(e)}")

    images = result.get("images", [])
    if not images:
        raise ValidationError("CLOVA OCR 응답에 이미지 분석 결과가 없습니다.")

    fields = images[0].get("fields", [])
    texts = [
        field.get("inferText", "")
        for field in fields
        if field.get("inferText")
    ]

    raw_text = " ".join(texts).strip()

    if not raw_text:
        raise ValidationError("CLOVA OCR에서 인식된 텍스트가 없습니다.")

    return raw_text


@transaction.atomic
def analyze_receipt_ocr(*, receipt: Receipt, actor):
    """
    리더가 업로드한 영수증/이용내역 이미지에서 OCR을 실행하고,
    추출된 금액을 receipt.extracted_total_amount에 저장한다.
    """
    trip = receipt.trip
    _validate_trip_leader(trip=trip, user=actor)

    if not receipt.image and not receipt.image_url:
        raise ValidationError("분석할 영수증 이미지가 없습니다.")

    raw_text = run_ocr_for_receipt(receipt)
    extracted_amount = extract_total_amount_from_text(raw_text)
    extracted_ride_time = extract_ride_time_from_text(
        raw_text,
        base_depart_time=trip.depart_time,
    )

    receipt.ocr_raw_text = raw_text
    receipt.extracted_total_amount = extracted_amount
    receipt.extracted_ride_time = extracted_ride_time

    if extracted_ride_time:
        time_diff_seconds = abs((extracted_ride_time - trip.depart_time).total_seconds())
        time_diff_minutes = int(time_diff_seconds // 60)

        if time_diff_minutes > 30:
            receipt.ocr_status = "FAILED"
            receipt.save(
                update_fields=[
                    "ocr_raw_text",
                    "extracted_total_amount",
                    "extracted_ride_time",
                    "ocr_status",
                    "updated_at",
                ]
            )
            raise ValidationError(
                f"영수증 이용 시간이 모집 출발 시간과 {time_diff_minutes}분 차이납니다. "
                "다른 영수증을 등록하거나 수기 정산을 이용해주세요."
            )

    if extracted_amount is None:
        receipt.ocr_status = "NEEDS_REVIEW"
    else:
        receipt.ocr_status = "SUCCESS"

    receipt.save(
        update_fields=[
            "ocr_raw_text",
            "extracted_total_amount",
            "extracted_ride_time",
            "ocr_status",
            "updated_at",
        ]
    )
    return receipt


@transaction.atomic
def create_receipt(*, trip, user, validated_data):
    _validate_trip_leader(trip=trip, user=user)

    reset_existing = validated_data.pop("reset_existing", False)
    existing_receipt = getattr(trip, "receipt", None)

    if existing_receipt:
        has_existing_settlements = existing_receipt.settlements.exists()

        if has_existing_settlements and not reset_existing:
            raise ValidationError("이미 정산이 생성된 영수증입니다. 기존 정산을 취소한 뒤 다시 등록해주세요.")

        if has_existing_settlements and reset_existing:
            # model/migration을 건드리지 않기 위해 기존 정산 레코드는 삭제한다.
            # 삭제 후 같은 receipt + payer_user 조합으로 새 정산 요청을 다시 만들 수 있다.
            existing_receipt.settlements.all().delete()

        # 정산 요청 생성 전이거나, reset_existing=True로 기존 정산을 정리한 경우
        # 잘못 올린 영수증/OCR 실패 영수증을 새 이미지로 교체한다.
        existing_receipt.uploaded_by = user
        existing_receipt.image = validated_data.get("image")
        existing_receipt.image_url = validated_data.get("image_url")
        existing_receipt.total_amount = validated_data.get("total_amount")

        # OCR/확정 상태를 영수증 등록 직후 상태로 초기화한다.
        existing_receipt.ocr_raw_text = ""
        existing_receipt.extracted_total_amount = None
        existing_receipt.extracted_departure_name = None
        existing_receipt.extracted_arrival_name = None
        existing_receipt.extracted_ride_time = None
        existing_receipt.ocr_status = "PENDING"
        existing_receipt.status = "PENDING"
        existing_receipt.confirmed_at = None

        existing_receipt.save(
            update_fields=[
                "uploaded_by",
                "image",
                "image_url",
                "total_amount",
                "ocr_raw_text",
                "extracted_total_amount",
                "extracted_departure_name",
                "extracted_arrival_name",
                "extracted_ride_time",
                "ocr_status",
                "status",
                "confirmed_at",
                "updated_at",
            ]
        )
        return existing_receipt

    receipt = Receipt.objects.create(
        trip=trip,
        uploaded_by=user,
        image=validated_data.get("image"),
        image_url=validated_data.get("image_url"),
        total_amount=validated_data.get("total_amount"),
        ocr_status="PENDING",
        status="PENDING",
    )
    return receipt


@transaction.atomic
def confirm_receipt_amount(*, receipt: Receipt, actor, total_amount: int):
    """
    OCR로 추출된 금액 또는 리더가 수정한 금액을 최종 정산 금액으로 확정한다.
    """
    trip = receipt.trip
    _validate_trip_leader(trip=trip, user=actor)

    if total_amount is None:
        raise ValidationError("최종 결제 금액이 필요합니다.")

    if total_amount < 0:
        raise ValidationError("결제 금액은 0원 이상이어야 합니다.")

    if total_amount > 300000:
        raise ValidationError("택시 요금으로 보기 어려운 금액입니다.")

    receipt.total_amount = total_amount
    receipt.status = "CONFIRMED"
    receipt.confirmed_at = timezone.now()
    receipt.save(
        update_fields=[
            "total_amount",
            "status",
            "confirmed_at",
            "updated_at",
        ]
    )

    return receipt


@transaction.atomic
def create_settlements_for_receipt(*, receipt: Receipt, actor):
    trip = receipt.trip
    _validate_trip_leader(trip=trip, user=actor)

    if receipt.total_amount is None:
        raise ValidationError("최종 결제 금액이 확정되지 않았습니다.")

    if not hasattr(trip, "payment_channel"):
        raise ValidationError("먼저 결제 링크를 등록해야 합니다.")

    participants = list(
        TripParticipant.objects.filter(
            trip=trip,
            status="JOINED",
        ).select_related("user")
    )

    if len(participants) < 2:
        raise ValidationError("정산하려면 최소 2명 이상의 참가자가 필요합니다.")

    payee_user = receipt.uploaded_by
    participant_user_ids = {p.user_id for p in participants}

    if payee_user.id not in participant_user_ids:
        raise ValidationError("영수증 업로더는 현재 참가자여야 합니다.")

    if receipt.settlements.exists():
        raise ValidationError("이미 정산이 생성된 영수증입니다.")

    headcount = len(participants)
    base_amount = receipt.total_amount // headcount
    remainder = receipt.total_amount % headcount

    created = []
    for participant in participants:
        if participant.user_id == payee_user.id:
            continue

        share_amount = base_amount
        if remainder > 0:
            share_amount += 1
            remainder -= 1

        settlement = Settlement.objects.create(
            trip=trip,
            receipt=receipt,
            payer_user=participant.user,
            payee_user=payee_user,
            share_amount=share_amount,
            status="REQUEST",
        )
        created.append(settlement)

    return created


@transaction.atomic
def mark_settlement_link_opened(*, settlement: Settlement, user):
    """
    참여자가 이용내역 확인 체크박스 선택 후 송금 링크를 열었음을 기록한다.
    실제 송금 완료가 아니라 링크 이동 기록만 남긴다.
    """
    if settlement.payer_user_id != user.id:
        raise PermissionDenied("본인 정산만 처리할 수 있습니다.")

    if settlement.status not in ["REQUEST", "LINK_OPENED"]:
        raise ValidationError("현재 송금 링크를 열 수 없는 상태입니다.")

    settlement.status = "LINK_OPENED"
    settlement.link_opened_at = timezone.now()
    settlement.save(update_fields=["status", "link_opened_at"])
    return settlement


@transaction.atomic
def mark_settlement_paid_self(*, settlement: Settlement, user):
    if settlement.payer_user_id != user.id:
        raise PermissionDenied("본인 정산만 송금 완료 처리할 수 있습니다.")

    if settlement.status not in ["REQUEST", "LINK_OPENED"]:
        raise ValidationError("현재 송금 완료 처리할 수 없는 상태입니다.")

    settlement.status = "PAID_SELF"
    settlement.paid_self_at = timezone.now()
    settlement.save(update_fields=["status", "paid_self_at"])
    return settlement


@transaction.atomic
def upload_settlement_proof(*, settlement: Settlement, user, image_url: str):
    if settlement.payer_user_id != user.id:
        raise PermissionDenied("본인 정산에만 증빙을 업로드할 수 있습니다.")

    if settlement.status not in ["REQUEST", "PAID_SELF", "DISPUTED"]:
        raise ValidationError("현재 증빙을 업로드할 수 없는 상태입니다.")

    proof = SettlementProof.objects.create(
        settlement=settlement,
        uploaded_by=user,
        image_url=image_url,
    )
    return proof


@transaction.atomic
def confirm_settlement(*, settlement: Settlement, user):
    if settlement.payee_user_id != user.id:
        raise PermissionDenied("수취인만 정산을 확인할 수 있습니다.")

    if settlement.status != "PAID_SELF":
        raise ValidationError("먼저 상대방이 송금 완료 처리를 해야 합니다.")

    has_proof = settlement.proofs.exists()

    settlement.status = "CONFIRMED"
    settlement.confirmed_at = timezone.now()
    settlement.verified_by = user
    settlement.verification_method = "PROOF_IMAGE" if has_proof else "MANUAL"
    settlement.save(
        update_fields=[
            "status",
            "confirmed_at",
            "verified_by",
            "verification_method",
        ]
    )
    return settlement


@transaction.atomic
def dispute_settlement(*, settlement: Settlement, user):
    if user.id not in [settlement.payer_user_id, settlement.payee_user_id]:
        raise PermissionDenied("정산 당사자만 이의제기할 수 있습니다.")

    if settlement.status not in ["REQUEST", "PAID_SELF"]:
        raise ValidationError("현재 이의제기할 수 없는 상태입니다.")

    settlement.status = "DISPUTED"
    settlement.save(update_fields=["status"])
    return settlement


@transaction.atomic
def complete_trip_settlement(*, trip, user):
    """
    리더가 해당 trip의 정산을 최종 완료 처리한다.
    - 모든 정산 요청을 CONFIRMED로 변경
    - 채팅방 공지 문구를 정산 완료 문구로 변경
    - 채팅방 만료 시간을 현재 시각 + 1시간으로 설정
    """
    _validate_trip_leader(trip=trip, user=user)

    settlements = list(
        Settlement.objects.filter(
            trip=trip,
        )
    )

    if not settlements:
        raise ValidationError("완료 처리할 정산 요청이 없습니다.")

    now = timezone.now()
    expires_at = now + timedelta(hours=1)

    for settlement in settlements:
        settlement.status = "CONFIRMED"
        settlement.confirmed_at = now
        settlement.verified_by = user
        settlement.verification_method = "MANUAL"
        settlement.save(
            update_fields=[
                "status",
                "confirmed_at",
                "verified_by",
                "verification_method",
            ]
        )
# 1. 매칭(Trip) 자체를 '완료' 상태로 변경
    trip.status = "COMPLETED"
    trip.save(update_fields=["status"])

    # 2. 참여자들의 탑승 횟수/매너 점수 증가 및 상태 마감
    participants = TripParticipant.objects.filter(trip=trip, status="JOINED")
    for p in participants:
        # 유저 DB 업데이트
        p.user.successful_streak_count += 1
        p.user.trust_score += 0.1  # 소수점 오류 방지를 위해 0.1 단위로 설정
        p.user.save(update_fields=["successful_streak_count", "trust_score"])

        # 참여자 상태 마감
        p.status = "SETTLED"
        p.save(update_fields=["status"])
    local_expires_at = timezone.localtime(expires_at)
    period = "오전" if local_expires_at.hour < 12 else "오후"
    hour_12 = local_expires_at.hour % 12
    if hour_12 == 0:
        hour_12 = 12

    notice = (
        f"정산이 완료되었습니다. "
        f"{period} {hour_12:02d}시{local_expires_at.minute:02d}분에 "
        f"채팅방이 자동 삭제 됩니다."
    )

    chat_room = ChatRoom.objects.filter(trip=trip).first()
    if chat_room:
        chat_room.pinned_notice = notice
        chat_room.expires_at = expires_at
        chat_room.is_archived = False
        chat_room.save(
            update_fields=[
                "pinned_notice",
                "expires_at",
                "is_archived",
            ]
        )
        channel_layer = get_channel_layer()
        if channel_layer:
            event = {
                "type": "broadcast_message",
                "message_type": "settlement_completed",
                "message": "정산이 완료되었습니다.",
                "pinned_notice": notice,
                "expires_at": expires_at.isoformat(),
            }

            async_to_sync(channel_layer.group_send)(
                f"chat_{trip.id}",
                event,
            )

            if chat_room.id != trip.id:
                async_to_sync(channel_layer.group_send)(
                    f"chat_{chat_room.id}",
                    event,
                )

    return {
        "pinned_notice": notice,
        "expires_at": expires_at,
    }
