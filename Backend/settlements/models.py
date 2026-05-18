from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models
from django.db.models import Q

from trips.models import Trip


class PaymentChannel(models.Model):
    PROVIDER_CHOICES = [
        ("KAKAOPAY", "KAKAOPAY"),
        ("TOSS", "TOSS"),
        ("OTHER", "OTHER"),
    ]
    
    trip = models.OneToOneField(
        Trip,
        on_delete=models.CASCADE,
        related_name="payment_channel",
    )
    
    provider = models.CharField(
        max_length=20,
        choices=PROVIDER_CHOICES,
        default="KAKAOPAY",
    )
    
    kakaopay_link = models.TextField(blank=True, null=True)
    updated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="payment_channels_updated",
    )
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"PaymentChannel for Trip {self.trip_id}"


class Receipt(models.Model):
    STATUS_CHOICES = [
        ("PENDING", "PENDING"),
        ("CONFIRMED", "CONFIRMED"),
    ]
    OCR_STATUS_CHOICES = [
        ("PENDING", "PENDING"),
        ("SUCCESS", "SUCCESS"),
        ("FAILED", "FAILED"),
        ("NEEDS_REVIEW", "NEEDS_REVIEW"),
    ]

    trip = models.OneToOneField(
        Trip,
        on_delete=models.CASCADE,
        related_name="receipt",
    )
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="receipts_uploaded",
    )
    image = models.ImageField(
        upload_to="receipts/%Y/%m/%d/",
        blank=True,
        null=True,
    )

    image_url = models.TextField(blank=True, null=True)

    total_amount = models.PositiveIntegerField(
        validators=[MinValueValidator(0)],
        blank=True,
        null=True,
    )
    ocr_raw_text = models.TextField(blank=True, null=True)

    extracted_total_amount = models.PositiveIntegerField(
        validators=[MinValueValidator(0)],
        blank=True,
        null=True,
    )

    extracted_departure_name = models.CharField(
        max_length=255,
        blank=True,
        null=True,
    )

    extracted_arrival_name = models.CharField(
        max_length=255,
        blank=True,
        null=True,
    )

    extracted_ride_time = models.DateTimeField(blank=True, null=True)

    ocr_status = models.CharField(
        max_length=20,
        choices=OCR_STATUS_CHOICES,
        default="PENDING",
    )
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default="PENDING")
    confirmed_at = models.DateTimeField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        constraints = [
            models.CheckConstraint(
                condition=Q(total_amount__gte=0),
                name="settlements_receipt_total_amount_nonnegative",
            ),
        ]
        
    def get_display_image_url(self):
        if self.image:
            return self.image.url
        return self.image_url

    def __str__(self):
        return f"Receipt for Trip {self.trip_id}"

class Settlement(models.Model):
    STATUS_CHOICES = [
        ("REQUEST", "REQUEST"),
        ("LINK_OPENED", "LINK_OPENED"),
        ("PAID_SELF", "PAID_SELF"),
        ("CONFIRMED", "CONFIRMED"),
        ("DISPUTED", "DISPUTED"),
        ("OVERDUE", "OVERDUE"),
        ("CANCELED", "CANCELED"),
    ]

    VERIFICATION_METHOD_CHOICES = [
        ("MANUAL", "MANUAL"),
        ("PROOF_IMAGE", "PROOF_IMAGE"),
    ]
    
    trip = models.ForeignKey(
    Trip,
    on_delete=models.CASCADE,
    related_name="settlements",
    )

    receipt = models.ForeignKey(
        Receipt,
        on_delete=models.CASCADE,
        related_name="settlements",
    )
    payer_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="settlements_to_pay",
    )
    payee_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="settlements_to_receive",
    )
    share_amount = models.PositiveIntegerField(validators=[MinValueValidator(0)])
    memo_code = models.CharField(max_length=20, blank=True, null=True)

    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default="REQUEST")
    verification_method = models.CharField(
        max_length=20,
        choices=VERIFICATION_METHOD_CHOICES,
        blank=True,
        null=True,
    )
    verified_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        blank=True,
        null=True,
        related_name="settlements_verified",
    )

    requested_at = models.DateTimeField(auto_now_add=True)
    link_opened_at = models.DateTimeField(blank=True, null=True)
    paid_self_at = models.DateTimeField(blank=True, null=True)
    confirmed_at = models.DateTimeField(blank=True, null=True)
    due_at = models.DateTimeField(blank=True, null=True)
    
    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["receipt", "payer_user"],
                name="unique_receipt_payer_settlement",
            ),
            models.CheckConstraint(
                condition=Q(share_amount__gte=0),
                name="settlements_settlement_share_amount_nonnegative",
            ),
            models.CheckConstraint(
                condition=~Q(payer_user=models.F("payee_user")),
                name="settlements_payer_payee_must_differ",
            ),
        ]

    def __str__(self):
        return f"Settlement {self.id} / receipt={self.receipt_id}"


class SettlementProof(models.Model):
    settlement = models.ForeignKey(
        Settlement,
        on_delete=models.CASCADE,
        related_name="proofs",
    )
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="settlement_proofs_uploaded",
    )
    image_url = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Proof for Settlement {self.settlement_id}"